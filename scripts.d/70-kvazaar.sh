#!/bin/bash

SCRIPT_REPO="https://github.com/ultravideo/kvazaar.git"
SCRIPT_COMMIT="45597d8de2e3ef7695ac54e8a3372572c4bb8213"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    ./autogen.sh

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_TESTS=OFF
        -DUSE_CRYPTO=ON # OFF
        -DBUILD_KVAZAAR_BINARY=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON) # To build only the lib
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DKVZ_STATIC_LIB"

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $static_flags" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if [[ -n "$static_flags" ]]; then
        if ! grep -qF -- "$static_flags" "$PC_DIR/kvazaar.pc"; then
            sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_DIR/kvazaar.pc"
        fi
    fi
    echo "Libs.private: -pthread" >> "$PC_DIR/kvazaar.pc"
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-libkvazaar
}

ffbuild_unconfigure() {
    echo --disable-libkvazaar
}
