#!/bin/bash

SCRIPT_REPO="https://github.com/alanxz/rabbitmq-c.git"
SCRIPT_COMMIT="8b7471eab8d09536b3c104dbb30a65699cf48104"

ffbuild_depends() {
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

    mkdir build && cd build

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_API_DOCS=OFF
        -DBUILD_EXAMPLES=OFF
        -DBUILD_OSSFUZZ=OFF
        -DBUILD_TESTS=OFF
        -DBUILD_TOOLS=OFF
        -DCMAKE_BUILD_TYPE=Release
        -DENABLE_SSL_SUPPORT=ON
        -DRUN_SYSTEM_TESTS=OFF
        )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF ) || \
        myconf+=( -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DINSTALL_STATIC_LIBS=ON )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-librabbitmq
}

ffbuild_unconfigure() {
    echo --disable-librabbitmq
}
