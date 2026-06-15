#!/bin/bash

SCRIPT_REPO="https://github.com/OpenMPT/openmpt.git"
SCRIPT_COMMIT="8a08807c8374034b81ddf6ca109786ad19a05f8a"

ffbuild_depends() {
    echo base
    echo zlib
    echo libvorbis
    echo libogg
    echo libmpg123
    echo sdl2
}

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf \
include \
build/vs2017win7 \
build/vs2017winxp \
build/vs2017winxpansi \
build/vs2017winxpx64 \
build/vs2019win7 \
build/vs2022win7 \
build/vs2022win8 \
build/vs2022win10 \
build/vs2022win10uwp \
build/vs2022win11 \
build/vs2022win11clang \
build/vs2022win11uwp \
build/vs2022win81 \
build/vs2026win11 \
build/vs2026win11clang \
build/vs2026win11uwp"
}

ffbuild_dockerbuild() {
    set -e

    find . -name "Makefile" -exec sed -i 's/-fvisibility=hidden//g' {} + 2>/dev/null || true

    export CFLAGS="$CFLAGS ${USELTO}${USELTO_C}"
    export CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}"
    export LDFLAGS="$LDFLAGS ${USELTO}"
    export CPPFLAGS="$CPPFLAGS"

    local myconf=(
        PREFIX="$FFBUILD_PREFIX"
        CXXSTDLIB_PCLIBSPRIVATE="-lstdc++"
        VERBOSE=2
        EXAMPLES=0
        OPENMPT123=0
        IN_OPENMPT=0
        XMP_OPENMPT=0
        DEBUG=0
        NATIVE=0
        OPTIMIZE=vectorize
        OPTIMIZE_FASTMATH=0
        TEST=0
        MODERN=1
        FORCE_DEPS=1
        NO_MINIMP3=0
        NO_ZLIB=0
        NO_OGG=0
        NO_VORBIS=0
        NO_VORBISFILE=0
        NO_MPG123=0
        # NO_SDL2=1
        # NO_PULSEAUDIO=1
        NO_SNDFILE=1
        NO_PORTAUDIO=1
        NO_PORTAUDIOCPP=1
        NO_FLAC=1
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( SHARED_LIB=1 STATIC_LIB=0 DYNLINK=1 ) || \
        myconf+=( SHARED_LIB=0 STATIC_LIB=1 DYNLINK=0 )

    # [[ "$USE_LTO" == "1" ]] && myconf+=( OPTIMIZE_LTO=1 )

    if [[ $TARGET == winarm64 ]]; then
        myconf+=(
            CONFIG=mingw-w64
            WINDOWS_ARCH=arm64
        )
        export CPPFLAGS="$CPPFLAGS -DMPT_WITH_MINGWSTDTHREADS"
    elif [[ $TARGET == win* ]]; then
        myconf+=(
            CONFIG=mingw-w64
            WINDOWS_ARCH=amd64
            WINDOWS_VERSION=win10
            MINGW_FLAVOUR=-posix
        )
        export CPPFLAGS="$CPPFLAGS -DMPT_WITH_MINGWSTDTHREADS"
    elif [[ $TARGET == linux* ]]; then
        myconf+=(
            CONFIG=gcc
            TOOLCHAIN_PREFIX="$FFBUILD_CROSS_PREFIX"
        )
    fi

    make $MAKE_V -j$(nproc) "${myconf[@]}" all install DESTDIR="$FFBUILD_DESTDIR" || return 1
    rm -r "$INSTALL_ROOT"/share/doc/libopenmpt

    sed -i "s|^Cflags:.*|& -I\${includedir}/libopenmpt|" "$PC_DIR/libopenmpt.pc"
}

ffbuild_configure() {
    echo --enable-libopenmpt
}

ffbuild_unconfigure() {
    echo --disable-libopenmpt
}
