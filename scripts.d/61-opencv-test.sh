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

    export OpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"
    export OpenJPEG_DIR="$FFBUILD_PREFIX/lib/cmake/openjpeg-2.5"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DENABLE_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DOPENCV_GENERATE_PKGCONFIG=ON
        -DCPU_BASELINE=${CPU_ARCH:-BROADWELL}
        -DCPU_DISPATCH=AVX,AVX2
        -DENABLE_PIC=ON
        -DOPENCV_ENABLE_NONFREE=ON
        # Используем то, что уже собрали
        -DBUILD_OPENEXR=ON # why not
        -DBUILD_ZLIB=OFF
        -DBUILD_JPEG=OFF
        -DBUILD_PNG=OFF
        -DBUILD_OPENJPEG=OFF
        -DBUILD_WEBP=OFF
        -DBUILD_TIFF=OFF
        -DBUILD_TBB=OFF
        -DBUILD_IPP_IW=OFF
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
        #-DBUILD_opencv_python3=OFF
        -DBUILD_opencv_java=OFF
        # Включаем форматы
        -DWITH_AVIF=ON
        -DWITH_IPP=ON
        -DOPENCV_IPP_ENABLE_ALL=ON
        -DWITH_JPEG=ON
        -DWITH_JPEGXL=ON
        -DWITH_MSMF_DXVA=ON
        -DWITH_OPENCL=ON
        -DWITH_OPENCL_D3D11_NV=ON
        -DWITH_OPENGL=ON
        -DWITH_OPENJPEG=ON
        -DWITH_PNG=ON
        -DWITH_TIFF=ON
        -DWITH_VULKAN=ON
        -DWITH_WEBP=ON
        -DWITH_ZLIB_NG=ON
        -DWITH_CUDA=OFF
        # Parallel processing
        -DWITH_OPENMP=OFF
        -DWITH_PTHREADS_PF=OFF
        -DWITH_TBB=ON
        -DTBB_INCLUDE_DIRS="$FFBUILD_PREFIX/include"
        -DTBB_LIB_DIR="$FFBUILD_PREFIX/lib"
        # Указываем пути к библиотекам
        -DZLIB_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DZLIB_LIBRARY="$FFBUILD_PREFIX/lib/libz.a"
        -DOPENJPEG_INCLUDE_DIR="$FFBUILD_PREFIX/include/openjpeg-2.5"
        -DOPENJPEG_LIBRARY="$FFBUILD_PREFIX/lib/libopenjp2.a"
        # Включаем интеграцию с OpenVINO (Inference Engine)
        -DWITH_OPENVINO=ON
        -DOpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"
        -DInferenceEngine_DIR="$FFBUILD_PREFIX/lib/cmake"
        # Отключаем загрузку готовых DLL FFmpeg
        -DOPENCV_FFMPEG_SKIP_DOWNLOAD=ON
        -DWITH_FFMPEG=OFF # ON if standalone
        # plugins
        -DHIGHGUI_ENABLE_PLUGINS=ON
        -DVIDEOIO_ENABLE_PLUGINS=ON
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

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
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
