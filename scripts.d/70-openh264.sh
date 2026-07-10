#!/bin/bash

SCRIPT_REPO="https://github.com/cisco/openh264.git"
SCRIPT_COMMIT="3bc90ba54124ad64a25f5845daf78d4949aae50d"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf test res gtest"
}

ffbuild_dockerbuild() {
    set -e

    export CFLAGS="$CFLAGS ${USELTO}${USELTO_C}"
    export CPPFLAGS="$CPPFLAGS"
    export CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}"
    export LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}"

    local myconf=(
        PREFIX="$FFBUILD_PREFIX"
        INCLUDE_PREFIX="$FFBUILD_PREFIX"/include/wels
        BUILDTYPE=Release
        DEBUGSYMBOLS=False
        LIBDIR_NAME=lib
        BUILD_UT_EXE=No
        CC="$CC"
        CXX="$CXX"
        AR="$AR"
    )

    if [[ $TARGET == win32 ]]; then
        myconf+=(
            OS=mingw_nt
            ARCH=i686
        )
    elif [[ $TARGET == win64 ]]; then
        myconf+=(
            OS=mingw_nt
            ARCH=x86_64
        )
    elif [[ $TARGET == winarm64 ]]; then
        myconf+=(
            OS=mingw_nt
            ARCH=aarch64
        )
    elif [[ $TARGET == linux64 ]]; then
        myconf+=(
            OS=linux
            ARCH=x86_64
        )
    elif [[ $TARGET == linuxarm64 ]]; then
        myconf+=(
            OS=linux
            ARCH=aarch64
        )
    fi

    make $MAKE_V -j$(nproc) "${myconf[@]}" install-static DESTDIR="$FFBUILD_DESTDIR" || return 1

    sed -i "s|^Cflags:.*|& -I\${includedir}/wels|" "$PC_DIR/openh264.pc"
}

ffbuild_configure() {
    echo --enable-libopenh264
}

ffbuild_unconfigure() {
    echo --disable-libopenh264
}
