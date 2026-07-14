#!/bin/bash

SCRIPT_REPO="https://github.com/libjpeg-turbo/libjpeg-turbo.git"
SCRIPT_COMMIT="1db93c29599cf64e5193297b6e2de069c1838d04"

ffbuild_depends() {
    echo zlib
    echo spng
}

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
        -DWITH_SIMD=ON
        -DREQUIRE_SIMD=ON
        -DWITH_TOOLS=OFF
        -DWITH_TESTS=OFF
        -DWITH_ARITH_ENC=ON
        -DWITH_ARITH_DEC=ON
        -DWITH_TURBOJPEG=ON
        -DWITH_JNA=OFF
        # Break compatibility with libjpeg v6b
        -DWITH_JPEG7=OFF
        -DWITH_JPEG8=OFF
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags+="-DLIBJPEG_STATIC"
    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DENABLE_STATIC=OFF -DENABLE_SHARED=ON ) || \
        myconf+=( -DENABLE_STATIC=ON -DENABLE_SHARED=OFF )

    if has_library "z"; then
        log_info "ZLIB library detected. Building with ZLIB support..."
        myconf+=( -DWITH_SYSTEM_ZLIB=ON )
    fi
    if has_library "spng"; then
        log_info "SPNG library detected. Building with SPNG support..."
        myconf+=( -DWITH_SYSTEM_SPNG=ON )
        [[ "${PREFER_SHARED}" != "1" ]] && static_flags+="-DSPNG_STATIC"
    fi

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    for PC_FILE in "$PC_DIR"/*jpeg*.pc; do
        [[ -e "$PC_FILE" ]] || continue
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
        if [[ "${myconf[@]}" =~ "-DWITH_SYSTEM_SPNG=ON" ]]; then
            if ! grep -q "^Libs.private:" "$PC_FILE"; then
                sed -i '/^Libs:/i Libs.private: -lspng' "$PC_FILE"
            elif ! grep -q "^Libs.private:.*-lspng" "$PC_FILE"; then
                sed -i 's/^\(Libs.private:[[:space:]]*\)/\1-lspng /' "$PC_FILE"
            fi
        fi
    done
}

ffbuild_cppflags() {
    echo "$static_flags"
}
