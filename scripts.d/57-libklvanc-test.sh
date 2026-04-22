#!/bin/bash

SCRIPT_REPO="https://github.com/stoth68000/libklvanc.git"
SCRIPT_COMMIT="d2bec177f68fe807a8c12d3b8d18ee8208bbdc32"

ffbuild_enabled() {
    [[ $TARGET == linux* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    grep -rl "sys/errno.h" . | xargs sed -i 's|sys/errno.h|errno.h|g'

    ./autogen.sh --build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-examples
        --disable-gtk-doc
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1
}

ffbuild_configure() {
    echo --enable-libklvanc
}

ffbuild_unconfigure() {
    echo --disable-libklvanc
}
