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
    )

    ./configure "${myconf[@]}" \
        CFLAGS="$CFLAGS -DPCRE2_STATIC" \
        LDFLAGS="$LDFLAGS $DEP_LIBS" \
        CPPFLAGS="$CPPFLAGS -DPCRE2_STATIC" \
        CXXFLAGS="$CXXFLAGS -DPCRE2_STATIC" || return 1
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    log_info "${SYNC_MARK} Patching PRCE .pc files..."
    for pc in "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/lib/pkgconfig/*pcre2*.pc; do
        [[ -e "$pc" ]] || continue
        sed -i '/^Cflags:/ s/$/ -DPCRE2_STATIC/' "$pc"
        sed -i "/Libs.private:/ s/$/ -lpthread/" "$pc"
    done

    clean_la_files

    get_deps_list
}

ffbuild_cppflags() {
    echo "-DPCRE2_STATIC"
}

ffbuild_configure() {
    echo --enable-pcre
}

ffbuild_unconfigure() {
    echo --disable-pcre
}
