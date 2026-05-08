#!/bin/bash

SCRIPT_REPO="https://github.com/Haivision/srt.git"
SCRIPT_COMMIT="2220de504027b0fc45012b459365505834300e31"

ffbuild_depends() {
    echo base
    echo openssl
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
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_POLICY_DEFAULT_CMP0069=NEW
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DENABLE_CXX_DEPS=ON
        -DENABLE_ENCRYPTION=ON
        -DENABLE_LOGGING=OFF
        -DENABLE_APPS=OFF
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DENABLE_STATIC=OFF -DENABLE_SHARED=ON -DUSE_STATIC_LIBSTDCXX=OFF ) || \
        myconf+=( -DENABLE_STATIC=ON -DENABLE_SHARED=OFF -DUSE_STATIC_LIBSTDCXX=ON )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    sed -i '/^Libs.private:/ s/$/ -lstdc++"/' "$PC_DIR/srt.pc"
}

ffbuild_configure() {
    echo --enable-libsrt
}

ffbuild_unconfigure() {
    echo --disable-libsrt
}
