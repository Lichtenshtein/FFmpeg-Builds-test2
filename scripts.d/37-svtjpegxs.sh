#!/bin/bash

SCRIPT_REPO="https://github.com/OpenVisualCloud/SVT-JPEG-XS.git"
SCRIPT_COMMIT="97c2e23f39738440db2bb1760683058d372bba9b"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # отключаем автоматическое определение архитектуры хоста
    # чтобы он не взял флаги процессора GitHub раннера
    sed -i 's/-march=native//g' CMakeLists.txt || true

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_TESTING=OFF
        -DBUILD_APPS=OFF
        -DENABLE_NATIVE=OFF
        -DENABLE_NASM=ON
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
    )

    # Специальные флаги для MinGW, чтобы избежать сегфолтов
    # -mstackrealign (выравнивание стека для cflags moved to base_cflags)
    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -fno-asynchronous-unwind-tables" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -fno-asynchronous-unwind-tables" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # # Check library names - SVT-JPEG-XS might use different library names
    # ls $INSTALL_ROOT/lib/libSvt*
    # # Check header locations:
    # ls $INSTALL_ROOT/include/svt-jpegxs/

    # echo "=== Installed files ==="
    # find "$FFBUILD_DESTDIR" -type f

    # # Create pkg-config files manually if they don't exist
    # if [[ ! -f "$PC_DIR/SvtJpegxsEnc.pc" ]]; then
        # mkdir -p "$PC_DIR"
        
        # cat > "$PC_DIR/SvtJpegxsEnc.pc" <<EOF
# prefix=$FFBUILD_PREFIX
# exec_prefix=\${prefix}
# libdir=\${prefix}/lib
# includedir=\${prefix}/include

# Name: SvtJpegxsEnc
# Description: SVT JPEG XS Encoder
# Version: 0.9
# Libs: -L\${libdir} -lSvtJpegxsEnc
# Libs.private: -lstdc++ -lpthread -lm
# Cflags: -I\${includedir}
# EOF

        # cat > "$PC_DIR/SvtJpegxsDec.pc" <<EOF
# prefix=$FFBUILD_PREFIX
# exec_prefix=\${prefix}
# libdir=\${prefix}/lib
# includedir=\${prefix}/include

# Name: SvtJpegxsDec
# Description: SVT JPEG XS Decoder
# Version: 0.9
# Libs: -L\${libdir} -lSvtJpegxsDec
# Libs.private: -lstdc++ -pthread -lm
# Cflags: -I\${includedir}
# EOF
    # fi

    for pc in "$PC_DIR"/SvtJpegxs*.pc; do
        [[ -f "$pc" ]] || continue
        # Исправляем префикс
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$pc"
    done

    # FFmpeg иногда ищет просто svtjpegxs.pc. Создадим алиас.
    if [[ -f "$PC_DIR/SvtJpegxsEnc.pc" ]]; then
        cp "$PC_DIR/SvtJpegxsEnc.pc" \
           "$PC_DIR/svtjpegxs.pc"
    fi
}

ffbuild_configure() {
    echo --enable-libsvtjpegxs
}

ffbuild_unconfigure() {
    echo --disable-libsvtjpegxs
}