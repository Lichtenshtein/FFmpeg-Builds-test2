#!/bin/bash

SCRIPT_REPO="https://github.com/sekrit-twc/znedi3.git"
SCRIPT_COMMIT="4cf67b9acad5bfc45b306b5187c5766695a94ca4"

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
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local myconf=(
        --buildtype=release
        --cross-file="$FFBUILD_MESON_CROSS"
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --prefix="$FFBUILD_PREFIX"
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dc_std=gnu17
        -Dcpp_std=gnu++20
    )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -w" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -w" \
        -Dc_link_args="$LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    log_info "Copying the weights file nnedi3_weights.bin to the installation prefix..."

    # Копируем в общую папку хранения бинарников (откуда ваша система забирает файлы)
    mkdir -p "${INSTALL_ROOT}/bin"
    cp "../nnedi3_weights.bin" "${INSTALL_ROOT}/bin/nnedi3_weights.sign" 2>/dev/null || true
    cp "../nnedi3_weights.bin" "${INSTALL_ROOT}/bin/nnedi3_weights.bin"

    # Проверяем, что файл успешно скопирован и не пустой
    if [ ! -s "${INSTALL_ROOT}/include/../bin/nnedi3_weights.bin" ]; then
        log_warn "nnedi3_weights.bin was not found or is empty in the target folder!"
    fi
}
