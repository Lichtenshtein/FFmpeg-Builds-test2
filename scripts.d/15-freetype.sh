#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="d262bd978c3ea303289153dba1ae8a6dc4ac747a"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
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
        --without-harfbuzz
        --without-png
        --without-zlib
        --without-bzip2
        --without-brotli
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    CPPFLAGS="$CPPFLAGS -DFT2_BUILD_LIBRARY" \
    CXXFLAGS="$CXXFLAGS" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    local PC_DIR="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    local PC_ORIGIN="$PC_DIR/freetype2.pc"
    local PC_LINK="$PC_DIR/freetype.pc"
    if [[ -f "$PC_ORIGIN" ]]; then
        sed -i 's/[[:space:]]*$//' "$PC_ORIGIN"
        log_info "${SYNC_MARK} Patching FREETYPE .pc file..."
        if ! grep -q "FT2_BUILD_LIBRARY" "$PC_ORIGIN"; then
            sed -i '/^Cflags:/ s/$/ -DFT2_BUILD_LIBRARY/' "$PC_ORIGIN"
        fi
    else
        log_error "freetype2.pc not found!"
    fi

    # Создаем симлинк
    ln -sf freetype2.pc "$PC_LINK"

    get_deps_list
}
