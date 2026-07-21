#!/bin/bash

# SCRIPT_REPO="https://github.com/TimothyGu/libilbc.git"
# SCRIPT_COMMIT="6adb26d4a4e159cd66d4b4c5e411cd3de0ab6b5e"

SCRIPT_REPO="https://github.com/mal359/libilbc.git"
SCRIPT_COMMIT="92453650e3dc53c0ca209dbf04d3153a5517a91d"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    # Cut the build of test executables from CMakeLists.txt
    sed -i '/add_executable[[:space:]]*(ilbc_test/,/)/d' CMakeLists.txt
    sed -i '/target_link_libraries[[:space:]]*(ilbc_test/,/)/d' CMakeLists.txt
    sed -i '/add_executable[[:space:]]*(ilbc_test2/,/)/d' CMakeLists.txt
    sed -i '/target_link_libraries[[:space:]]*(ilbc_test2/,/)/d' CMakeLists.txt
    sed -i '/add_custom_target[[:space:]]*(ilbc_test-sample/,/)/d' CMakeLists.txt
    sed -i '/add_custom_target[[:space:]]*(ilbc_test2-sample/,/)/d' CMakeLists.txt

    # Remove the ilbc_test reference from the installation section
    sed -i 's/install[[:space:]]*([[:space:]]*TARGETS[[:space:]]\+ilbc[[:space:]]\+ilbc_test/install(TARGETS ilbc/g' CMakeLists.txt

    mkdir -p _build && cd _build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_TESTING=OFF
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DWITH_NEON=OFF # Enable NEON optimization
    )

    local EXTRA_CFLAGS="-Wno-error=implicit-function-declaration"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $EXTRA_CFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $EXTRA_CFLAGS" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Cut the line
    sed -i '/^Cflags:/d' "$PC_DIR/libilbc.pc"
    # Write a new clean line
    echo "Cflags: -I\${includedir}" >> "$PC_DIR/libilbc.pc"
}

ffbuild_configure() {
    echo --enable-libilbc
}

ffbuild_unconfigure() {
    echo --disable-libilbc
}
