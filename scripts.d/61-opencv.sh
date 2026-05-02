#!/bin/bash

SCRIPT_REPO="https://github.com/opencv/opencv.git"
SCRIPT_COMMIT="2027a3399076b099930fc8eb2721d8c028fdabc0"

ffbuild_depends() {
    echo vulkan-headers
    echo vulkan-loader
    echo glslang
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

grep -r "JBIG" /opt/ffbuild/lib/cmake/tiff/ || true

    # export OpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"
    export OpenJPEG_DIR="$FFBUILD_PREFIX/lib/cmake/openjpeg-2.5"
    export OpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"

    PYTHON_ROOT=$(python3 -c "import sys; print(sys.prefix)")
    NUMPY_PATH=$(python3 -c "import numpy; print(numpy.get_include())")

    # вырезаем поиск JBIG из процесса нахождения TIFF
    sed -i 's/include(FindTIFF)/set(TIFF_FOUND TRUE); set(TIFF_LIBRARY "${TIFF_LIBRARY}"); set(TIFF_LIBRARIES "${TIFF_LIBRARY}")/g' cmake/OpenCVFindLibsGrfmt.cmake

    # Убираем "умный" парсинг заголовков, который может запутать OpenCV
    sed -i 's/ocv_parse_header.*TIFF_VERSION/message(STATUS "Skipping TIFF header parse")/g' cmake/OpenCVFindLibsGrfmt.cmake

    # очищаем GRFMT_LIBS от мусора в imgcodecs
    sed -i '/list(APPEND GRFMT_LIBS ${TIFF_LIBRARIES})/i set(TIFF_LIBRARIES "${TIFF_LIBRARY}")' modules/imgcodecs/CMakeLists.txt

    mkdir -p build && cd build

    # Создаем фиктивный файл, который удовлетворит требование JBIG::JBIG
    # Это создаст реальную цель в памяти CMake, которую ищет imgcodecs
    cat <<EOF > fix_opencv_deps.cmake
add_library(JBIG::JBIG STATIC IMPORTED)
set_target_properties(JBIG::JBIG PROPERTIES IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/libjbig.a")
add_library(ZLIB::ZLIB STATIC IMPORTED)
set_target_properties(ZLIB::ZLIB PROPERTIES IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/libz.a")
add_library(JPEG::JPEG STATIC IMPORTED)
set_target_properties(JPEG::JPEG PROPERTIES IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/libjpeg.a")
EOF

    local myconf=(
        -DCMAKE_PROJECT_INCLUDE="${PWD}/fix_opencv_deps.cmake"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DENABLE_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DOPENCV_GENERATE_PKGCONFIG=ON
        -DOPENCV_CHECK_COMPILER_FLAGS=OFF
        -DCMAKE_MAP_IMPORTED_CONFIG_DEBUG=Release
        -DCMAKE_POLICY_DEFAULT_CMP0091=NEW 
        -DCPU_BASELINE=AVX2
        -DCPU_DISPATCH=AVX2
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
        -DBUILD_IPP_IW=ON
        # Отключаем лишнее для ускорения сборки
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
        # installed version of numpy not suitable
        -DBUILD_opencv_python3=OFF
        # -DPYTHON3_INCLUDE_PATH="$PYTHON_ROOT/include/python3.12"
        # -DPYTHON3_LIBRARIES="$PYTHON_ROOT/lib/libpython3.12.so"
        # -DPYTHON3_NUMPY_INCLUDE_DIRS="$NUMPY_PATH"
        # -DOPENCV_SKIP_PYTHON_LOADER=ON
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
        # Parallel processing
        -DWITH_OPENMP=OFF
        -DWITH_PTHREADS_PF=OFF
        -DWITH_TBB=ON
        -DTBB_INCLUDE_DIRS="$FFBUILD_PREFIX/include"
        -DTBB_LIB_DIR="$FFBUILD_PREFIX/lib"
        # Указываем пути к библиотекам
        -DCMAKE_DISABLE_FIND_PACKAGE_ZLIB=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_TIFF=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_JPEG=ON
        -DZLIB_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DZLIB_LIBRARY="$FFBUILD_PREFIX/lib/libz.a"
        -DOPENJPEG_INCLUDE_DIR="$FFBUILD_PREFIX/include/openjpeg-2.5"
        -DOPENJPEG_LIBRARY="$FFBUILD_PREFIX/lib/libopenjp2.a"
        -DTIFF_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DTIFF_LIBRARY="$FFBUILD_PREFIX/lib/libtiff.a"
        -DJPEG_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DJPEG_LIBRARY="$FFBUILD_PREFIX/lib/libjpeg.a"
        # Включаем интеграцию с OpenVINO (Inference Engine)
        -DWITH_OPENVINO=ON
        -DOPENVINO_STATIC_COMPILATION=OFF
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
        # CUDA; linux only
        # -DWITH_CUDA=OFF # not supported
        # -DOPENCV_DNN_CUDA=ON
        # -DCUDA_ARCH_BIN=6.1 # Например, для Pascal
        # -DCUDA_ARCH_PTX=6.1
        )
    fi

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS $ADDITIONAL_LIBS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    if ! grep -qiE "OPENVINO:.*(YES|ON|TRUE)" CMakeCache.txt && ! grep -qi "HAVE_OPENVINO:INTERNAL=ON" CMakeCache.txt; then
        echo "ERROR: OpenVINO was not detected in CMakeCache.txt!"
        # Выведем для отладки, что там на самом деле
        grep -i "OPENVINO" CMakeCache.txt
        return 1
    fi

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_libs() {
    echo "-lopencv_dnn -lopencv_imgproc -lopencv_core"
}

ffbuild_configure() {
    echo --enable-libopencv
}

ffbuild_unconfigure() {
    echo --disable-libopencv
}
