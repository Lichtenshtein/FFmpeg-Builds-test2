#!/bin/bash

SCRIPT_REPO="https://github.com/dyne/frei0r.git"
SCRIPT_COMMIT="530f7e6388c6931f20aa2ca9e4ea33a60df7aca7"

ffbuild_depends() {
    echo opencv-test
    echo cairo
}

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerfinal() {
    to_df "COPY --link --from=${PREVLAYER} \$FFBUILD_PREFIX/. \$FFBUILD_PREFIX"
    to_df "ENV FREI0R_PATH=\$FFBUILD_PREFIX/lib/frei0r-1"
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    # флаги для игнорирования несовместимых типов в SIMD коде (актуально для GCC 14)
    # Флаг -flax-vector-conversions разрешает неявное приведение __m128i к __m128
    # Добавляем -fpermissive для некоторых старых плагинов frei0r
    ADDITIONAL_FLAGS="-flax-vector-conversions -Wno-error=incompatible-pointer-types -fpermissive"

    CFLAGS="$CFLAGS $CPPFLAGS $ADDITIONAL_FLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS $ADDITIONAL_FLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DOPENCV_DIR="$FFBUILD_PREFIX/lib/cmake/opencv4" \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DWITHOUT_OPENCV=OFF \
        -DWITHOUT_FACERECOGNITION=ON \
        -DWITHOUT_CAIRO=OFF \
        -DWITHOUT_GAVL=OFF \
        .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

}

ffbuild_configure() {
    echo --enable-frei0r
}

ffbuild_unconfigure() {
    echo --disable-frei0r
}
