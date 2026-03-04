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

    local DEP_LIBS="-ljpeg -lturbojpeg -ltiff -ltiffxx $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file=/cross.meson
        -Ddefault_library=static
        -Dutils=false
        -Dfastfloat=true
        -Dthreaded=true
        -Dtests=disabled
        -Dcpp_args="$CXXFLAGS"
        -Dc_args="$CFLAGS"
        -Dc_link_args="$LDFLAGS $DEP_LIBS"
        -Dcpp_link_args="$LDFLAGS $DEP_LIBS"
    )

    # export CFLAGS="$CFLAGS -fpermissive"

    meson setup "${myconf[@]}" ..
    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    # ѕровер€ем lcms2.pc
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/lcms2.pc"
    if [[ -f "$PC_FILE" ]]; then
        # lcms2 часто не пишет зависимости в .pc, если они статические
        # ƒобавим -lm (математическа€ библиотека) дл€ Windows/MinGW
        sed -i '/^Libs.private:/ s/$/ $DEP_LIBS/' "$PC_FILE"
    fi

    get_deps_list
}
