#!/bin/bash

SCRIPT_REPO="https://github.com/AOMediaCodec/libavif.git"
SCRIPT_COMMIT="226e112a833bbb3e98632492e4d766e37d661774"

ffbuild_depends() {
    echo libwebp
    echo zlib
    echo dav1d
    echo rav1e
    echo aom
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    export PKG_CONFIG_LIBDIR="${FFBUILD_PREFIX}/lib/pkgconfig:${FFBUILD_PREFIX}/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="/"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DAVIF_BUILD_TESTS=OFF
        -DAVIF_BUILD_APPS=OFF
        -DAVIF_BUILD_EXAMPLES=OFF
        # Включаем поддержку внешнего декодера dav1d
        -DAVIF_CODEC_DAV1D=SYSTEM
        -DAVIF_CODEC_DAV1D_ENABLED=ON
        -DAVIF_LIBSHARPYUV=SYSTEM
        # Если есть aom, можно включить энкодер
        -DAVIF_CODEC_AOM=OFF
        -DAVIF_LIBYUV=LOCAL
        -DAVIF_OPTIMIZE_RAV1E_FOR_SIZE=OFF
        -DENABLE_WERROR=OFF
        -DENABLE_GOLDEN_TESTS=OFF
    )

         # -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" || return 1

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1
    
    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}
