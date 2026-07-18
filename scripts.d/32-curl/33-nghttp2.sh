#!/bin/bash

SCRIPT_REPO="https://github.com/nghttp2/nghttp2.git"
SCRIPT_COMMIT="a25ec3de429d038f08f334cd3dc3b637f05fe7bf"

ffbuild_depends() {
    echo zlib
    echo libxml2
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
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DENABLE_HPACK_TOOLS=OFF
        -DENABLE_EXAMPLES=OFF
        -DENABLE_FAILMALLOC=OFF
        -DENABLE_HTTP3=OFF # OFF; HTTP/3 will be at the curl level in conjunction with quiche
        -DENABLE_DOC=OFF
        -DENABLE_LIB_ONLY=ON
        -DENABLE_APP=OFF
        -DBUILD_TESTING=OFF
        -DWITH_LIBXML2=ON # libxml2
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF ) || \
        myconf+=( -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON )

    local static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DNGHTTP2_STATICLIB"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s|^Cflags:.*|& -I\${includedir}/nghttp2|" "$PC_FILE"
        done
        log_info "Cflags paths have been updated."
    fi
}
