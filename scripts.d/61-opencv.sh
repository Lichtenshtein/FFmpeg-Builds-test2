#!/bin/bash

SCRIPT_REPO="https://github.com/opencv/opencv.git"
SCRIPT_COMMIT="30fffe2fa080b83b3cffecce05225475dbbdf012"

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
        # -DENABLE_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
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
        # -DWITH_ZLIB_NG=ON
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
        # -DCMAKE_DISABLE_FIND_PACKAGE_ZLIB=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_TIFF=ON
        # -DCMAKE_DISABLE_FIND_PACKAGE_JPEG=ON
        -DZLIB_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DZLIB_LIBRARY="$FFBUILD_PREFIX/lib/libz.a"
        -DZLIB_LIBRARIES="$FFBUILD_PREFIX/lib/libz.a"
        -DOPENJPEG_INCLUDE_DIR="$FFBUILD_PREFIX/include/openjpeg-2.5"
        -DOPENJPEG_LIBRARY="$FFBUILD_PREFIX/lib/libopenjp2.a"
        -DTIFF_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DTIFF_LIBRARY="$FFBUILD_PREFIX/lib/libtiff.a"
        -DTIFF_LIBRARIES="$FFBUILD_PREFIX/lib/libtiff.a"
        -DJPEG_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DJPEG_LIBRARY="$FFBUILD_PREFIX/lib/libjpeg.a"
        # Включаем интеграцию с OpenVINO (Inference Engine)
        -DWITH_OPENVINO=$([ "${BUILD_VINO}" == "1" ] && echo ON || echo OFF)
        -DOPENVINO_STATIC_COMPILATION=$([ "${BUILD_VINO}" == "1" ] && echo ON || echo OFF)
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

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-D__TBB_DYNAMIC_LOAD_ENABLED=0 -DOPENVINO_STATIC_LIBRARY"

    # -D_WIN32_WINNT=0x0600
    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="-ljbig $LIBS $ADDITIONAL_LIBS" \
    cmake -G Ninja "${myconf[@]}" .. || {
        log_error "CMake failed, restoring TIFF..."
        [ -d "$TIFF_HIDE_DIR" ] && mv "$TIFF_HIDE_DIR"/* "$TIFF_CMAKE_DIR/"
        return 1
    }

    mkdir -p "$INSTALL_ROOT"/{include,bin,lib/pkgconfig}

    local IPP_PATH="3rdparty/ippicv/ippicv_win/icv"
    if [ -f "$IPP_PATH/lib/intel64/ippicvmt.lib" ]; then
        log_info "Found IPP ICV (.lib), converting for MinGW..."
        cp "$IPP_PATH/lib/intel64/ippicvmt.lib" "$IPP_PATH/lib/intel64/libippicv.a"
        mv "$IPP_PATH/lib/intel64/ippicvmt.lib" "${INSTALL_ROOT}/lib/libippicv.a"
        log_info "Copying IPP ICV headers to include directory..."
        cp "$IPP_PATH/include"/*.h "${INSTALL_ROOT}/include/"
    else
        log_warn "IPP ICV files not found at $IPP_PATH"
    fi

    # ПАТЧ IPP IW
    local IPP_IW_FILE="3rdparty/ippicv/ippicv_win/iw/src/iw_own.cpp"
    if [ -f "$IPP_IW_FILE" ]; then
        log_info "Surgically removing SEH from IPP IW ($IPP_IW_FILE)..."

        # Force the file to use standard C++ try/catch instead of MSVC __try
        # We do this by undefining ICV_BASE or just nuking the macro definitions
        sed -i 's/#define OWN_TRY   __try/#define OWN_TRY   try/g' "$IPP_IW_FILE"
        sed -i 's/#define OWN_CATCH __except (EXCEPTION_EXECUTE_HANDLER)/#define OWN_CATCH catch (...)/g' "$IPP_IW_FILE"

        # Safety fallback for any direct usages
        sed -i 's/__try/try/g' "$IPP_IW_FILE"
        sed -i 's/__except(EXCEPTION_EXECUTE_HANDLER)/catch(...)/g' "$IPP_IW_FILE"
        sed -i 's/__except(1)/catch(...)/g' "$IPP_IW_FILE"
    else
        log_warn "IPP IW file not found at $IPP_IW_FILE, skipping patch."
    fi

    if [[ "${BUILD_VINO}" == "1" ]]; then
        if ! grep -qiE "OPENVINO:.*(YES|ON|TRUE)" CMakeCache.txt && ! grep -qi "HAVE_OPENVINO:INTERNAL=ON" CMakeCache.txt; then
            log_error "OpenVINO was not detected in CMakeCache.txt!"
            # Выведем для отладки, что там на самом деле
            grep -i "OPENVINO" CMakeCache.txt
            return 1
        fi
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

    local SRC_3RDPARTY="${INSTALL_ROOT}/lib/opencv4/3rdparty"
    local DEST_LIB="${INSTALL_ROOT}/lib"
    local PC_FILE="$PC_DIR/opencv4.pc"

    if [ -d "$SRC_3RDPARTY" ]; then
        log_info "Moving OpenCV 3rdparty libs to main lib directory..."
        if [[ "${PREFER_SHARED}" == "1" ]]; then
            mv "$SRC_3RDPARTY"/*.dll "$DEST_LIB/" 2>/dev/null || true
        else
            mv "$SRC_3RDPARTY"/*.a "$DEST_LIB/" 2>/dev/null || true
            log_info "Searching for IPP ICV library..."
            find . -name "libippicv*.a" -exec cp {} "${DEST_LIB}/" \; || true
        fi
        rm -rf "${INSTALL_ROOT}/lib/opencv4"
    fi

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # исправление имен liblib -> lib
        pushd "${DEST_LIB}"
        for f in liblib*.a; do
            if [ -f "$f" ]; then
                newname=$(echo "$f" | sed 's/^liblib/lib/')
                log_info "Renaming $f to $newname"
                mv -f "$f" "$newname"
            fi
        done
        # Create libopencv_core.a from libopencv_core4140.a
        for lib in libopencv_*.a; do
            unversioned=$(echo "$lib" | sed -E 's/[0-9]+\.a$/.a/')
            if [ "$lib" != "$unversioned" ]; then
                log_info "Creating symlink $unversioned -> $lib"
                ln -sf "$lib" "$unversioned"
            fi
        done
        popd
        # Удаляем системные дубликаты, если они пришли из OpenCV 3rdparty
        for duplicate in libpng.a libprotobuf.a libz.a libjpeg.a libtiff.a; do
            if [ -f "${FFBUILD_PREFIX}/lib/${duplicate}" ] && [ -f "${DEST_LIB}/${duplicate}" ]; then
                 log_info "Removing duplicate ${duplicate} from OpenCV build"
                 rm -f "${DEST_LIB}/${duplicate}"
            fi
        done
    fi

    # Исправляем пути к 3rdparty либам в .cmake конфигах OpenCV
    # Заменяем относительный путь 'lib/opencv4/3rdparty' на просто 'lib'
    # исправляем названия библиотек с liblib -> lib
    log_info "Fixing paths and names in .cmake files..."
    find "${DEST_LIB}/cmake/opencv4" -name "*.cmake" -exec sed -i \
        -e 's|lib/opencv4/3rdparty/|lib/|g' \
        -e 's|liblib|lib|g' {} +

    # Создаем симлинк, чтобы заголовочные файлы находились по стандартному пути
    # ln -sfn opencv4/opencv2 "${INSTALL_ROOT}/include/opencv2"

    log_info "Creating MSVC security cookie stubs for IPP..."
    # Создаем исходник заглушки
    cat <<EOF > msvc_stub.c
#include <stdint.h>
#include <stdlib.h>

uintptr_t __security_cookie = 0xBB40E64E;
void __fastcall __security_check_cookie(uintptr_t _StackCookie) {
    if (_StackCookie != __security_cookie) abort();
}

int _fltused = 0;

void __chkstk(void) {
    extern void ___chkstk_ms(void);
    ___chkstk_ms();
}

long long _time64(long long* t) { 
    if (t) *t = 0;
    return 0; 
} 
EOF

    # Компилируем в объектный файл и упаковываем в статическую либу
    ${FFBUILD_CROSS_PREFIX}gcc $CFLAGS -c msvc_stub.c -o msvc_stub.o
    ${FFBUILD_CROSS_PREFIX}ar rcs "${DEST_LIB}/libmsvc_stub.a" msvc_stub.o

    if [ -f "$PC_FILE" ]; then
        log_info "Fixing includedir path in opencv4.pc..."
        sed -i "s|^includedir=.*|includedir=\${prefix}/include/opencv4|g" "$PC_FILE"
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
        local CLEAN_PRIVATES=$(echo "$OLD_PRIVATES" | sed -E 's/-llib/-l/g; s|-L/[^ ]*||g; s/-lRunTmChk.a//g; s/-lntdll.a//g; s/-lopencv_[^ ]*//g')
        # Записываем в файл
        sed -i "s|^Libs:.*|Libs: -L\${libdir} ${ACTUAL_LIBS}|" "$PC_FILE"
        sed -i "s|^Libs.private:.*|Libs.private: ${CLEAN_PRIVATES}|" "$PC_FILE"
        # Добавляем необходимые либы
        if [[ "${myconf[@]}" =~ "-DWITH_OPENVINO=ON" ]]; then
            sed -i '/^Libs.private:/ s/$/ -lopenvino/' "$PC_FILE"
        fi
        if [[ "${myconf[@]}" =~ "-DWITH_TBB=ON" ]]; then
            sed -i '/^Libs.private:/ s/$/ -ltbb12/' "$PC_FILE"
        fi
        if [[ "${myconf[@]}" =~ "-DWITH_IPP=ON" ]]; then
            sed -i 's|^Libs.private: |Libs.private: -lmsvc_stub -lippicv |' "$PC_FILE"
            sed -i 's/-lippicvmt//g; s/-lippicv -lippicv/-lippicv/g' "$PC_FILE"
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
