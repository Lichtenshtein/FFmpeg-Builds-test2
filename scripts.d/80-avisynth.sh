#!/bin/bash
export USE_VERS_FINDER=1
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
    echo "rm -rf distrib"
}

ffbuild_dockerbuild() {
    set -e

    # Отвязка от .git
    cat << EOF > avs_core/Version.cmake
#define AVS_MAJOR_VER 3
#define AVS_MINOR_VER 7
#define AVS_BUGFIX_VER 5

#define AVS_SEQREV "4600"
#define AVS_BRANCH "master"

#define AVS_NEWEST_TAG "${VER_FULL}"
#define AVS_DEVNEXT_REV "0"
#define AVS_DEV_REVDATE "2026-06-17"
#define AVS_DEV_GITHASH "ffbuild-static"

#define AVS_VERSION_STR "AviSynth+ ${VER_FULL} (r4600, master, x86_64)"
EOF

    # создаём пустышку
    cat << 'EOF' > avs_core/Version.cmake
EOF

    mkdir -p build && cd build

    local extra_cxx_flags="-DRELEASE_TARBALL"

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
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${extra_cxx_flags} ${USELTO}${USELTO_C}" \
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
