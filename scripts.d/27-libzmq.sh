#!/bin/bash

SCRIPT_REPO="https://github.com/zeromq/libzmq.git"
SCRIPT_COMMIT="51a5a9cbe315ab149357afe063e9e2d41f4c99a8"

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
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DBUILD_TESTS=OFF
        -DENABLE_INTRINSICS=ON
        -DENABLE_DRAFTS=OFF
        -DWITH_TLS=ON # OFF
        -DWITH_PERF_TOOL=OFF
        -DENABLE_CLANG=ON
        -DWITH_DOCS=OFF
        -DENABLE_CPACK=OFF
        -DENABLE_NO_EXPORT=ON # empty ZMQ_EXPORT macro, bypassing platform-based automated detection
    )

    if [[ $TARGET == win* ]]; then
        myconf+=( -DPOLLER="epoll" )
    fi

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DZMQ_STATIC"

    CFLAGS="$CFLAGS $CPPFLAGS -DZMQ_NO_EXPORT $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -DZMQ_NO_EXPORT $static_flags" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    {
        echo "Cflags.private: -DZMQ_NO_EXPORT $static_flags"
        [[ $TARGET != win* ]] || echo "Libs.private: -lws2_32 -liphlpapi"
    } >> "$PC_DIR/libzmq.pc"
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-libzmq
}

ffbuild_unconfigure() {
    echo --disable-libzmq
}
