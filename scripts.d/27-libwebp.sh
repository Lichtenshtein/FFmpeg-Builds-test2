#!/bin/bash

SCRIPT_REPO="https://github.com/webmproject/libwebp.git"
SCRIPT_COMMIT="f342dfc1756785df8803d25478bf664c0de629de"

ffbuild_depends() {
    echo libpng
    echo libjpeg-turbo
    echo libtiff
    echo giflib
    echo zlib
    echo zstd
    echo xz
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

    # Порядок: WebP -> TIFF -> [JPEG, JBIG, LZMA, Z]
    local WEBP_DEPS="-ltiff -ltiffxx -ljpeg -lturbojpeg -lpng16 -lgif -lzstd -llzma -ljbig -ljbig85 -lz $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
        --enable-everything
        --disable-gl
        --disable-sdl
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    ./configure "${myconf[@]}" \
        CFLAGS="$CFLAGS -DWEBP_STATIC" \
        LDFLAGS="$LDFLAGS $WEBP_DEPS" \
        CPPFLAGS="$CPPFLAGS -DWEBP_STATIC" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    # libwebp генерирует несколько .pc файлов (libwebp, libwebpmux, libsharpyuv)
    # Нужно убедиться, что они содержат системные либы для Windows
    for pc in libwebp.pc libwebpmux.pc libwebpdemux.pc libwebpdecoder.pc libsharpyuv.pc; do
        local PC_PATH="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/$pc"
        [[ -f "$PC_PATH" ]] || continue
        log_info "${SYNC_MARK} Patching $(basename $pc)..."
        sed -i "/^Cflags:/ s/$/ -DWEBP_STATIC/" "$PC_PATH"
        sed -i "/^Libs\.private:/d" "$PC_FILE"
        echo "Libs.private: $WEBP_DEPS" >> "$PC_FILE"
    done

    get_deps_list
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
