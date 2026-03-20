#!/bin/bash

SCRIPT_REPO="https://github.com/webmproject/libvpx.git"
SCRIPT_COMMIT="30f3852521b11b5e361ec1eaeef5a12730bfe90f"

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

    local myconf=(
        --disable-shared
        --enable-static
        --enable-pic
        --disable-examples
        --disable-tools
        --disable-docs
        --disable-unit-tests
        --enable-vp9-highbitdepth
        --prefix="$FFBUILD_PREFIX"
        --enable-realtime-only
        --enable-runtime-cpu-detect
        --enable-postproc
        --enable-multi-res-encoding
        --enable-multithread
        --enable-better-hw-compatibility
        --enable-webm-io
        --enable-postproc-visualizer
        --enable-vp9-temporal-denoising
    )

    if [[ $TARGET == win64 ]]; then
        myconf+=( --target=x86_64-win64-gcc )
    fi

    # libvpx не любит стандартный CROSS, ему нужен конкретный префикс
    CROSS="$FFBUILD_CROSS_PREFIX" ./configure "${myconf[@]}" \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS" \
        CPPFLAGS="$CPPFLAGS" \
        CXXFLAGS="$CXXFLAGS" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    # Исправление для LTO
    # Work around strip breaking LTO symbol index
    # "$RANLIB" "$FFBUILD_DESTPREFIX"/lib/libvpx.a
    "$RANLIB" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libvpx.a"

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libvpx
}

ffbuild_unconfigure() {
    echo --disable-libvpx
}
