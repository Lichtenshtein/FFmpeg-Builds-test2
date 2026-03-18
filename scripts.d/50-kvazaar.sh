#!/bin/bash

SCRIPT_REPO="https://github.com/ultravideo/kvazaar.git"
SCRIPT_COMMIT="45597d8de2e3ef7695ac54e8a3372572c4bb8213"

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
    )

    ./configure "${myconf[@]}" \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS" \
        CPPFLAGS="$CPPFLAGS" \
        CXXFLAGS="$CXXFLAGS" \
        LIBS="$LIBS" || return 1
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    echo "Cflags.private: -DKVZ_STATIC_LIB" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/kvazaar.pc
    echo "Libs.private: -lpthread" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/kvazaar.pc

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libkvazaar
}

ffbuild_unconfigure() {
    echo --disable-libkvazaar
}
