#!/bin/bash

SCRIPT_REPO="https://github.com/AviSynth/AviSynthPlus.git"
SCRIPT_COMMIT="345a00034c6f167662119c129b06a1f65b72b619"

ffbuild_depends() {
    echo soundtouch
}

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e
    # their version check is insistant on a tag to exist, so make one
    git tag -a ffbuild -m "FFbuild Version"

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DHEADERS_ONLY=OFF # Install only the Headers
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DENABLE_INTEL_SIMD=ON
        -DENABLE_PLUGINS=ON
        -DENABLE_CUDA=OFF
        # -DCORE_PLUGIN_INSTALL_PATH=
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    # VersionGen должна быть собрана перед инсталляцией
    ninja $NINJA_V VersionGen || return 1
    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    sed -i "s|^Cflags:.*|& -I\${includedir}/avisynth|" "$PC_DIR/avisynth.pc"
}

ffbuild_configure() {
    echo --enable-avisynth
}

ffbuild_unconfigure() {
    echo --disable-avisynth
}
