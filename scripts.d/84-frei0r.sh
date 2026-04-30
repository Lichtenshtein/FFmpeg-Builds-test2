#!/bin/bash

SCRIPT_REPO="https://github.com/dyne/frei0r.git"
SCRIPT_COMMIT="32e91405d2ec5e222f75175b36dc4cc7bc0667ef"

# export SKIP_PRE_PATCH=1

ffbuild_depends() {
    echo opencv
    echo cairo
    echo gavl
    # echo nettle # from gavl
    # echo gnutls # from gavl
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
    # ADDITIONAL_FLAGS="-flax-vector-conversions -fpermissive -Wno-error=incompatible-pointer-types -Wno-error=int-conversion"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DWITHOUT_FACERECOGNITION=OFF # facedetect and facebl0r plugins
        -DWITHOUT_OPENCV=OFF # required for facebl0r filter
        -DWITHOUT_CAIRO=OFF  # required for cairo- filters and mixers
        -DWITHOUT_GAVL=OFF   # required for scale0tilt and vectorscope filters
        # -DCairo_INCLUDE_DIR="" # ?
        -DOPENCV_DIR="$FFBUILD_PREFIX/lib/cmake/opencv4"
    )

    CFLAGS="$CFLAGS $CPPFLAGS $ADDITIONAL_FLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS $ADDITIONAL_FLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-frei0r
}

ffbuild_unconfigure() {
    echo --disable-frei0r
}
