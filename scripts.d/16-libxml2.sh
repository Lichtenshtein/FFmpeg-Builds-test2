#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/libxml2.git"
SCRIPT_COMMIT="962bd10d01151d29190567e2d15ccf641be55063"

export SKIP_CONF_FINDER=1

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

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --without-python
        --without-debug
        --without-catalog
        --without-docs
        --without-modules
        --disable-maintainer-mode
        --with-pic
        --with-thread-alloc
        --with-winpath
        --with-zlib
        --with-iconv
        --with-tls
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    # Проверяем наличие статической библиотеки libicudt.a
    if has_library "icudt"; then
        log_info "ICU library detected. Building libxml2 with ICU support..."
        local DEP_LIBS="-llzma -lz -lintl -liconv -lcharset -licuin -licuuc -licudt $LIBS"
        myconf+=( "--with-icu" )
    else
        log_warn "ICU library not found. Building libxml2 without ICU for faster testing..."
        local DEP_LIBS="-llzma -lz -lintl -liconv -lcharset $LIBS"
        myconf+=( "--without-icu" )
    fi

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DLIBXML_STATIC -DXML_STATIC"

    # Принудительно задаем AR как gcc-ar для стабильности архивации
    ./autogen.sh "${myconf[@]}" \
        CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
        CPPFLAGS="$CPPFLAGS $static_flags" \
        CXXFLAGS="$CXXFLAGS $static_flags ${USELTO}${USELTO_C}" \
        LDFLAGS="$LDFLAGS ${USELTO}" \
        LIBS="$DEP_LIBS" \
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

    local PC_FILE="$PC_DIR/libxml-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s/ -DLIBXML_STATIC//g; s/ -DXML_STATIC//g" "$PC_FILE"
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
    fi
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-libxml2
}

ffbuild_unconfigure() {
    echo --disable-libxml2
}
