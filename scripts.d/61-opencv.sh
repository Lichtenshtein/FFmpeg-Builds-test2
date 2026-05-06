#!/bin/bash

SCRIPT_REPO="https://github.com/opencv/opencv.git"
SCRIPT_COMMIT="10dad24385b547e4120cc07ddc27cdd202d753e0"

export SKIP_POST_PATCH=1

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

    # временно перемещаем "отравленные" .cmake файлы tiff
    local TIFF_CMAKE_DIR="$FFBUILD_PREFIX/lib/cmake/tiff"
    local TIFF_HIDE_DIR="$TMP_DIR/tiff_hide"
    if [ -d "$TIFF_CMAKE_DIR" ]; then
        log_info "Hiding TIFF CMake configs to force raw library usage..."
        mkdir -p "$TIFF_HIDE_DIR"
        mv "$TIFF_CMAKE_DIR"/* "$TIFF_HIDE_DIR/"
    fi

    # export OpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"
    export OpenJPEG_DIR="$FFBUILD_PREFIX/lib/cmake/openjpeg-2.5"
    export OpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"

    PYTHON_ROOT=$(python3 -c "import sys; print(sys.prefix)")
    NUMPY_PATH=$(python3 -c "import numpy; print(numpy.get_include())")

    mkdir -p build && cd build

    local myconf=(
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
        # IPP
        -DBUILD_IPP_IW=ON
        -DWITH_IPP=ON
        -DOPENCV_IPP_ENABLE_ALL=ON
        -DIPP_IW_DISABLE_SEH=ON
        # Parallel processing
        -DBUILD_TBB=OFF
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
        -DTIFF_LIBRARIES="$FFBUILD_PREFIX/lib/libtiff.a"
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
    # -D_WIN32_WINNT=0x0600
    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="-ljbig $LIBS $ADDITIONAL_LIBS" \
    cmake -G Ninja "${myconf[@]}" .. || {
        log_error "CMake failed, restoring TIFF..."
        [ -d "$TIFF_HIDE_DIR" ] && mv "$TIFF_HIDE_DIR"/* "$TIFF_CMAKE_DIR/"
        return 1
    }

    # ПАТЧ IPP IW
    local IPP_IW_FILE="3rdparty/ippicv/ippicv_win/iw/src/iw_own.c"
    if [ -f "$IPP_IW_FILE" ]; then
        log_info "Surgically removing SEH from IPP IW..."
        # Заменяем __try на простой блок
        sed -i 's/__try/if(1)/g' "$IPP_IW_FILE"
        # Заменяем __except(...) на else if(0)
        sed -i 's/__except(EXCEPTION_EXECUTE_HANDLER)/else if(0)/g' "$IPP_IW_FILE"
        sed -i 's/__except(1)/else if(0)/g' "$IPP_IW_FILE"
    else
        log_warn "IPP IW file not found at $IPP_IW_FILE, skipping patch."
    fi

    if ! grep -qiE "OPENVINO:.*(YES|ON|TRUE)" CMakeCache.txt && ! grep -qi "HAVE_OPENVINO:INTERNAL=ON" CMakeCache.txt; then
        log_error "OpenVINO was not detected in CMakeCache.txt!"
        # Выведем для отладки, что там на самом деле
        grep -i "OPENVINO" CMakeCache.txt
        return 1
    fi

    ninja $NINJA_V || {
        log_error "Build failed, restoring TIFF..."
        [ -d "$TIFF_HIDE_DIR" ] && mv "$TIFF_HIDE_DIR"/* "$TIFF_CMAKE_DIR/"
        return 1
    }

    DESTDIR="$FFBUILD_DESTDIR" ninja install

    if [ -d "$TIFF_HIDE_DIR" ]; then
        log_info "Restoring TIFF CMake files..."
        mv "$TIFF_HIDE_DIR"/* "$TIFF_CMAKE_DIR/"
        rm -rf "$TIFF_HIDE_DIR"
    fi

    local DEST_LIB="${INSTALL_ROOT}/lib"
    local PC_FILE="$PC_DIR/opencv4.pc"

    log_info "Moving OpenCV 3rdparty libs to main lib directory..."
    find 3rdparty -name "*.a" -exec mv {} "${DEST_LIB}/" \;

    # исправление имен liblib -> lib
    pushd "${DEST_LIB}"
    for f in liblib*.a; do
        if [ -f "$f" ]; then
            newname=$(echo "$f" | sed 's/liblib/lib/')
            log_info "Renaming $f to $newname"
            if [ -f "$newname" ]; then
                rm "$f"
            else
                mv "$f" "$newname"
            fi
        fi
    done
    popd

    # removing duplicate libraries
    if [ -f "${FFBUILD_PREFIX}/lib/libpng.a" ]; then
        rm -f "${DEST_LIB}/libpng.a"
    fi
    if [ -f "${FFBUILD_PREFIX}/lib/libprotobuf.a" ]; then
        rm -f "${DEST_LIB}/libprotobuf.a"
    fi

    if [ -f "$PC_FILE" ]; then
        log_info "Fixing includedir path in opencv4.pc..."
        sed -i "s|includedir=\${prefix}/include/opencv4|includedir=\${prefix}/include|g" "$PC_FILE"
        log_info "Cleaning up OpenCV pkg-config file..."
        # Вытаскиваем версию для регулярки (динамически)
        local OPENCV_VER_SUFFIX=$(find "${DEST_LIB}" -name "libopencv_core*.a" | grep -oE "[0-9]+.a$" | sed 's/.a//')
        # переносим все модули opencv из Libs.private в основные Libs
        local ACTUAL_LIBS=$(find "${DEST_LIB}" -name "libopencv_*.a" -printf "%f\n" | sed 's/^lib//;s/\.a$//' | xargs -I{} echo -l{} | tr '\n' ' ')
        # Удаляем путь к 3rdparty, так как мы перенесли либы в общий корень
        sed -i 's|-L${exec_prefix}/lib/opencv4/3rdparty||g' "$PC_FILE"
        # Формируем чистую строку Libs
        local OLD_PRIVATES=$(grep "Libs.private:" "$PC_FILE" | cut -d':' -f2-)
        # Убираем любые упоминания -lopencv_* из текущего файла, чтобы избежать дублей
        # Чистим зависимости: liblib -> lib, абсолютные пути, мусор
        local CLEAN_PRIVATES=$(echo "$OLD_PRIVATES" | sed -E 's/-llib/-l/g; s|-L/build/[^ ]*||g; -L/opt/ffbuild/lib[^ ]*||g; s/-lRunTmChk.a//g; s/-lntdll.a//g; s/-lopencv_[^ ]*//g')
        # Записываем в файл
        sed -i "s|^Libs:.*|Libs: -L\${libdir} ${ACTUAL_LIBS}|" "$PC_FILE"
        sed -i "s|^Libs.private:.*|Libs.private: ${CLEAN_PRIVATES}|" "$PC_FILE"
        # Добавляем необходимые либы
        if [[ "${myconf[@]}" =~ "-DWITH_OPENVINO=ON" ]]; then
            sed -i '/^Libs.private:/ s/$/ -lopenvino/' "$PC_FILE"
        fi
        sed -i "s/Requires.private:.*/Requires.private: /" "$PC_FILE"
        # Удаляем лишние пробелы
        sed -i 's/[[:space:]]\+/ /g' "$PC_FILE"
    fi
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
