#!/bin/bash

SCRIPT_REPO="https://github.com/opencv/opencv.git"
SCRIPT_COMMIT="4.13.0"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    # Настраиваем пути для поиска OpenVINO, который мы установили ранее
    export OpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake/OpenVINO"

    local mycmake=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_WITH_STATIC_CRT=OFF
        # Отключаем лишнее для ускорения сборки
        -DBUILD_EXAMPLES=OFF
        -DBUILD_TESTS=OFF
        -DBUILD_PERF_TESTS=OFF
        -DBUILD_opencv_apps=OFF
        -DBUILD_opencv_python2=OFF
        -DBUILD_opencv_python3=OFF
        -DBUILD_opencv_java=OFF
        # Включаем интеграцию с OpenVINO (Inference Engine)
        -DWITH_OPENVINO=ON
        -DOPENVINO_LIB_DIRS="$FFBUILD_PREFIX/lib"
        -DOPENVINO_INCLUDE_DIRS="$FFBUILD_PREFIX/include"
        # Оптимизация под ваш Xeon Broadwell
        -DCPU_BASELINE=BROADWELL
        -DCPU_DISPATCH=AVX2
    )

    cmake "${mycmake[@]}" ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libopencv
}

ffbuild_unconfigure() {
    echo --disable-libopencv
}
