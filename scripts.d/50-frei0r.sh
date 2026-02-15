#!/bin/bash

SCRIPT_REPO="https://github.com/dyne/frei0r.git"
SCRIPT_COMMIT="ced05b4fcb94481d9b8fb81b4af3e63bd8026491"

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return -1
    (( $(ffbuild_ffver) >= 500 )) || return -1
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerfinal() {
    to_df "COPY --link --from=${PREVLAYER} \$FFBUILD_PREFIX/. \$FFBUILD_PREFIX"
    to_df "ENV FREI0R_PATH=\$FFBUILD_PREFIX/lib/frei0r-1"
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    # флаги для игнорирования несовместимых типов в SIMD коде (актуально для GCC 14)
    # Флаг -flax-vector-conversions разрешает неявное приведение __m128i к __m128
    export CFLAGS="$CFLAGS -flax-vector-conversions -Wno-error=incompatible-pointer-types"
    export CXXFLAGS="$CXXFLAGS -flax-vector-conversions -Wno-error=incompatible-pointer-types"

        # -DWITHOUT_OPENCV=ON
    cmake -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DOPENCV_DIR="$FFBUILD_PREFIX/lib/cmake/opencv4" \ 
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DWITHOUT_GAVL=ON \
        ..

    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install
}

ffbuild_configure() {
    echo --enable-frei0r
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) >= 404 )) || return 0
    echo --disable-frei0r
}
