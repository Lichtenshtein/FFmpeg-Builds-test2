#!/bin/bash

# SCRIPT_REPO="https://github.com/libass/libass.git"
# SCRIPT_COMMIT="fadc390583f24eb5cf98f16925fd3adee50bca88"

SCRIPT_REPO="https://github.com/amanosatosi/libassmod.git"
SCRIPT_COMMIT="beb9f3960b022a2f51cd08ddc9c39fa29b30b5af"

ffbuild_depends() {
    echo base
    echo libiconv
    echo freetype
    echo fontconfig
    echo harfbuzz
    echo fribidi
    echo libunibreak
    # echo libpng
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
        # --enable-compare # compare program (requires libpng)
        --with-pic
        --disable-test
        --enable-wrap-unicode
        --enable-directwrite
        --enable-libunibreak
        # --enable-large-tiles # in the rasterizer (better performance, slightly worse quality)
        --enable-asm
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS -Dread_file=libass_internal_read_file ${USELTO}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1
}

ffbuild_configure() {
    echo --enable-libass
}

ffbuild_unconfigure() {
    echo --disable-libass
}
