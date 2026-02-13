#!/bin/bash

SCRIPT_REPO="https://chromium.googlesource.com/webm/libvpx"
SCRIPT_COMMIT="d5399cdd6abea1169a246f28c5ca9a50975d7ba9"

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
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
        # ВКЛЮЧАЕМ ОПТИМИЗАЦИИ
        --enable-realtime-only
        --enable-runtime-cpu-detect
        --enable-postproc
        --enable-multi-res-encoding
        --enable-vp9-temporal-denoising
    )

    if [[ $TARGET == win64 ]]; then
        myconf+=( --target=x86_64-win64-gcc )
        # Принудительно передаем флаги Broadwell через окружение для configure
        export CFLAGS="$CFLAGS -march=broadwell -mtune=broadwell"
        export CXXFLAGS="$CXXFLAGS -march=broadwell -mtune=broadwell"
    fi

    # libvpx не любит стандартный CROSS, ему нужен конкретный префикс
    CROSS="$FFBUILD_CROSS_PREFIX" ./configure "${myconf[@]}"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправление для LTO
    # Work around strip breaking LTO symbol index
    # "$RANLIB" "$FFBUILD_DESTPREFIX"/lib/libvpx.a
    "$RANLIB" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libvpx.a"
}

ffbuild_configure() {
    echo --enable-libvpx
}

ffbuild_unconfigure() {
    echo --disable-libvpx
}
