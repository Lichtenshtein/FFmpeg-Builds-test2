#!/bin/bash

SCRIPT_REPO="https://github.com/OpenVisualCloud/SVT-JPEG-XS.git"
SCRIPT_COMMIT="8e50180ad909a0bdcdf91b462c64033f0fe3e112"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    log_info "🔧 Patching SvtJpegxs internal API macros for forced static linking..."

    find . -type f -name "SvtJpegxs*.h" | while read -r header; do
        if ! grep -q "FORCE_STATIC_FIX" "$header"; then
            sed -i '1i #define FORCE_STATIC_FIX\n#ifdef PREFIX_API\n#undef PREFIX_API\n#endif\n#define PREFIX_API' "$header"
            log_debug "Forced static macros applied to: $(basename "$header")"
        fi
    done

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
    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -fno-asynchronous-unwind-tables -mstackrealign" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -fno-asynchronous-unwind-tables -mstackrealign" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    for PC_FILE in "$PC_DIR"/SvtJpegxs*.pc; do
        [[ -f "$PC_FILE" ]] || continue
        # Исправляем префикс
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        if ! grep -q -- "-lstdc++" "$PC_FILE"; then
            sed -i '/^Libs.private:/ s/$/ -lstdc++/' "$PC_FILE"
        fi
        sed -i 's|^Cflags:.*|Cflags: -I${includedir} -I${includedir}/svt-jpegxs -UDEF_DLL|' "$PC_FILE"
    done

    # FFmpeg иногда ищет просто svtjpegxs.pc. Создадим алиас.
    if [[ -f "$PC_DIR/SvtJpegxsEnc.pc" ]]; then
        cp "$PC_DIR/SvtJpegxsEnc.pc" "$PC_DIR/svtjpegxs.pc"
    fi
}

ffbuild_configure() {
    echo --enable-libsvtjpegxs
}

ffbuild_unconfigure() {
    echo --disable-libsvtjpegxs
}