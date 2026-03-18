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
    local FC_LIBS="-lxml2 -lfreetype -lharfbuzz -lharfbuzz-icu -lsicuin -lsicuuc -lsicudt -lpng16 -lbrotlidec -lbrotlicommon -lbz2 -lz -lintl -liconv -lcharset"

    local myconf=(
        --cross-file=/cross.meson
        --prefix="$FFBUILD_PREFIX"
        --libdir="lib"
        --buildtype=release
        --default-library=static
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

    mkdir _build
    cd _build

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    # Запуск конфигурации
    meson setup .. "${myconf[@]}" \
        -Dc_args="$CFLAGS" \
        -Dcpp_args="$CPPFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    clean_la_files

    rm -rf "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/{var,etc}

    # local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/fontconfig.pc"
    # if [[ -f "$PC_FILE" ]]; then
        # log_info "${SYNC_MARK} Patching fontconfig.pc..."
        # sed -i "s|^Libs.private:.*|Libs.private: $FC_LIBS $LIBS -lole32 -luuid|" "$PC_FILE"
    # fi

    get_deps_list
}

ffbuild_configure() {
    echo --enable-fontconfig
}

ffbuild_unconfigure() {
    echo --disable-fontconfig
}
