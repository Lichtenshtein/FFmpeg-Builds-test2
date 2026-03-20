#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/libxml2.git"
SCRIPT_COMMIT="2cc5834033db61fb7adc242fb15f7d1e13f66c14"

ffbuild_depends() {
    echo base
    echo libiconv
    echo zlib
    echo libicu
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

    local XML_DEPS="-llzma -lz -lintl -liconv -lcharset -lsicuin -lsicuuc -lsicudt $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --without-python
        --without-debug
        --without-catalog
        --without-docs
        --without-modules
        --disable-maintainer-mode
        --disable-shared
        --enable-static
        --with-pic
        --with-icu
        --with-thread-alloc
        --with-winpath
        --with-zlib
        --with-iconv
        --with-tls
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    # Принудительно задаем AR как gcc-ar для стабильности архивации
    ./autogen.sh "${myconf[@]}" \
        CFLAGS="$CFLAGS -DLIBXML_STATIC -DXML_STATIC" \
        CPPFLAGS="$CPPFLAGS -DLIBXML_STATIC -DXML_STATIC" \
        LDFLAGS="$LDFLAGS" \
        AR="${FFBUILD_TOOLCHAIN}-gcc-ar" \
        NM="${FFBUILD_TOOLCHAIN}-gcc-nm" \
        RANLIB="${FFBUILD_TOOLCHAIN}-gcc-ranlib" \
        CC="${FFBUILD_TOOLCHAIN}-gcc" \
        CXX="${FFBUILD_TOOLCHAIN}-g++" || return 1

    make -j$(nproc) $MAKE_V CCLD="${FFBUILD_TOOLCHAIN}-g++" || {
    # Tool executables (xmllint/xmlcatalog) may fail due to libstdc++ conflict
    # The library itself (libxml2.a) is built correctly — proceed with install
    log_warn "make failed (likely xmllint/xmlcatalog tool linking) — checking if libxml2.a exists..."
    [[ -f ".libs/libxml2.a" ]] || { log_error "libxml2.a not built!"; return 1; }
    log_warn "libxml2.a confirmed present, proceeding with install."
} || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libxml-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "${SYNC_MARK} Cleaning and fixing libxml-2.0.pc..."

        # Очищаем основную строку Libs (оставляем только саму либу)
        sed -i "s|^Libs:.*|Libs: -L\${libdir} -lxml2|" "$PC_FILE"

        # Убираем Requires (zlib и icu), так как мы пропишем их явно в Libs.private 
        # Это предотвратит путаницу, если pkg-config не найдет icu-uc.pc
        sed -i "s|^Requires:.*|Requires:|" "$PC_FILE"

        # Формируем чистую Libs.private (без дубликатов)
        # Используем XML_DEPS (icu, lzma, iconv, intl, z) и системные LIBS
        local FINAL_PRIVATE=$(echo "$XML_DEPS" | xargs -n1 | sort -u | xargs)

        # Удаляем старую строку Libs.private если она была, и пишем новую
        sed -i "/^Libs\.private:/d" "$PC_FILE"
        echo "Libs.private: $FINAL_PRIVATE" >> "$PC_FILE"

        # Добавляем оба макроса статики
        # Проверяем, чтобы не добавить дубликат LIBXML_STATIC
        sed -i "s/-DLIBXML_STATIC//" "$PC_FILE"
        sed -i "/^Cflags:/ s/$/ -DLIBXML_STATIC -DXML_STATIC/" "$PC_FILE"
    fi

    get_deps_list
}

ffbuild_cppflags() {
    echo "-DLIBXML_STATIC -DXML_STATIC"
}

ffbuild_configure() {
    echo --enable-libxml2
}

ffbuild_unconfigure() {
    echo --disable-libxml2
}
