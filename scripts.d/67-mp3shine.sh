#!/bin/bash

# SCRIPT_REPO="https://github.com/toots/shine.git"
# SCRIPT_COMMIT="ab5e3526b64af1a2eaa43aa6f441a7312e013519"

SCRIPT_REPO="https://github.com/wshon/shine.git"
SCRIPT_COMMIT="e4f41742513caad76739fac666c4f7b7f1fb955b"
SCRIPT_BRANCH="debug"

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
        --prefix="$FFBUILD_PREFIX"
        --libdir="lib"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --cross-file="$FFBUILD_MESON_CROSS"
        --wrap-mode=nodownload
    )

    [[ "${USE_LTO}" == "1" ]] && myconf+=( -Db_lto=true )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dc_link_args="$LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # autoreconf -i

    # local myconf=(
        # --prefix="$FFBUILD_PREFIX"
        # --with-pic
    # )

    # [[ "${PREFER_SHARED}" == "1" ]] && \
        # myconf+=( --disable-static --enable-shared ) || \
        # myconf+=( --enable-static --disable-shared )

    # if [[ $TARGET == win* || $TARGET == linux* ]]; then
        # myconf+=(
            # --host="$FFBUILD_TOOLCHAIN"
        # )
    # fi

    # CFLAGS="$CFLAGS ${USELTO}" \
    # CPPFLAGS="$CPPFLAGS" \
    # CXXFLAGS="$CXXFLAGS ${USELTO}" \
    # LDFLAGS="$LDFLAGS ${USELTO}" \
    # LIBS="$LIBS" \
    # ./configure "${myconf[@]}" || return 1

    # make -j$(nproc) $MAKE_V || return 1
    # make install DESTDIR="$FFBUILD_DESTDIR" || return 1
}

ffbuild_configure() {
    echo --enable-libshine
}

ffbuild_unconfigure() {
    echo --disable-libshine
}
