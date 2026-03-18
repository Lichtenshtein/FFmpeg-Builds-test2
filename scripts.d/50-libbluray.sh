#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/libbluray.git"
SCRIPT_COMMIT="4dfb9b0123b006ce5d66592dc8058f61e5c0cdc8"

ffbuild_depends() {
    echo base
    echo libxml2
    echo freetype
    echo fontconfig
    echo harfbuzz
    echo libudfread
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    apply_patches

    # stop the static library from exporting symbols when linked into a shared lib
    sed -i 's/-DBLURAY_API_EXPORT/-DBLURAY_API_EXPORT_DISABLED/g' src/meson.build

    mkdir build && cd build

    export CFLAGS="$(echo $CFLAGS | sed 's/-std=c11//g')"
    export CXXFLAGS="$(echo $CXXFLAGS | sed 's/-std=c++17//g')"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        -Ddefault_library=static
        -Denable_docs=false
        -Denable_tools=false
        -Denable_devtools=false
        -Denable_examples=false
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dbdj_jar=disabled
        -Dfontconfig=enabled
        -Dfreetype=enabled
        -Dlibxml2=enabled
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file=/cross.meson
        )
    else
        echo "Unknown target"
        return 1
    fi

    export CPPFLAGS="${CPPFLAGS} -Ddec_init=libbr_dec_init"

    meson setup "${myconf[@]}" .. || return 1
    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libbluray
}

ffbuild_unconfigure() {
    echo --disable-libbluray
}
