#!/bin/bash

SCRIPT_REPO="https://github.com/DeepTulip/libspng.git"
SCRIPT_COMMIT="588a43d12f92a27195af237ec24ec5b6417ab41c"

ffbuild_depends() {
    echo zlib
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .

    local COMPONENT_NAME="spng"
    local PATCHES_DIR="${PATCHES_DIR}"
    local CUSTOM_CMAKELISTS="${PATCHES_DIR}/${COMPONENT_NAME}/CMakeLists.txt"

    if [[ -f "$CUSTOM_CMAKELISTS" ]]; then
        log_info "Replacing CMakeLists.txt with custom version from patches..."
        echo "cp -rfv '$CUSTOM_CMAKELISTS' './CMakeLists.txt'"
    else
        log_warn "Custom CMakeLists.txt not found at $CUSTOM_CMAKELISTS. Using default."
    fi
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DSPNG_ENABLE_OPT=ON
        -DSPNG_INSTALL=ON
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DSPNG_SHARED=ON -DSPNG_STATIC=OFF ) || \
        myconf+=( -DSPNG_SHARED=OFF -DSPNG_STATIC=ON )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}
