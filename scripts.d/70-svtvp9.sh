#!/bin/bash

SCRIPT_REPO="https://github.com/OpenVisualCloud/SVT-VP9.git"
SCRIPT_COMMIT="7917f95c3849768ab569ccc4a5adecb8854b65f6"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    [[ $TARGET == *arm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    sed -i 's/-march=native//g' CMakeLists.txt || true

    mkdir -p _build && cd _build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_APP=OFF
        -DNATIVE=OFF
        -DCOVERAGE=OFF
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    sed -i "s|^Cflags:.*|& -I\${includedir}/svt-vp9|" "$PC_DIR/SvtVp9Enc.pc"
}

ffbuild_configure() {
    echo --enable-libsvtvp9
}

ffbuild_unconfigure() {
    echo --disable-libsvtvp9
}
