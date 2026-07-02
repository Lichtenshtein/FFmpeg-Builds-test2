#!/bin/bash

SCRIPT_REPO="https://github.com/fraunhoferhhi/vvdec.git"
SCRIPT_COMMIT="26272de81a81f83eea4b4ff84ee3782fcef86ce9"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    [[ $TARGET == winarm* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    # -fpermissive нужен для некоторых версий GCC при сборке VVC
    local FLAGS="-fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DVVDEC_ENABLE_LINK_TIME_OPT=OFF # to overrite -fno-fat-lto-objects
        -DVVDEC_LIBRARY_ONLY=ON
        -DVVDEC_ENABLE_BUILD_TYPE_POSTFIX=OFF
        -DVVDEC_ENABLE_WERROR=OFF
        -DVVDEC_OPT_TARGET_ARCH="${CPU_ARCH:-broadwell}"
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $FLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $FLAGS" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/libvvdec.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s|^Libs.private:.*|Libs.private: -lstdc++|g" "$PC_FILE"
        sed -i 's|/[^ ]*libstdc++.a|-lstdc++|g' "$PC_FILE"
        sed -i 's|/[^ ]*libssp.a|-lssp|g' "$PC_FILE"
        sed -i "s|^Cflags:.*|& -I\${includedir}/vvdec|" "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libvvdec
}

ffbuild_unconfigure() {
    echo --disable-libvvdec
}