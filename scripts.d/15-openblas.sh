#!/bin/bash

SCRIPT_REPO="https://github.com/OpenMathLib/OpenBLAS.git"
SCRIPT_COMMIT="62bcfb0dc9f1cfa685fc04135c50e2780c303137"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    # lapack-netlib
    echo "rm -rf ctest cpp_thread_test utest test"
}

ffbuild_dockerbuild() {
    set -e

    local NO_WARN="-Wno-unused-function -Wno-unused-variable"

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
        -DBUILD_WITHOUT_LAPACK=OFF
        -DBUILD_WITHOUT_LAPACKE=OFF
        -DBUILD_WITHOUT_CBLAS=OFF
        -DBUILD_TESTING=OFF
        -DBUILD_BENCHMARKS=OFF
        -DUTEST_CHECK=OFF
        -DNO_AFFINITY=ON
        -DUSE_LOCKING=ON
        -DHOSTCC=gcc
        -DCPP_THREAD_SAFETY_USE_OPENMP=$([ "${USE_OPENMP}" == "1" ] && echo ON || echo OFF)
    )

    CFLAGS="-O3 -march=broadwell -mtune=broadwell -pipe -g1 -fstack-protector-strong -Wno-attributes -I/opt/ffbuild/include ${NO_WARN}" \
    CXXFLAGS="-O3 -march=broadwell -mtune=broadwell -pipe -g1 -mms-bitfields -fstack-protector-strong -Wno-attributes -I/opt/ffbuild/include ${NO_WARN}" \
    LDFLAGS="-Wl,-Bstatic -static -static-libgcc -static-libstdc++ -pipe -fuse-ld=lld -Wl,--as-needed -L/opt/ffbuild/lib" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local fortran_libs=""

    if [ "$use_fortran" == "ON" ]; then
        log_info "${TARGET_MARK} Injecting GNU Fortran runtime libraries into pkg-config."
        fortran_libs=" -lgfortran -lquadmath"
    fi

    # if [[ "${myconf[@]}" =~ "-DBUILD_WITHOUT_LAPACK=OFF" ]]; then
        # if grep -q "ONLY_C=0" "config.h" 2>/dev/null || grep -q "#define TRN_MANUAL" "config.h" 2>/dev/null || [ ! -f "config.h" ]; then
            # if grep -E "^CMAKE_Fortran_COMPILER:FILEPATH=" CMakeCache.txt | grep -E -iq "flang|clang"; then
                # log_info "${TARGET_MARK} LLVM Flang detected via CMakeCache. Adding -lflang -lflangrti to Libs.private"
                # fortran_libs=" -lflang -lflangrti"
            # elif grep -E "^CMAKE_Fortran_COMPILER:FILEPATH=" CMakeCache.txt | grep -E -iq "gfortran|gcc"; then
                # log_info "${TARGET_MARK} GNU Fortran detected via CMakeCache. Adding -lgfortran -lquadmath to Libs.private"
                # fortran_libs=" -lgfortran -lquadmath"
            # else
                # log_warn "Unknown Fortran compiler identity in CMakeCache.txt. Skipping library injection."
            # fi
        # else
            # log_warn "OpenBLAS build log shows C-only LAPACK wrapper was used. No Fortran runtime injected."
        # fi
    # fi

    if ls "$PC_DIR"/*openblas*.pc >/dev/null 2>&1; then
        for PC_FILE in "$PC_DIR"/*openblas*.pc; do
            [[ -e "$PC_FILE" ]] || continue

            if ! grep -q "^Libs.private:" "$PC_FILE"; then
                log_info "${LOGS_MARK} Libs.private not found in $(basename "$PC_FILE"). Adding placeholder..."
                sed -i '/^Libs:/a Libs.private:' "$PC_FILE"
            fi

            sed -i "s|^Libs.private:.*|Libs.private: $LIBS|" "$PC_FILE"
            if ! grep -qF -- "-pthread" "$PC_FILE"; then
                sed -i "/^Libs.private:/ s/$/ -pthread/" "$PC_FILE"
            fi
            if [[ "${myconf[@]}" =~ "CPP_THREAD_SAFETY_USE_OPENMP=ON" ]]; then
                sed -i "/^Libs.private:/ s/$/ ${OPENMP_LIB}/" "$PC_FILE"
            fi
            if [[ -n "$fortran_libs" ]]; then
                sed -i "/^Libs.private:/ s/$/${fortran_libs}/" "$PC_FILE"
            fi
            sed -i "s|^Libs:.*|Libs: -L\${libdir} -lopenblas|" "$PC_FILE"
            sed -i "s|^Cflags:.*|& -I\${includedir}/openblas|" "$PC_FILE"
        done
    fi
}
