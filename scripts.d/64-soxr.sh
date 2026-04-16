#!/bin/bash

SCRIPT_REPO="https://github.com/Jklein64/soxr.git"
SCRIPT_COMMIT="a431f4de6aa118b8962d5035e442b234a7ab6878"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Short-circuit the check to generate a .pc file. We always want it.
    sed -i 's/NOT WIN32/1/g' src/CMakeLists.txt

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DWITH_OPENMP=$([[ $target != winarm64 && "${USE_OPENMP}" == "1" ]] && echo ON || echo OFF)
        -DBUILD_TESTS=OFF
        -DBUILD_EXAMPLES=OFF
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DWITH_DEV_TRACE=OFF # developer trace capability
        -DWITH_DEV_GPROF=OFF # developer grpof output
        -DWITH_HI_PREC_CLOCK=ON # Enable high-precision time-base
        -DWITH_FLOAT_STD_PREC_CLOCK=OFF # floating-point for standard-precision time-base
        -DWITH_LSR_BINDINGS=ON # a libsamplerate-like interface
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if [[ "${USE_OPENMP}" == "1" ]]; then
        if [[ $TARGET != winarm64 ]]; then
            sed -i '/^Libs.private:/ s/$/ -lgomp/' "$PC_DIR/soxr.pc"
        fi
    fi
}

ffbuild_configure() {
    echo --enable-libsoxr
}

ffbuild_unconfigure() {
    echo --disable-libsoxr
}

ffbuild_libs() {
    if [[ "${USE_OPENMP}" == "1" ]]; then
        [[ $TARGET != winarm64 ]] && echo -lgomp
    fi
}
