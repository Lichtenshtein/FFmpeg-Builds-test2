#!/bin/bash

SCRIPT_REPO="https://github.com/intel/libva.git"
SCRIPT_COMMIT="ad64eb9b616d1b66afaf4cb9f0ea0b8e0ec1169c"

ffbuild_depends() {
    echo base
    echo x11
}

ffbuild_enabled() {
    [[ $TARGET == linuxarm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # This works around an issue of our libxcb-dri3 implib-wrapper not exporting data symbols.
    # Under normal circumstances, this would break horribly.
    # But we only want to generate another import lib for libva, so it doesn't matter.
    echo "#include <xcb/xcbext.h>" >> va/x11/va_dri3.c
    echo "xcb_extension_t xcb_dri3_id;" >> va/x11/va_dri3.c

    # Allow to actually toggle static linking
    sed -i "s/shared_library/library/g" va/meson.build

    mkdir -p _build && cd _build

    local myconf=(
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Denable_docs=false
    )

    if [[ $TARGET == linux64 ]]; then
        myconf+=(
            --cross-file="$FFBUILD_MESON_CROSS"
            --sysconfdir="/etc"
            -Ddriverdir="/usr/lib/x86_64-linux-gnu/dri"
            -Ddisable_drm=false
            -Dwith_x11=yes
            -Dwith_glx=no
            -Dwith_wayland=no
        )
    elif [[ $TARGET == win* ]]; then
        myconf+=(
            --cross-file=/cross.meson
            -Dwith_win32=yes
        )
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$RAW_CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dc_link_args="$RAW_LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$RAW_LDFLAGS ${USELTO}" || return 1

    ninja -j"$(nproc)" $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s|^Cflags:.*|& -I\${includedir}/va|" "$PC_FILE"
        done
        log_info "Cflags paths have been updated."
    fi

    if [[ $TARGET == linux* ]]; then
        gen-implib "$INSTALL_ROOT"/lib/{libva.so.2,libva.a}
        gen-implib "$INSTALL_ROOT"/lib/{libva-drm.so.2,libva-drm.a}
        gen-implib "$INSTALL_ROOT"/lib/{libva-x11.so.2,libva-x11.a}
        rm "$INSTALL_ROOT"/lib/libva{,-drm,-x11}.so*

        sed -i '/^Libs:/ s/$/ -ldl/' "$PC_DIR/libva.pc"
    fi
}

ffbuild_configure() {
    echo --enable-vaapi
}

ffbuild_unconfigure() {
    echo --disable-vaapi
}
