#!/bin/bash

SCRIPT_REPO="https://github.com/webmproject/libvpx.git"
SCRIPT_COMMIT="30f3852521b11b5e361ec1eaeef5a12730bfe90f"

ffbuild_depends() {
    echo libavif # for libyuv
}

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    local myconf=(
        --as="nasm"
        --cpu="${CPU_TUNE:-broadwell}"
        --disable-debug
        --disable-docs
        --disable-examples
        --disable-realtime-only
        --disable-tools
        --disable-unit-tests
        --enable-better-hw-compatibility
        --enable-ccache
        --enable-libyuv
        --enable-multi-res-encoding
        --enable-multithread
        --enable-pic
        --enable-postproc
        --enable-postproc-visualizer
        --enable-runtime-cpu-detect
        --enable-spatial-resampling
        --enable-vp8
        --enable-vp9
        --enable-vp9-highbitdepth
        --enable-vp9-postproc
        --enable-vp9-temporal-denoising
        --enable-webm-io # input from and output to WebM container
        --prefix="$FFBUILD_PREFIX"
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    if [[ $TARGET == win64 ]]; then
        myconf+=( --target=x86_64-win64-gcc )
        export CROSS="$FFBUILD_CROSS_PREFIX"
    elif [[ $TARGET == linux64 ]]; then
        myconf+=(
            --target=x86_64-linux-gcc
        )
        export CROSS="$FFBUILD_CROSS_PREFIX"
    fi

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Исправление для LTO
    # Work around strip breaking LTO symbol index
    # "$RANLIB" "$FFBUILD_DESTPREFIX"/lib/libvpx.a
    "$RANLIB" "$INSTALL_ROOT/lib/libvpx.a"

    sed -i "s|^Cflags:.*|& -I${includedir}/vpx|" "$PC_DIR/vpx.pc"
}

ffbuild_configure() {
    echo --enable-libvpx
}

ffbuild_unconfigure() {
    echo --disable-libvpx
}
