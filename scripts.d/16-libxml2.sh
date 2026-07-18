#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/libxml2.git"
SCRIPT_COMMIT="c8eaf2236ff16667970f96f3f01e119c99d38ab2"

ffbuild_depends() {
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
        --with-tls
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    local LZMA_LIBS=""
    local Z_LIBS=""
    local ICONV_LIBS=""
    local ICU_LIBS=""

    if has_library "z"; then
        log_info "ZLIB library detected. Building libxml2 with ZLIB support..."
        myconf+=( --with-zlib )
        local Z_LIBS="-lz"
    else
        log_warn "ZLIB library not found. Building libxml2 without ZLIB..."
        myconf+=( --without-zlib )
    fi
    if has_library "iconv"; then
        log_info "Iconv library detected. Building libxml2 with Iconv support..."
        myconf+=( --with-iconv )
        local ICONV_LIBS="-liconv -lcharset"
    else
        log_warn "Iconv library not found. Building libxml2 without Iconv..."
        myconf+=( --without-iconv )
    fi
    if has_library "icudt"; then
        log_info "ICU library detected. Building libxml2 with ICU support..."
        myconf+=( --with-icu )
        local ICU_LIBS="-licuin -licuuc -licudt"
    else
        log_warn "ICU library not found. Building libxml2 without ICU..."
        myconf+=( --without-icu )
    fi

    local DEP_LIBS="-Wl,--start-group ${LZMA_LIBS} ${Z_LIBS} ${ICONV_LIBS} -lintl ${ICU_LIBS} -Wl,--end-group $LIBS"

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DLIBXML_STATIC -DXML_STATIC"

    log_info "Configuring libxml2 with Autotools..."

    ./autogen.sh "${myconf[@]}" \
        CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
        CPPFLAGS="$CPPFLAGS $static_flags" \
        CXXFLAGS="$CXXFLAGS $static_flags ${USELTO}${USELTO_C}" \
        LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
        LIBS="$DEP_LIBS" \
        AR="${AR}" \
        NM="${NM}" \
        RANLIB="${RANLIB}" \
        CC="${CC}" \
        CXX="${CXX}" || return 1

    # Compilation attempt with handling of xmllint/xmlcatalog utilities crash due to linking
    make -j$(nproc) $MAKE_V CCLD="${FFBUILD_TOOLCHAIN}-g++" || {
        log_warn "make failed (likely xmllint/xmlcatalog tool linking) — checking if libxml2.a exists..."
        [[ -f ".libs/libxml2.${lib_ext}" ]] || { log_error "libxml2.${lib_ext} not built!"; return 1; }
        log_warn "libxml2.${lib_ext} confirmed present, proceeding with install."
    } || return 1

    make install DESTDIR="$FFBUILD_DESTDIR" bin_PROGRAMS="" || return 1

    local PC_FILE="$PC_DIR/libxml-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s/ -DLIBXML_STATIC//g; s/ -DXML_STATIC//g" "$PC_FILE"

        if [[ -n "$static_flags" ]]; then
            for flag in $static_flags; do
                if ! grep -qF -- "$flag" "$PC_FILE"; then
                    sed -i "/^Cflags:/ s/$/ $flag/" "$PC_FILE"
                fi
            done
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
