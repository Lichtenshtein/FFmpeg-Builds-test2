#!/bin/bash

# SCRIPT_REPO="https://github.com/libass/libass.git"
# SCRIPT_COMMIT="fadc390583f24eb5cf98f16925fd3adee50bca88"

SCRIPT_REPO="https://github.com/amanosatosi/libassmod.git"
SCRIPT_COMMIT="c248bbba98db65872fdb9f08ab93fef1f59e32cd"
SCRIPT_BRANCH="mangetsu"

ffbuild_depends() {
    echo base
    echo libiconv
    echo freetype
    echo fontconfig
    echo harfbuzz
    echo fribidi
    echo libunibreak
    # echo libpng
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        --cross-file="$FFBUILD_MESON_CROSS"
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dtest=disabled
        -Dcompare=disabled # compare program (requires libpng)
        -Dprofile=disabled
        -Dfuzz=disabled
        -Dcheckasm=disabled
        -Dfontconfig=enabled
        -Dasm=enabled
        -Dlibunibreak=enabled
        # -Dlarge-tiles=enabled # in the rasterizer (better performance, slightly worse quality)
    )

    if [[ $TARGET == win* ]]; then
        myconf+=(
            -Ddirectwrite=enabled
        )
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Dread_file=libass_internal_read_file" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Dread_file=libass_internal_read_file" \
        -Dc_link_args="$LDFLAGS ${USELTO}${USELTO_L}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}${USELTO_L}" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s|^Cflags:.*|& -I\${includedir}/ass|" "$PC_FILE"
        done
        log_info "Cflags paths have been updated."
    fi
}

ffbuild_configure() {
    echo --enable-libass
}

ffbuild_unconfigure() {
    echo --disable-libass
}
