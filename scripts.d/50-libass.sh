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
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    apply_patches

    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
        --enable-wrap-unicode
        --enable-directwrite
    )

    export CFLAGS="$CFLAGS -Dread_file=libass_internal_read_file"

    ./configure "${myconf[@]}" \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS" \
        CPPFLAGS="$CPPFLAGS" \
        CXXFLAGS="$CXXFLAGS" \
        LIBS="$LIBS" || return 1
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libass
}

ffbuild_unconfigure() {
    echo --disable-libass
}
