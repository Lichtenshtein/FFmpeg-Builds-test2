#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/fontconfig/fontconfig.git"
SCRIPT_COMMIT="d87ec67db56518e9e9c36ff38f151dfc9b728b2e"

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

    mkdir -p _build && cd _build

    local myconf=(
        --cross-file="$FFBUILD_MESON_CROSS"
        --prefix="$FFBUILD_PREFIX"
        --libdir="lib"
        --buildtype=release
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Ddoc=disabled
        -Dnls=enabled
        -Dtests=disabled
        -Dtools=disabled
        -Dcache-build=disabled
        -Ddefault-sub-pixel-rendering=rgb
    )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --sysconfdir=/etc
            --localstatedir=/var
        )
    fi

    if has_library "xml2"; then
        log_info "LibXML2 library detected. Building with LibXML2 support..."
        myconf+=( -Dxml-backend=libxml2 )
        local XML2_LIB="-lxml2"
        local XML2_C_FLAGS="-DLIBXML_STATIC -DXML_STATIC"
    fi
    if has_library "iconv"; then
        log_info "Iconv library detected. Building libxml2 with Iconv support..."
        myconf+=( -Diconv=enabled )
        local ICONV_LIBS="-liconv -lcharset"
    else
        log_warn "Iconv library not found. Building libxml2 without Iconv..."
        myconf+=( -Diconv=disabled )
    fi

    # Fontconfig requires either expat or libxml2.
    local DEP_LIBS="${XML2_LIB} -lfreetype -lintl ${ICONV_LIBS}"
    local WIN_LIBS="-luuid $LIBS"

    meson setup .. "${myconf[@]}" \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dc_link_args="$LDFLAGS ${USELTO}${USELTO_L} $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}${USELTO_L} $DEP_LIBS $WIN_LIBS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    rm -rf "$INSTALL_ROOT"/{var,etc}

    mkdir -p "$PC_DIR"
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s|^Cflags:.*|& -I\${includedir}/fontconfig|" "$PC_FILE"
        done
        log_info "Cflags paths have been updated."
    fi
}

ffbuild_configure() {
    echo --enable-libfontconfig
}

ffbuild_unconfigure() {
    echo --disable-libfontconfig
}
