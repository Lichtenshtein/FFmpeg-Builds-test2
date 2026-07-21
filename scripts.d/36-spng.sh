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

    echo "rm -rf tests"

    local COMPONENT_NAME="spng"
    local PATCHES_DIR="${PATCHES_DIR}"
    local CUSTOM_CMAKELISTS="${PATCHES_DIR}/${COMPONENT_NAME}/CMakeLists.txt"

    if [[ -f "$CUSTOM_CMAKELISTS" ]]; then
        log_info "Replacing CMakeLists.txt with custom version from patches..."
        echo "cp -rf${OP_V} '$CUSTOM_CMAKELISTS' './CMakeLists.txt'"
    else
        log_warn "Custom CMakeLists.txt not found at $CUSTOM_CMAKELISTS. Using default."
    fi
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build "$PC_DIR" && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DSPNG_ENABLE_OPT=ON
        -DSPNG_INSTALL=ON
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DSPNG_SHARED=ON -DSPNG_STATIC=OFF ) || \
        myconf+=( -DSPNG_SHARED=OFF -DSPNG_STATIC=ON )

    local static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DSPNG_STATIC"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} ${static_flags}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} ${static_flags}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/spng.pc"
    if [[ -f "$PC_FILE" ]]; then
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
    fi
}
