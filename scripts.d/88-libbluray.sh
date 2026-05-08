#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/libbluray.git"
SCRIPT_COMMIT="4dfb9b0123b006ce5d66592dc8058f61e5c0cdc8"

ffbuild_depends() {
    echo base
    echo libxml2
    echo freetype
    echo fontconfig
    echo harfbuzz
    # цепочка
    echo libudfread
    # echo libdvdcss
    # echo libdvdread
    # echo libdvdnav
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # stop the static library from exporting symbols when linked into a shared lib
    sed -i 's/-DBLURAY_API_EXPORT/-DBLURAY_API_EXPORT_DISABLED/g' src/meson.build

    mkdir -p build && cd build

    local myconf=(
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        --prefix="$FFBUILD_PREFIX"
        -Ddefault_library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Denable_docs=false
        -Denable_tools=false
        -Denable_devtools=false
        -Denable_examples=false
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Dbdj_jar=disabled
        -Dfontconfig=enabled
        -Dfreetype=enabled
        -Dlibxml2=enabled
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file="$FFBUILD_MESON_CROSS"
        )
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Ddec_init=libbr_dec_init" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Ddec_init=libbr_dec_init" \
        -Dc_link_args="$LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-libbluray
}

ffbuild_unconfigure() {
    echo --disable-libbluray
}
