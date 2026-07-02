#!/bin/bash

SCRIPT_REPO="https://github.com/fraunhoferhhi/vvenc.git"
SCRIPT_COMMIT="182ad990a15c5300702202f184b332b7d146a841"

ffbuild_enabled() {
    [[ $TARGET == winarm* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local FLAGS="-fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DVVENC_ENABLE_BUILD_TYPE_POSTFIX=OFF
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DVVENC_LIBRARY_ONLY=ON
        -DVVENC_ENABLE_WERROR=OFF
        -DVVENC_ENABLE_LINK_TIME_OPT=OFF # to overrite -fno-fat-lto-objects
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $FLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $FLAGS" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/libvvenc.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s|^Libs.private:.*|Libs.private: -lstdc++|g" "$PC_FILE"
        sed -i 's|/[^ ]*libstdc++.a|-lstdc++|g' "$PC_FILE"
        sed -i 's|/[^ ]*libssp.a|-lssp|g' "$PC_FILE"
        sed -i "s|^Cflags:.*|& -I\${includedir}/vvenc|" "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libvvenc
}

ffbuild_unconfigure() {
    echo --disable-libvvenc
}
