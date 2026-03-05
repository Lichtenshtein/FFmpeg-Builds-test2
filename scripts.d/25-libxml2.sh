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

    local XML_DEPS="-lpthread -lsicuin -lsicuuc -lsicudt -llzma -liconv -lcharset -lintl -lz"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --without-python
        --without-debug
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
        CPPFLAGS="$CPPFLAGS -DLIBXML_STATIC -DXML_STATIC -I$FFBUILD_PREFIX/include" \
        LDFLAGS="$LDFLAGS" \
        LIBS="$XML_DEPS $LIBS" \
        AR="${FFBUILD_TOOLCHAIN}-gcc-ar" \
        NM="${FFBUILD_TOOLCHAIN}-gcc-nm" \
        RANLIB="${FFBUILD_TOOLCHAIN}-gcc-ranlib"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    clean_la_files

    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libxml-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "${SYNC_MARK} Patching libxml-2.0.pc..."
        # форсируем флаги статики в Cflags
        sed -i "/^Cflags:/ s/$/ -DLIBXML_STATIC -DXML_STATIC/" "$PC_FILE"
        # полный хвост зависимостей в Libs.private (сначала либы, потом системные)
        sed -i "s|^Libs.private:.*|Libs.private: $XML_DEPS -lws2_32 -lbcrypt $LIBS|" "$PC_FILE"
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
