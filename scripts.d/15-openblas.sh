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

    local fc_compiler="${FC:-x86_64-w64-mingw32-gfortran}"

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
        -DC_LAPACK=OFF # Build from C sources instead of Fortran
        -DCMAKE_Fortran_COMPILER="$FC"
        # -DCMAKE_Fortran_COMPILER_WORKS=ON
        -DBUILD_WITHOUT_CBLAS=OFF
        -DBUILD_TESTING=OFF
        -DBUILD_BENCHMARKS=OFF
        -DUTEST_CHECK=OFF
        -DNO_AFFINITY=ON
        -DUSE_LOCKING=ON
        -DHOSTCC=gcc
        -DCPP_THREAD_SAFETY_USE_OPENMP=$([ "${USE_OPENMP}" == "1" ] && echo ON || echo OFF)
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${OPENMP_C}${USELTO}${USELTO_C} -DNO_AFFINITY=1"
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${OPENMP_C}${USELTO}${USELTO_C} -DNO_AFFINITY=1"
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}"

    local flang_fflags=""
    for flag in $CFLAGS; do
        if [[ "$flag" == *"-flto="* ]]; then
            flang_fflags="$flang_fflags -flto"
            continue
        fi
        [[ "$flag" == *"-ffat-lto-objects"* ]] && continue
        [[ "$flag" == *"-flto-partition"* ]] && continue
        [[ "$flag" == *"-ffat-lto-objects"* ]] && continue
        [[ "$flag" == *"-fmerge-all-constants"* ]] && continue
        [[ "$flag" == *"-fno-var-tracking-assignments"* ]] && continue
        [[ "$flag" == *"-fgraphite-identity"* ]] && continue
        [[ "$flag" == *"-floop-nest-optimize"* ]] && continue
        [[ "$flag" == *"-std=gnu17"* ]] && continue

        # if [[ "$flag" == *"-fgraphite-identity"* || "$flag" == *"-floop-nest-optimize"* ]]; then
            # [[ "$flang_fflags" == *"-mllvm -polly"* ]] || flang_fflags="$flang_fflags -mllvm -polly -mllvm -polly-vectorizer=stripmine"
            # continue
        # fi

        [[ "$flag" == *"-pipe"* ]] && continue
        [[ "$flag" == *"-fstack-protector-strong"* ]] && continue
        [[ "$flag" == *"-mms-bitfields"* ]] && continue
        [[ "$flag" == *"-Wno-attributes"* ]] && continue
        [[ "$flag" == *"-mconsole"* ]] && continue
        flang_fflags="$flang_fflags $flag"
    done

    flang_fflags="--target=${FFBUILD_TOOLCHAIN} $flang_fflags"


    local mingw_sysroot="/opt/ct-ng/x86_64-w64-mingw32/x86_64-w64-mingw32/sys-root/mingw"
    local gcc_runtime_dir="/opt/ct-ng/lib/gcc/x86_64-w64-mingw32/15.2.0"
    local orig_env_ldflags="$LDFLAGS"

    local flang_ldflags=""
    for flag in $LDFLAGS; do
        if [[ "$flag" == *"-flto="* ]]; then
            flang_ldflags="$flang_ldflags -flto"
            continue
        fi
        [[ "$flag" == *"-static-libgcc"* ]] && continue
        [[ "$flag" == *"-static-libstdc++"* ]] && continue
        [[ "$flag" == *"-flto-partition=balanced"* ]] && continue
        [[ "$flag" == *"-pipe"* ]] && continue
        # [[ "$flag" == *"-fmerge-all-constants"* ]] && continue
        # [[ "$flag" == *"-fno-var-tracking-assignments"* ]] && continue
        # [[ "$flag" == *"-fgraphite-identity"* ]] && continue
        # [[ "$flag" == *"-floop-nest-optimize"* ]] && continue
        # [[ "$flag" == *"-std=gnu17"* ]] && continue

        # if [[ "$flag" == *"-fgraphite-identity"* || "$flag" == *"-floop-nest-optimize"* ]]; then
            # [[ "$flang_fflags" == *"-mllvm -polly"* ]] || flang_fflags="$flang_fflags -mllvm -polly -mllvm -polly-vectorizer=stripmine"
            # continue
        # fi

        # [[ "$flag" == *"-fstack-protector-strong"* ]] && continue
        # [[ "$flag" == *"-mms-bitfields"* ]] && continue
        # [[ "$flag" == *"-Wno-attributes"* ]] && continue
        # [[ "$flag" == *"-mconsole"* ]] && continue
        flang_ldflags="$flang_ldflags $flag"
    done

    flang_ldflags="-B${mingw_sysroot}/lib -B${gcc_runtime_dir} -L${mingw_sysroot}/lib $flang_ldflags"

    CFLAGS="$CFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    FFLAGS="$flang_fflags" \
    LDFLAGS="$flang_ldflags" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    export LDFLAGS="$orig_env_ldflags"

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local fortran_libs=""

    if [[ "${myconf[@]}" =~ "-DBUILD_WITHOUT_LAPACK=OFF" ]]; then
        if grep -q "ONLY_C=0" "config.h" 2>/dev/null || grep -q "#define TRN_MANUAL" "config.h" 2>/dev/null || [ ! -f "config.h" ]; then
            if grep -E "^CMAKE_Fortran_COMPILER:FILEPATH=" CMakeCache.txt | grep -E -iq "flang|clang"; then
                log_info "${TARGET_MARK} LLVM Flang detected via CMakeCache. Adding -lflang -lflangrti to Libs.private"
                fortran_libs=" -lflang -lflangrti"
            elif grep -E "^CMAKE_Fortran_COMPILER:FILEPATH=" CMakeCache.txt | grep -E -iq "gfortran|gcc"; then
                log_info "${TARGET_MARK} GNU Fortran detected via CMakeCache. Adding -lgfortran -lquadmath to Libs.private"
                fortran_libs=" -lgfortran -lquadmath"
            else
                log_warn "Unknown Fortran compiler identity in CMakeCache.txt. Skipping library injection."
            fi
        else
            log_warn "OpenBLAS build log shows C-only LAPACK wrapper was used. No Fortran runtime injected."
        fi
    fi

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
