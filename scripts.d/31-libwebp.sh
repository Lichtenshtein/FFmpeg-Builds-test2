#!/bin/bash

SCRIPT_REPO="https://github.com/webmproject/libwebp.git"
SCRIPT_COMMIT="f342dfc1756785df8803d25478bf664c0de629de"

ffbuild_depends() {
    echo libpng
    echo libjpeg-turbo
    echo libtiff
    echo giflib
    echo zlib
    # echo zstd
    # echo xz
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    ./autogen.sh

    # почему-то нужен для libwebp
    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"

    local DEP_LIBS="-ltiffxx -ltiff -lturbojpeg -ljpeg -lpng16 -lgif -ljbig -lzstd -llzma -lz"
    local WIN_LIBS="-lgdi32 -lmsimg32 -ldwrite -ld2d1 -lwindowscodecs -lopengl32 $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-pic
        --enable-everything
        --enable-near-lossless
        --enable-swap-16bit-csp
        --disable-gl
        --disable-sdl
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    local static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DWEBP_STATIC"

    CFLAGS="$CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $static_flags ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    JPEG_LIBS="-lturbojpeg -ljpeg" \
    LIBS="$DEP_LIBS $WIN_LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    for pc in libwebp.pc libwebpmux.pc libwebpdemux.pc libwebpdecoder.pc libsharpyuv.pc; do
        local PC_PATH="$PC_DIR/$pc"
        [[ -f "$PC_PATH" ]] || continue
        sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_PATH"
    done
}

ffbuild_libs() {
    echo "-lwebpmux -lwebpdemux -lwebp -lwebpdecoder -lsharpyuv"
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-libwebp
}

ffbuild_unconfigure() {
    echo --disable-libwebp
}
