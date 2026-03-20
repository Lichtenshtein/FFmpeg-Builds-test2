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

    ./configure "${myconf[@]}" \
        CFLAGS="$CFLAGS -DFT2_BUILD_LIBRARY" \
        LDFLAGS="$LDFLAGS" \
        CPPFLAGS="$CPPFLAGS -DFT2_BUILD_LIBRARY" \
        CXXFLAGS="$CXXFLAGS -DFT2_BUILD_LIBRARY" \
        LIBS="$LIBS" || return 1
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    # Создаем симлинк для совместимости
    ln -sf freetype2.pc "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/freetype.pc"

    log_info "${SYNC_MARK} Patching FREETYPE .pc file..."
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/freetype.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i '/^Cflags:/ s/$/ -DFT2_BUILD_LIBRARY/' "$pc"
    fi

    get_deps_list
}
