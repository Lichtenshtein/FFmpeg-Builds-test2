#!/bin/bash

SCRIPT_REPO="https://github.com/OpenMPT/openmpt.git"
SCRIPT_COMMIT="a2b251c67ca757bb181a0cd4cc97e9e94bfe2608"

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
}

ffbuild_dockerbuild() {
    set -e

    export CFLAGS="$CFLAGS"
    export CXXFLAGS="$CXXFLAGS"
    export LDFLAGS="$LDFLAGS"
    export CPPFLAGS="$CPPFLAGS"

    local myconf=(
        PREFIX="$FFBUILD_PREFIX"
        # CXXSTDLIB_PCLIBSPRIVATE="-lstdc++"
        VERBOSE=2
        EXAMPLES=0
        OPENMPT123=0
        IN_OPENMPT=0
        XMP_OPENMPT=0
        DEBUG=0
        NATIVE=0
        OPTIMIZE=vectorize
        OPTIMIZE_FASTMATH=1
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

    [[ "$USE_LTO" == "1" ]] && myconf+=( OPTIMIZE_LTO=1 )

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
    rm -r "$FFBUILD_DESTPREFIX"/share/doc/libopenmpt
}

ffbuild_configure() {
    echo --enable-libopenmpt
}

ffbuild_unconfigure() {
    echo --disable-libopenmpt
}
