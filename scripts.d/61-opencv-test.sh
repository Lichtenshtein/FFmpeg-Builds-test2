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

    # Настраиваем пути поиска конфигов
    export OpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"
    
    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=OFF
        -DOPENCV_GENERATE_PKGCONFIG=ON
        -DCPU_BASELINE=${CPU_ARCH:-BROADWELL}
        -DCPU_DISPATCH=AVX2
        -DENABLE_PIC=ON

        # --- ОТКЛЮЧАЕМ ВСЕ МОДУЛИ, КРОМЕ DNN ---
        -DBUILD_opencv_calib3d=OFF
        -DBUILD_opencv_features2d=OFF
        -DBUILD_opencv_flann=OFF
        -DBUILD_opencv_gapi=OFF
        -DBUILD_opencv_highgui=OFF
        -DBUILD_opencv_imgcodecs=OFF
        -DBUILD_opencv_ml=OFF
        -DBUILD_opencv_objdetect=OFF
        -DBUILD_opencv_photo=OFF
        -DBUILD_opencv_stitching=OFF
        -DBUILD_opencv_video=OFF
        -DBUILD_opencv_videoio=OFF
        
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

        # --- OPENVINO (ГЛАВНАЯ ЦЕЛЬ) ---
        -DWITH_OPENVINO=ON
        -DOpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"
        -DInferenceEngine_DIR="$FFBUILD_PREFIX/lib/cmake"
        -Dngraph_DIR="$FFBUILD_PREFIX/lib/cmake"

        # --- ПРОЧЕЕ ---
        -DBUILD_EXAMPLES=OFF
        -DBUILD_TESTS=OFF
        -DBUILD_PERF_TESTS=OFF
        -DWITH_FFMPEG=OFF
        -DOPENCV_FFMPEG_SKIP_DOWNLOAD=ON

        -DCMAKE_POLICY_DEFAULT_CMP0028=NEW
        -DCMAKE_IMPORTED_NO_SYSTEM=ON
        -DOPENVINO_STATIC_COMPILATION=OFF
        -DOPENCV_SKIP_PYTHON_LOADER=ON
        -DBUILD_opencv_model_diagnostics=OFF # Отключаем проблемную утилиту
    )

    if [[ $TARGET == win64 ]]; then
        myconf+=(
        -DWITH_GSTREAMER=OFF
        -DWITH_WIN32UI=OFF
        -DWITH_GTK=OFF
        )
    elif [[ $TARGET == linux64 ]]; then
        myconf+=(
        -DWITH_GSTREAMER=ON
        )
    fi

# -ltbb12
    local ADDITIONAL_LDFLAGS="-lopenvino -lopenvino_c -lopenvino_onnx_frontend -ltbb12"

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -Dov_core_EXPORTS -Dov_runtime_EXPORTS -Dov_builder_EXPORTS" \
    LDFLAGS="$LDFLAGS $ADDITIONAL_LDFLAGS" \
    LIBS="$LIBS $ADDITIONAL_LIBS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-libopencv
}

ffbuild_unconfigure() {
    echo --disable-libopencv
}
