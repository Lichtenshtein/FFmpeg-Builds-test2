#!/bin/bash

SCRIPT_REPO="https://github.com/mm2/Little-CMS.git"
SCRIPT_COMMIT="6ae7e97cc1b0a44f1996d51160de9fbab97bb7b8"

ffbuild_depends() {
    echo libjpeg-turbo
    echo libtiff
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    local LCMS_DEPS="-ltiff -ltiffxx -ljpeg -lturbojpeg -ljbig -ljbig85 -lzstd -llzma -lz $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file=/cross.meson
        -Ddefault_library=static
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dutils=false
        -Dfastfloat=true
        -Dthreaded=true
        -Dtests=disabled
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$(echo $CFLAGS | sed 's/-std=c11//g')" \
        -Dcpp_args="$(echo $CXXFLAGS | sed 's/-std=c++17//g')" \
        -Dc_link_args="$LDFLAGS $LCMS_DEPS" \
        -Dcpp_link_args="$LDFLAGS $LCMS_DEPS" || return 1
    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    clean_la_files

    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/lcms2.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "/^Libs.private:/ s/$/ $LCMS_DEPS/" "$PC_FILE"
    fi

    get_deps_list
}

ffbuild_configure() {
    echo --enable-lcms2
}

ffbuild_unconfigure() {
    echo --disable-lcms2
}
