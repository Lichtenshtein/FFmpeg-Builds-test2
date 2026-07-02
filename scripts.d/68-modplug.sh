#!/bin/bash

#SCRIPT_REPO="https://github.com/Konstanty/libmodplug"

SCRIPT_REPO="https://github.com/mywave82/libmodplug.git"
SCRIPT_COMMIT="dadf7058372c04ab28ee1fb5475d05e5e191e72e"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    autoreconf -if

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --with-pic
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    fi

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DMODPLUG_STATIC"
    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $static_flags ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    sed -i "s|^Cflags:.*|& -I\${includedir}/libmodplug $static_flags|" "$PC_DIR/libmodplug.pc"
}

ffbuild_cflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-libmodplug
}

ffbuild_unconfigure() {
    echo --disable-libmodplug
}