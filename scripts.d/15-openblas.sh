#!/bin/bash

SCRIPT_REPO="https://github.com/OpenMathLib/OpenBLAS.git"
SCRIPT_COMMIT="f959027a068f1a12e473377aa94b53395fc0064c"

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

    log_info "${BROOM_MARK} Patching CMake scripts to suppress warnings..."
    find . -name "CMakeLists.txt" -o -name "*.cmake" | xargs sed -i 's/-Wunused-function/-Wno-unused-function/g' 2>/dev/null || true
    find . -name "CMakeLists.txt" -o -name "*.cmake" | xargs sed -i 's/-Wunused-variable/-Wno-unused-variable/g' 2>/dev/null || true

    mkdir -p build && cd build

    local use_fortran=OFF
    if [ -n "$FC" ] && command -v "$FC" >/dev/null 2>&1; then
        log_info "${TARGET_MARK} Fortran compiler found at $FC. Activating native Fortran LAPACK."
        use_fortran=ON
    else
        log_warn "Fortran compiler ($FC) NOT found. Falling back to C-only LAPACK."
        if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
            log_debug "${DIRS_MARK} Contents of /opt/ct-ng/bin (first 20 files):"
            ls -F /opt/ct-ng/bin | head -n 30
        fi
    fi

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
        -DC_LAPACK=$([ "$use_fortran" == "ON" ] && echo OFF || echo ON) # Build from C sources instead of Fortran
        -DCMAKE_Fortran_COMPILER=$([ "$use_fortran" == "ON" ] && echo "$FC" || echo OFF)
        -DBUILD_LAPACK_DEPRECATED=$([ "$use_fortran" == "ON" ] && echo ON || echo OFF) # Drops hundreds of unneeded f2c files
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

    CFLAGS="$CFLAGS $CPPFLAGS ${OPENMP_C}${USELTO}${USELTO_C} -DNO_AFFINITY=1" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${OPENMP_C}${USELTO}${USELTO_C} -DNO_AFFINITY=1" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
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
