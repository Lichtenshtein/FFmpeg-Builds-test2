#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/rist/librist.git"
SCRIPT_COMMIT="1a5013b59ce098465e835a0510cd395872bb1c24"

ffbuild_depends() {
    echo mbedtls
    echo nettle
    # echo gnutls
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
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --prefix="$FFBUILD_PREFIX"
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false )
        -Dbuilt_tools=false
        -Dbuiltin_mbedtls=false
        # -Duse_mbedtls=true
        -Dc_std=c11
        -Dcpp_std=c++17
        -Dtest=false
        -Duse_nettle=true
    )

    if [[ $TARGET == win* ]]; then
        myconf+=(
            -Dhave_mingw_pthreads=true
        )
    fi

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file=/cross.meson
        )
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    echo "Requires: mbedcrypto" >> "$PC_DIR/librist.pc"
}

ffbuild_configure() {
    echo --enable-librist
}

ffbuild_unconfigure() {
    echo --disable-librist
}
