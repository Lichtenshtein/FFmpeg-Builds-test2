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

    local DEP_LIBS="-ltiffxx -ltiff -lturbojpeg -ljpeg -lpng16 -lgif"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
        --enable-everything
        --enable-near-lossless
        --enable-swap-16bit-csp
        --disable-gl
        --disable-sdl
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS -DWEBP_STATIC" \
    CXXFLAGS="$CXXFLAGS -DWEBP_STATIC" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$DEP_LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # libwebp генерирует несколько .pc файлов (libwebp, libwebpmux, libsharpyuv)
    for pc in libwebp.pc libwebpmux.pc libwebpdemux.pc libwebpdecoder.pc libsharpyuv.pc; do
        local PC_PATH="$PC_DIR/$pc"
        [[ -f "$PC_PATH" ]] || continue
        sed -i "/^Cflags:/ s/$/ -DWEBP_STATIC/" "$PC_PATH"
        sed -i "/^Libs\.private:/d" "$PC_PATH"
        echo "Libs.private: $DEP_LIBS" >> "$PC_PATH"
    done

}

ffbuild_cppflags() {
    echo "-DWEBP_STATIC"
}

ffbuild_configure() {
    echo --enable-libwebp
}

ffbuild_unconfigure() {
    echo --disable-libwebp
}
