#!/bin/bash

SCRIPT_REPO="https://github.com/mpeg5/xevd.git"
SCRIPT_COMMIT="4087f635624cf4ee6ebe3f9ea165ff939b32117f"

# SCRIPT_REPO="https://github.com/jamrial/xevd.git"
# SCRIPT_COMMIT="1f7a2e79544ecdc71bbb51e938f392e5d00aa5b7"
# SCRIPT_BRANCH="rbsp_fix"

ffbuild_enabled() {
    [[ $TARGET == *arm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    if [ ! -f "version.txt" ]; then
        echo v0.5.0 >> version.txt
    fi

    find src_base -name "CMakeLists.txt" -exec sed -i 's|${CMAKE_CURRENT_SOURCE_DIR}/pkgconfig/|${CMAKE_CURRENT_SOURCE_DIR}/../pkgconfig/|g' {} +
    find src_main -name "CMakeLists.txt" -exec sed -i 's|${CMAKE_CURRENT_SOURCE_DIR}/pkgconfig/|${CMAKE_CURRENT_SOURCE_DIR}/../pkgconfig/|g' {} +

    mkdir -p _build && cd _build

    local myconf=(
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DXEVD_APP_STATIC_BUILD=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        # added by patch
        -DXEVD_BUILD_APP=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-libxevd
}

ffbuild_unconfigure() {
    echo --disable-libxevd
}