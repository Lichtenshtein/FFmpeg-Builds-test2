#!/bin/bash

SCRIPT_REPO="https://github.com/google/brotli.git"
SCRIPT_COMMIT="4e6d8fbfa3d11b491105c12b579727522aa7e836"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf \
tests \
java \
research/img \
js/test_data.tar \
js/test_data.ts \
test_data.js"
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DBROTLI_STATIC"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBROTLI_BUILD_FOR_PACKAGE=OFF # both shared and static libraries
        -DBROTLI_BUILD_TOOLS=OFF
        -DBROTLI_DISABLE_TESTS=TRUE
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    for PC_FILE in "$PC_DIR"/*brotli*.pc; do
        [[ -e "$PC_FILE" ]] || continue
        sed -i "s|^Cflags:.*|& -I\${includedir}/brotli|" "$PC_FILE"
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi
    done
}

ffbuild_cppflags() {
    echo "$static_flags"
}
