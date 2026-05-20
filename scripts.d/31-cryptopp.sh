#!/bin/bash

SCRIPT_REPO="https://github.com/abdes/cryptopp-cmake.git"
SCRIPT_COMMIT="866aceb8b13b6427a3c4541288ff412ad54f11ea"

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
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCRYPTOPP_BUILD_SHARED=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCRYPTOPP_BUILD_TESTING=OFF
        -DCRYPTOPP_BUILD_DOCUMENTATION=OFF
        -DCRYPTOPP_USE_OPENMP=$([ "$USE_OPENMP" == "1" ] && echo ON || echo OFF)
        # Отключаем промежуточный таргет объектов
        -DCRYPTOPP_USE_INTERMEDIATE_OBJECTS_TARGET=OFF
    )

    # [[ "${USE_LTO}" == "1" ]] && LTO_FLAGS="-fno-devirtualize -fno-devirtualize-speculatively"

    CFLAGS="$CFLAGS $CPPFLAGS $static_flags $OPENMP_C ${USELTO}${USELTO_C} $LTO_FLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS $static_flags $OPENMP_C ${USELTO}${USELTO_C} $LTO_FLAGS" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS $OPENMP_LIB" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/cryptopp.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: Crypto++
Description: A modern CMake build project for Crypto++
Version: 8.9.0
Libs: -L\${libdir} -lcryptopp
Libs.private: -lstdc++
Cflags: -I\${includedir} -I\${includedir}/cryptopp
EOF

    ln -sf cryptopp.pc "$PC_DIR/libcryptopp.pc"
}
