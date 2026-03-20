#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/pixman/pixman.git"
SCRIPT_COMMIT="f824cac6478971c0f71e4dfe8a60ebf70224076a"

ffbuild_depends() {
    echo libpng
    echo glib2
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    # Pixman для статики под Windows требует явного указания системных либ
    local PIXMAN_DEPS="-lpng16 -lglib-2.0 -lz -lintl -liconv -lcharset $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file=/cross.meson
        --buildtype=release
        --default-library=static
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dtests=disabled
        -Ddemos=disabled
        -Dgtk=disabled
        -Dopenmp=disabled
        -Dcpp_args="$(echo $CXXFLAGS | sed 's/-std=c++17//g') -Dpixman_static"
        -Dc_args="$(echo $CFLAGS | sed 's/-std=c11//g') -Dpixman_static"
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    meson setup "${myconf[@]}" .. \
        -Dc_link_args="$LDFLAGS $PIXMAN_DEPS" \
        -Dcpp_link_args="$LDFLAGS $PIXMAN_DEPS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    clean_la_files

    log_info "${SYNC_MARK} Patching PIXMAN .pc file..."
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/pixman-1.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s|^Libs.private:.*|Libs.private: $PIXMAN_DEPS|" "$PC_FILE"
        sed -i '/^Cflags:/ s/$/ -Dpixman_static/' "$pc"
    fi

    get_deps_list
}
