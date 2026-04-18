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

        # --- ОТКЛЮЧАЕМ ТЯЖЕЛЫЕ ЗАВИСИМОСТИ ---
        -DOPENCV_FORCE_3RDPARTY_BUILD=ON
        
        # --- ПАРАЛЛЕЛИЗМ ---
        -DWITH_TBB=OFF
        -DTBB_INCLUDE_DIRS="$FFBUILD_PREFIX/include"
        -DTBB_LIB_DIR="$FFBUILD_PREFIX/lib"
        -DWITH_OPENMP=ON
        -DWITH_PTHREADS_PF=OFF

        # --- OPENVINO (ГЛАВНАЯ ЦЕЛЬ) ---

        # --- ПРОЧЕЕ ---
        -DBUILD_EXAMPLES=OFF
        -DBUILD_PACKAGE=OFF
        -DBUILD_DOCS=OFF
        -DBUILD_TESTS=OFF
        -DBUILD_PERF_TESTS=OFF
        -DBUILD_FAT_JAVA_LIB=OFF
        -DBUILD_JAVA=OFF
        -DBUILD_opencv_apps=OFF
        -DBUILD_opencv_python2=OFF
        -DBUILD_opencv_java=OFF
        -DBUILD_opencv_python3=OFF
        -DWITH_FFMPEG=OFF
        -DOPENCV_FFMPEG_SKIP_DOWNLOAD=ON

        -DCMAKE_POLICY_DEFAULT_CMP0028=NEW
        -DCMAKE_IMPORTED_NO_SYSTEM=ON
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
