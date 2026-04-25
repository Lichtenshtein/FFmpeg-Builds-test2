#!/bin/bash

SCRIPT_REPO="https://github.com/xiph/theora.git"
SCRIPT_COMMIT="edfba372beb02ff70a1e2797d8cf561c242d0e0b"

ffbuild_depends() {
    echo base
    # checks for support libraries and headers:
    # echo libpng
    # echo cairo # only for --enable-telemetry (visual debugging of vector motion)
    # echo sdl # SDL 1.2 (not SDL2-3) for player_example (демо-плеера)
    # echo vorbis
    # echo libtiff # only for the png2theora utility; -ltiff cannot be found
    # echo libogg
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-pic
        --disable-examples
        --disable-oggtest
        --disable-vorbistest
        --disable-spec
        --disable-doc
        --enable-asm
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
        --enable-cuda # this added by patch; needs nvcc
        )
    fi

    # may need NOLTO
    CFLAGS="$CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/theora.pc"
    if [[ -f "$PC_FILE" ]]; then
        if ! grep -q "Requires:" "$PC_FILE"; then
            sed -i '/^Libs:/i Requires: ogg' "$PC_FILE"
        fi
    fi
}

ffbuild_configure() {
    echo --enable-libtheora
}

ffbuild_unconfigure() {
    echo --disable-libtheora
}
