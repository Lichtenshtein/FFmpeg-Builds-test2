#!/bin/bash

SCRIPT_REPO="https://github.com/PCRE2Project/pcre2.git"
SCRIPT_COMMIT="123424f8a2267aa12ef819c64744b9cea934e414"

ffbuild_depends() {
    echo zlib
    echo bzlib
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e
    ./autogen.sh

    local DEP_LIBS="-lbz2 -lz $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-static
        --disable-shared
        --enable-pcre2-8
        #--enable-pcre2-16
        #--enable-pcre2-32
        --with-link-size=3
        --with-parens-nest-limit=500
        --enable-jit
        --enable-unicode
        --enable-newline-is-anycrlf
        LDFLAGS="$LDFLAGS $DEP_LIBS"
        LIBS="$DEP_LIBS"
    )

    ./configure "${myconf[@]}"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    get_deps_list
}
