#!/bin/bash
# export USE_VERS_FINDER=1
SCRIPT_REPO="https://github.com/mpeg5/xeve.git"
SCRIPT_COMMIT="429c18a7736ffc010e1c550e8015ff18a242d06c"

ffbuild_enabled() {
    [[ $TARGET == *arm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    local VER_FULL="${VER_FULL:-0.5.1}"

    if [ ! -f "version.txt" ]; then
        rm -f version.txt
        log_info "Adding version..."
        echo "v${VER_FULL}" > version.txt
    fi

    find pkgconfig -name "*.pc.in" -exec sed -i "s|Version: .*|Version: ${VER_FULL}|g" {} +

    find src_base -name "CMakeLists.txt" -exec sed -i 's|${CMAKE_CURRENT_SOURCE_DIR}/pkgconfig/|${CMAKE_CURRENT_SOURCE_DIR}/../pkgconfig/|g' {} +
    find src_main -name "CMakeLists.txt" -exec sed -i 's|${CMAKE_CURRENT_SOURCE_DIR}/pkgconfig/|${CMAKE_CURRENT_SOURCE_DIR}/../pkgconfig/|g' {} +

    mkdir -p _build && cd _build

    local myconf=(
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        # added by patch
        -DXEVE_BUILD_APP=OFF
        -DXEVE_INSTALL=ON
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-libxeve
}

ffbuild_unconfigure() {
    echo --disable-libxeve
}