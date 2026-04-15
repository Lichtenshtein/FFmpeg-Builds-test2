#!/bin/bash

SCRIPT_REPO="https://github.com/AOMediaCodec/libavif.git"
SCRIPT_COMMIT="226e112a833bbb3e98632492e4d766e37d661774"

ffbuild_depends() {
    echo libwebp
    echo zlib
    echo dav1d
    echo rav1e # 1 of 3
    echo aom # 1 of 3
    echo svtav1 # 1 of 3
    echo libxml2
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p "include/sharpyuv"

    local GLOBAL_INC="$FFBUILD_PREFIX/include"
    mkdir -p "include/sharpyuv"

    if [[ -d "$GLOBAL_INC/webp/sharpyuv" ]]; then
        cp -v "$GLOBAL_INC/webp/sharpyuv/"*.h "include/sharpyuv/"
    elif [[ -d "$GLOBAL_INC/sharpyuv" ]]; then
        cp -v "$GLOBAL_INC/sharpyuv/"*.h "include/sharpyuv/"
    else
        log_error "Sharpyuv NOT found in $GLOBAL_INC"
        find "$GLOBAL_INC" -name "*sharpyuv*" >&2
        return 1
    fi

    cat <<EOF > fix_targets.cmake
add_library(sharpyuv::sharpyuv STATIC IMPORTED GLOBAL)
set_target_properties(sharpyuv::sharpyuv PROPERTIES 
    IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/libsharpyuv.a"
    INTERFACE_INCLUDE_DIRECTORIES "\${CMAKE_CURRENT_SOURCE_DIR}/include"
    AVIF_LOCAL OFF)

add_library(LibXml2::LibXml2 STATIC IMPORTED GLOBAL)
set_target_properties(LibXml2::LibXml2 PROPERTIES 
    IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/libxml2.a"
    INTERFACE_INCLUDE_DIRECTORIES "$FFBUILD_PREFIX/include/libxml2"
    AVIF_LOCAL OFF)

include_directories(BEFORE "\${CMAKE_CURRENT_SOURCE_DIR}/include")
EOF

    sed -i '1i include("${CMAKE_CURRENT_SOURCE_DIR}/fix_targets.cmake")' CMakeLists.txt
    sed -i 's/check_avif_option(AVIF_LIBSHARPYUV.*/set(AVIF_LIBSHARPYUV_ENABLED ON)/' CMakeLists.txt
    sed -i 's/check_avif_option(AVIF_LIBXML2.*/set(AVIF_LIBXML2_ENABLED ON)/' CMakeLists.txt
    sed -i 's/find_package(libsharpyuv/#/' CMakeLists.txt
    sed -i 's/find_package(LibXml2/#/' CMakeLists.txt

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_PREFIX_PATH="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DAVIF_BUILD_TESTS=OFF
        -DAVIF_BUILD_APPS=OFF
        -DAVIF_BUILD_EXAMPLES=OFF
        # Включаем поддержку внешнего декодера dav1d
        -DAVIF_CODEC_DAV1D=SYSTEM # Декодер
        -DAVIF_CODEC_DAV1D_ENABLED=ON
        -DAVIF_LIBSHARPYUV=SYSTEM # stupidly fails if no .cmake files found
        -DAVIF_LIBXML2=SYSTEM # convert JPEG with gain maps to AVIF using avifenc; doesn't find a shit
        -DAVIF_JPEG=SYSTEM
        -DAVIF_ZLIBPNG=SYSTEM
        # aom создаёт проблему курицы и яйца
        -DAVIF_CODEC_AOM=OFF
        -DAVIF_CODEC_SVT=SYSTEM # Используем SVT-AV1 как энкодер!
        -DAVIF_LIBYUV=LOCAL # Донор libyuv для aom
        # use rav1e instead of AOM or SVT
        #-DAVIF_CODEC_RAV1E=SYSYEM
        #-DAVIF_CODEC_RAV1E_ENABLED=ON
        -DAVIF_OPTIMIZE_RAV1E_FOR_SIZE=ON
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Извлекаем libyuv.a для послудующих стадий (она лежит в _deps/libyuv-build/)
    cp "_deps/libyuv-build/libyuv.a" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/libyuv"
    cp -r "_deps/libyuv-src/include/"* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/libyuv/"

    # Создаем pkg-config файл вручную, чтобы aom и avif-v2 его нашли
    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/libyuv.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libyuv
Description: YUV conversion and scaling library (extracted from libavif)
Version: 1.0.0
Libs: -L\${libdir} -lyuv
Libs.private: -lstdc++
Cflags: -I\${includedir}
EOF
}
