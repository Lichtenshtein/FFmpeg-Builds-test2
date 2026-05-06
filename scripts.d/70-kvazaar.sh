#!/bin/bash

SCRIPT_REPO="https://github.com/ultravideo/kvazaar.git"
SCRIPT_COMMIT="45597d8de2e3ef7695ac54e8a3372572c4bb8213"

ffbuild_depends() {
    echo cryptopp
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    sed -i 's/FetchContent_MakeAvailable/message(STATUS "Skipping") #/g' CMakeLists.txt
    sed -i 's|${CMAKE_BINARY_DIR}/lib/libcryptopp.a|cryptopp|g' CMakeLists.txt
    sed -i "1i include_directories($FFBUILD_PREFIX/include)" CMakeLists.txt
    sed -i "1i link_directories($FFBUILD_PREFIX/lib)" CMakeLists.txt

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_TESTS=OFF
        -DBUILD_KVAZAAR_BINARY=OFF # to build only the lib
        # crypto++
        -DFETCHCONTENT_FULLY_DISCONNECTED=ON
        -DUSE_CRYPTO=ON # OFF
        -DCRYPTOPP_FOUND=ON
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DKVZ_STATIC_LIB"

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C} $CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C} $CPPFLAGS $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/kvazaar.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "/^Libs.private:/ s/$/ -lcryptopp -lgomp -lstdc++/" "$PC_FILE"
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
    fi
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
