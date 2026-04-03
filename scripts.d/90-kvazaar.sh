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
    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
    )

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS -DKVZ_STATIC_LIB" \
    CXXFLAGS="$CXXFLAGS -DKVZ_STATIC_LIB" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    echo "Cflags.private: -DKVZ_STATIC_LIB" >> "$PC_DIR/kvazaar.pc"
    echo "Libs.private: -pthread" >> "$PC_DIR/kvazaar.pc"

}

ffbuild_cppflags() {
    echo "-DKVZ_STATIC_LIB"
}

ffbuild_configure() {
    echo --enable-libkvazaar
}

ffbuild_unconfigure() {
    echo --disable-libkvazaar
}
