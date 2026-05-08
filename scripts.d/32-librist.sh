#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/rist/librist.git"
SCRIPT_COMMIT="9b4e359f4e5b2d9a922b6d4f0af61fe7acf78c66"

ffbuild_depends() {
    # echo mbedtls # does not recognize external mbedtls
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
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dc_std=gnu17
        -Dcpp_std=gnu++20
        -Dtest=false
        -Dbuilt_tools=false
        -Dbuiltin_mbedtls=false
        -Duse_nettle=true
        -Duse_gnutls=false
        # -Duse_mbedtls=true 
    )

    if [[ $TARGET == win* ]]; then
        myconf+=(
            -Dhave_mingw_pthreads=true
        )
    fi

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file="$FFBUILD_MESON_CROSS"
        )
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dc_link_args="$LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # echo "Requires: mbedcrypto" >> "$PC_DIR/librist.pc"
}

ffbuild_configure() {
    echo --enable-librist
}

ffbuild_unconfigure() {
    echo --disable-librist
}
