#!/bin/bash

SCRIPT_REPO="https://github.com/ARMmbed/mbedtls.git"
SCRIPT_COMMIT="0fe989b6b514192783c469039edd325fd0989806"
# SCRIPT_COMMIT="v3.6.5"
# SCRIPT_TAGFILTER="v3.*"

ffbuild_enabled() {
    return 1
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    if [[ $TARGET == win32 ]]; then
        python3 scripts/config.py unset MBEDTLS_AESNI_C
    fi

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DENABLE_PROGRAMS=OFF
        -DENABLE_TESTING=OFF
        -DGEN_FILES=ON
        -DINSTALL_MBEDTLS_HEADERS=ON
        -DLINK_WITH_PTHREAD=ON
        -DLINK_WITH_TRUSTED_STORAGE=OFF
        -DMBEDTLS_FATAL_WARNINGS=OFF
        )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DUSE_SHARED_MBEDTLS_LIBRARY=ON -DUSE_STATIC_MBEDTLS_LIBRARY=OFF ) || \
        myconf+=( -DUSE_SHARED_MBEDTLS_LIBRARY=OFF -DUSE_STATIC_MBEDTLS_LIBRARY=ON )

    CFLAGS="$CFLAGS $CPPFLAGS -Wno-error=array-bounds" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -Wno-error=array-bounds" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if [[ $TARGET == win* ]]; then
        echo "Libs.private: -lws2_32 -lbcrypt -lwinmm -lgdi32" >> "$PC_DIR/mbedcrypto.pc"
    fi
}

ffbuild_configure() {
    echo --enable-mbedtls
}

ffbuild_unconfigure() {
    echo --disable-mbedtls
}