#!/bin/bash

SCRIPT_REPO="https://github.com/mccakit/fdk-aac.git"
SCRIPT_COMMIT="2e5642ea1e5dc4a1d2f0c2f331729acc9866caed"
SCRIPT_BRANCH="HDC-encoder-PS-patch"

ffbuild_enabled() {
    # [[ $VARIANT == nonfree* ]] || return 1
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
        --disable-example
    )

    # Флаги санитайзера
    local asan_flags="-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize=shift-base -fno-sanitize-recover=all"
    
    CFLAGS="$CFLAGS $asan_flags" \
    CPPFLAGS="$CPPFLAGS $asan_flags" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS $asan_flags" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libfdk-aac
}

ffbuild_unconfigure() {
    echo --disable-libfdk-aac
}
