#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/fontconfig/fontconfig.git"
SCRIPT_COMMIT="6d0a98982ec351c165c9224c8b7dbdfca3010e47"

ffbuild_depends() {
    echo base
    echo libxml2
    echo libiconv
    echo freetype
    echo gettext
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    ./autogen.sh --noconf

    # Fontconfig требует либо expat, либо libxml2.
    local FC_LIBS="-lxml2 -lfreetype -lharfbuzz -lharfbuzz-icu -lsicuin -lsicuuc -lsicudt -lpng16 -lbrotlidec -lbrotlicommon -lbz2 -lz -lintl -liconv -lcharset"

    local myconf=(
        ac_cv_va_copy="C99"
        --prefix="$FFBUILD_PREFIX"
        --enable-static
        --disable-shared
        --disable-docbook
        --disable-docs
        # --disable-nls
        --disable-cache-build
        --enable-libxml2
        --enable-iconv
        --with-arch=x86_64
        --with-default-sub-pixel-rendering=rgb
        --with-pic
    )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --sysconfdir=/etc
            --localstatedir=/var
            --host="$FFBUILD_TOOLCHAIN"
        )
    elif [[ $TARGET == win* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return 1
    fi

    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    ./configure "${myconf[@]}" \
        CFLAGS="$CFLAGS" \
        CPPFLAGS="$CPPFLAGS -I$FFBUILD_PREFIX/include/libxml2" \
        LDFLAGS="$LDFLAGS" \
        LIBS="$FC_LIBS $LIBS" \
        CC="${FFBUILD_TOOLCHAIN}-gcc" \
        CXX="${FFBUILD_TOOLCHAIN}-g++"

    # —начала генерируем заголовки (это создаст fcconst.h)
    # make -C fc-lang -j$(nproc) $MAKE_V CCLD="${FFBUILD_TOOLCHAIN}-g++"
    # make -C fc-case -j$(nproc) $MAKE_V CCLD="${FFBUILD_TOOLCHAIN}-g++"
    # make -C fc-const -j$(nproc) $MAKE_V CCLD="${FFBUILD_TOOLCHAIN}-g++"

    # “еперь собираем библиотеку. ≈сли упадет на fc-cache Ч игнорируем (|| true)
    # make -j$(nproc) $MAKE_V CCLD="${FFBUILD_TOOLCHAIN}-g++" || log_warn "Main make failed (expected due to fc-cache), proceeding to library install..."
    make -j$(nproc) $MAKE_V CCLD="${FFBUILD_TOOLCHAIN}-g++"

    # ”станавливаем только саму библиотеку и инклюды
    make install DESTDIR="$FFBUILD_DESTDIR"
    # make -C src install DESTDIR="$FFBUILD_DESTDIR"
    # make install-data-am DESTDIR="$FFBUILD_DESTDIR"

    clean_la_files

    rm -rf "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/{var,etc}

    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/fontconfig.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "${SYNC_MARK} Patching fontconfig.pc..."
        # √арантируем, что Libs.private содержит весь хвост
        sed -i "s|^Libs.private:.*|Libs.private: $FC_LIBS $LIBS -lole32 -luuid|" "$PC_FILE"
    fi

    get_deps_list
}

ffbuild_configure() {
    echo --enable-fontconfig
}

ffbuild_unconfigure() {
    echo --disable-fontconfig
}
