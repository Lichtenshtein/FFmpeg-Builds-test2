#!/bin/bash

SCRIPT_REPO="https://github.com/libjpeg-turbo/libjpeg-turbo.git"
SCRIPT_COMMIT="1db93c29599cf64e5193297b6e2de069c1838d04"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DWITH_JPEG8=ON
        -DWITH_SIMD=ON
        -DWITH_TOOLS=OFF
        -DWITH_TESTS=OFF
        -DWITH_TURBOJPEG=ON
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DLIBJPEG_STATIC"
    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DENABLE_STATIC=OFF -DENABLE_SHARED=ON ) || \
        myconf+=( -DENABLE_STATIC=ON -DENABLE_SHARED=OFF )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    for pc in "$PC_DIR"/*jpeg*.pc; do
        [[ -e "$pc" ]] || continue
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$pc"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$pc"
            fi
        fi
    done
}

ffbuild_cppflags() {
    echo "$static_flags"
}
