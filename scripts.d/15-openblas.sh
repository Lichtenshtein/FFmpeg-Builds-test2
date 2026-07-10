#!/bin/bash

SCRIPT_REPO="https://github.com/OpenMathLib/OpenBLAS.git"
SCRIPT_COMMIT="7c991951a5f3b1dbdd27f200f2bd4557b4c51a3d"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf lapack-netlib ctest cpp_thread_test utest test"
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_STATIC_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DCROSS=ON
        -DBINARY=64
        -DTARGET=HASWELL
        -DDYNAMIC_ARCH=OFF
        -DNUM_THREADS=64
        -DBUILD_WITHOUT_LAPACK=ON
        -DBUILD_WITHOUT_LAPACKE=ON
        -DBUILD_WITHOUT_CBLAS=OFF
        -DBUILD_TESTING=OFF
        -DBUILD_BENCHMARKS=OFF
        -DUTEST_CHECK=OFF
        -DNO_AFFINITY=ON
        -DUSE_LOCKING=ON
        -DHOSTCC=gcc
        -DCPP_THREAD_SAFETY_USE_OPENMP=$([ "${USE_OPENMP}" == "1" ] && echo ON || echo OFF)
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${OPENMP_C}${USELTO}${USELTO_C} -DNO_AFFINITY=1" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${OPENMP_C}${USELTO}${USELTO_C} -DNO_AFFINITY=1" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if ls "$PC_DIR"/*openblas*.pc >/dev/null 2>&1; then
        for PC_FILE in "$PC_DIR"/*openblas*.pc; do
            [[ -e "$PC_FILE" ]] || continue
            sed -i "s|^Libs.private:.*|Libs.private: $LIBS|" "$PC_FILE"
            if ! grep -qF -- "-pthread" "$PC_FILE"; then
                sed -i "/^Libs.private:/ s/$/ -pthread/" "$PC_FILE"
            fi
            if [[ "${myconf[@]}" =~ "CPP_THREAD_SAFETY_USE_OPENMP=ON" ]]; then
                sed -i "/^Libs.private:/ s/$/ ${OPENMP_LIB}/" "$PC_FILE"
            fi
            sed -i "s|^Libs:.*|Libs: -L\${libdir} -lopenblas|" "$PC_FILE"
            sed -i "s|^Cflags:.*|& -I\${includedir}/openblas|" "$PC_FILE"
        done
    fi
}
