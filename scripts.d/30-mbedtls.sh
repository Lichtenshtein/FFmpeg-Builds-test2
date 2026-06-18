#!/bin/bash

SCRIPT_REPO="https://github.com/Mbed-TLS/mbedtls.git"
SCRIPT_COMMIT="0bebf8b8c7f07abe3571ded48a11aa907a1ffb20"
# SCRIPT_COMMIT="v3.6.6"
# SCRIPT_TAGFILTER="v3.*"

ffbuild_enabled() {
    [[ "${SEC_PROTO}" != "mbedtls" ]] && return 1 || return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
    echo "rm -rf tests"
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
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
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

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Wno-error=array-bounds" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Wno-error=array-bounds" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s|^Cflags:.*|& -I\${includedir}/mbedtls|" "$PC_FILE"
        done
        log_info "Cflags paths have been updated."
        if [[ $TARGET == win* ]]; then
            echo "Libs.private: -lws2_32 -lbcrypt -lwinmm -lgdi32" >> "$PC_DIR/mbedcrypto.pc"
        fi
    fi
}

ffbuild_configure() {
    [[ "${SEC_PROTO}" != "mbedtls" ]] && echo --disable-mbedtls || echo --enable-mbedtls
}

ffbuild_unconfigure() {
    echo --disable-mbedtls
}