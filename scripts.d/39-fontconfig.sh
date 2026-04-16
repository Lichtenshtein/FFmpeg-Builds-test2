#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/fontconfig/fontconfig.git"
SCRIPT_COMMIT="39a8756c7748f5aa251db6a04d680d7731d73c74"

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

    # Fontconfig требует либо expat, либо libxml2.
    local DEP_LIBS="-lxml2 -lfreetype -lintl -liconv -lcharset"
    local WIN_LIBS="-luuid $LIBS"

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
        -Dxml-backend=libxml2
        -Diconv=enabled
        -Ddefault-sub-pixel-rendering=rgb
    )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --sysconfdir=/etc
            --localstatedir=/var
        )
    fi

    mkdir -p _build && cd _build

    meson setup .. "${myconf[@]}" \
        -Dc_args="$CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS $DEP_LIBS $WIN_LIBS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    rm -rf "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/{var,etc}
}

ffbuild_configure() {
    echo --enable-libfontconfig
}

ffbuild_unconfigure() {
    echo --disable-libfontconfig
}
