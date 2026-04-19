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
    echo libjxl
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir -p build && cd build

    # Указываем OpenCV, где искать OpenVINO
    export OpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"

    local myconf=(
        -DCMAKE_MAP_IMPORTED_CONFIG_DEBUG=Release
        -DCMAKE_POLICY_DEFAULT_CMP0091=NEW 
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_opencv_dnn=ON
        -DBUILD_opencv_core=ON
        -DBUILD_opencv_imgproc=ON
        -DBUILD_EXAMPLES=OFF
        -DBUILD_PACKAGE=OFF
        -DBUILD_DOCS=OFF
        -DBUILD_TESTS=OFF
        -DBUILD_PERF_TESTS=OFF
        -DBUILD_FAT_JAVA_LIB=OFF
        -DBUILD_JAVA=OFF
        -DBUILD_opencv_model_diagnostics=OFF
        -DBUILD_opencv_apps=OFF
        -DBUILD_opencv_python2=OFF
        -DBUILD_opencv_java=OFF
        # --- ОТКЛЮЧАЕМ ТЯЖЕЛЫЕ ЗАВИСИМОСТИ ---
        -DWITH_AVIF=OFF
        -DWITH_JPEG=OFF
        -DWITH_PNG=OFF
        -DWITH_WEBP=OFF
        -DWITH_TIFF=OFF
        -DWITH_OPENJPEG=OFF
        -DWITH_JPEGXL=OFF
        -DWITH_OPENEXR=OFF
        -DWITH_VULKAN=OFF
        -DWITH_OPENCL=OFF
        -DWITH_OPENGL=OFF
        -DWITH_IPP=OFF
        -DBUILD_ZLIB=ON # Пусть соберет свою маленькую копию для внутренних нужд dnn
        
        # --- ПАРАЛЛЕЛИЗМ ---
        -DWITH_TBB=OFF
        -DTBB_INCLUDE_DIRS="$FFBUILD_PREFIX/include"
        -DTBB_LIB_DIR="$FFBUILD_PREFIX/lib"
        -DWITH_OPENMP=ON
        -DWITH_PTHREADS_PF=OFF
        # Отключаем всё лишнее
        -DBUILD_opencv_calib3d=OFF -DBUILD_opencv_features2d=OFF -DBUILD_opencv_flann=OFF 
        -DBUILD_opencv_highgui=OFF -DBUILD_opencv_videoio=OFF -DBUILD_opencv_imgcodecs=OFF
        
        -DWITH_OPENVINO=ON
        -DOpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"
        -DInferenceEngine_DIR="$FFBUILD_PREFIX/lib/cmake"
        -DOPENVINO_STATIC_COMPILATION=OFF
        -DCPU_BASELINE=AVX2
        -DWITH_FFMPEG=OFF
    )

    # ВАЖНО: Мы НЕ передаем ручные LDFLAGS с плагинами. 
    # CMake сам возьмет их из OpenVINOTargets.cmake
    cmake -G Ninja "${myconf[@]}" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS $CPPFLAGS" \
        -DCMAKE_C_FLAGS="$CFLAGS $CPPFLAGS" \
        .. || return 1

    if ! grep -q "OpenVINO:.*YES" CMakeCache.txt; then
        echo "ERROR: OpenVINO was not detected by OpenCV!"
        grep "OpenVINO" CMakeCache.txt
        return 1
    fi

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

# ffbuild_libs() {
    # echo "-lopencv_dnn -lopencv_imgproc -lopencv_core"
# }

ffbuild_configure() {
    echo --enable-libopencv
}

ffbuild_unconfigure() {
    echo --disable-libopencv
}
