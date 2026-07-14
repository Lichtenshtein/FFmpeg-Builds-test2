#!/bin/bash

SCRIPT_REPO="https://github.com/sekrit-twc/znedi3.git"
SCRIPT_COMMIT="3f800876a1e87da1ffb77881207bcd95dc15bf48"

ffbuild_depends() {
    echo avisynth
    echo zimg
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
    echo "rm -rf graphengine/test"
}

ffbuild_dockerbuild() {
    set -e

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        log_info "Patching meson.build to force static plugin generation for vsznedi3..."
        sed -i "s/shared_module('vsznedi3'/static_library('vsznedi3'/g" meson.build
    fi

    mkdir build && cd build

    local myconf=(
        --buildtype=release
        --cross-file="$FFBUILD_MESON_CROSS"
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --prefix="$FFBUILD_PREFIX"
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dc_std=gnu17
        -Dcpp_std=gnu++20
        -Duse_avx512=$([ "${USE_AVX512}" == "1" ] && echo true || echo false)
    )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -w" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -w" \
        -Dc_link_args="$LDFLAGS ${USELTO}${USELTO_L}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}${USELTO_L}" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Add -lvsznedi3 to the Libs line in znedi3.pc
    local PC_FILE="$PC_DIR/znedi3.pc"
    if [[ "${PREFER_SHARED}" != "1" && -f "${PC_FILE}" ]]; then
        log_info "Fixing pkg-config to include both core and plugin archives..."
        sed -i 's/Libs: -L${libdir} -lznedi3/Libs: -L${libdir} -lznedi3 -lvsznedi3/g' "${PC_FILE}"
    fi

    log_info "Copying the weights file nnedi3_weights.bin to the installation prefix..."
    mkdir -p "${INSTALL_ROOT}/bin"
    cp "../nnedi3_weights.bin" "${INSTALL_ROOT}/bin/nnedi3_weights.sign" 2>/dev/null || true
    cp "../nnedi3_weights.bin" "${INSTALL_ROOT}/bin/nnedi3_weights.bin"

    if [ ! -s "${INSTALL_ROOT}/bin/nnedi3_weights.bin" ]; then
        log_warn "nnedi3_weights.bin was not found or is empty in the target folder!"
    fi
}
