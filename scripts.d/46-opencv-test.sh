#!/bin/bash

SCRIPT_REPO="https://github.com/opencv/opencv.git"
SCRIPT_COMMIT="2027a3399076b099930fc8eb2721d8c028fdabc0"

ffbuild_depends() {
    echo vulkan-headers
    echo vulkan-loader
    echo glslang-test
    echo shaderc
    echo spirv-cross
    echo spirv-headers
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    # Настраиваем пути для поиска OpenVINO, который мы установили ранее
    export OpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake/OpenVINO"

    local mycmake=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_WITH_STATIC_CRT=ON
        -DOPENCV_GENERATE_PKGCONFIG=ON
        -DENABLE_PIC=ON
        -DOPENCV_ENABLE_NONFREE=ON
        # Отключаем лишнее для ускорения сборки
        -DBUILD_EXAMPLES=OFF
        -DBUILD_PACKAGE=OFF
        -DBUILD_DOCS=OFF
        -DBUILD_TESTS=OFF
        -DBUILD_PERF_TESTS=OFF
        -DBUILD_FAT_JAVA_LIB=OFF
        -DBUILD_JAVA=OFF
        -DBUILD_opencv_apps=OFF
        -DBUILD_opencv_python2=OFF
        -DBUILD_opencv_python3=OFF
        -DBUILD_opencv_java=OFF
        -DWITH_IPP=OFF
        -DWITH_WIN32UI=OFF
        -DWITH_JPEGXL=ON
        -DWITH_OPENJPEG=ON
        -DWITH_JPEG=ON
        -DWITH_WEBP=ON
        -DWITH_PNG=ON
        -DWITH_TIFF=ON
        -DWITH_MSMF_DXVA=ON
        -DWITH_OPENCL_D3D11_NV=ON
        -DWITH_OPENGL=ON
        -DWITH_OPENMP=$([ "${USE_OPENMP}" == "1" ] && echo ON || echo OFF )
        -DWITH_OPENCL=ON
        -DWITH_ZLIB_NG=ON
        -DWITH_VULKAN=ON
        -DWITH_PTHREADS_PF=ON
        # Включаем интеграцию с OpenVINO (Inference Engine)
        -DWITH_OPENVINO=ON
        -DInferenceEngine_DIR="$FFBUILD_PREFIX/lib/cmake/OpenVINO"
        -DOpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake/OpenVINO"
        -Dngraph_DIR="$FFBUILD_PREFIX/lib/cmake/ngraph"
        -DOPENVINO_LIB_DIRS="$FFBUILD_PREFIX/lib"
        -DOPENVINO_INCLUDE_DIRS="$FFBUILD_PREFIX/include"
        -DCPU_BASELINE=${CPU_ARCH:-BROADWELL}
        -DCPU_DISPATCH=AVX2
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -DENABLE_LTO=ON )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS $ADDITIONAL_LIBS" \
    cmake "${mycmake[@]}" .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

}

ffbuild_configure() {
    echo --enable-libopencv
}

ffbuild_unconfigure() {
    echo --disable-libopencv
}
