#!/bin/bash

SCRIPT_REPO="https://github.com/openvinotoolkit/openvino.git"
SCRIPT_COMMIT="61d1ca8c471ff930477c8f27926688ba112642a7"

# export SKIP_POST_PATCH=1

ffbuild_depends() {
    echo tbbmalloc
    echo opencl
    echo opencv
}

ffbuild_enabled() {
    [[ "$BUILD_VINO" == "1" ]] && return 0
    return 1
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    log_info "Disabling samples and snippets subdirectories precisely..."
    sed -i '/ov_mark_target_as_cc(${TARGET_NAME})/a return()' docs/snippets/CMakeLists.txt
    sed -i 's/^[[:space:]]*add_subdirectory(samples)/# add_subdirectory(samples)/g' CMakeLists.txt

    log_info "Fixing case-sensitive Shlwapi library names for Linux host..."
    sed -i 's/\bShlwapi\b/shlwapi/g' src/common/util/CMakeLists.txt

    export TBBROOT="$FFBUILD_PREFIX"

    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        # Настройка многопоточности под статический TBB
        -DTHREADING=TBB
        -DENABLE_SYSTEM_TBB=ON
        -DENABLE_TBBBIND_2_5=OFF # Выключаем гибридный шедулер
        -DTBB_DIR="${FFBUILD_PREFIX}/lib/cmake/TBB"
        # Отключаем ВСЕ фронтенды
        -DENABLE_OV_IR_FRONTEND=ON # Оставляем только базовый парсер IR XML/BIN
        -DENABLE_OV_ONNX_FRONTEND=OFF
        -DENABLE_OV_PADDLE_FRONTEND=OFF
        -DENABLE_OV_TF_FRONTEND=OFF
        -DENABLE_OV_TF_LITE_FRONTEND=OFF
        -DENABLE_OV_PYTORCH_FRONTEND=OFF
        -DENABLE_OV_JAX_FRONTEND=OFF
        # Отключаем плагины и тяжелые зависимости
        -DENABLE_INTEL_CPU=ON  # Оставляем только CPU плагин для Xeon
        -DENABLE_INTEL_GPU=OFF # GPU требует OpenCL/Vulkan заголовков
        -DENABLE_INTEL_NPU=OFF
        -DENABLE_HETERO=OFF
        -DENABLE_MULTI=OFF
        -DENABLE_AUTO=OFF
        -DENABLE_AUTO_BATCH=OFF
        -DENABLE_PROXY=OFF
        -DENABLE_TEMPLATE=OFF
        -DENABLE_OPENCV=OFF # Не связываем с OpenCV samples
        -DENABLE_SYSTEM_PUGIXML=OFF # ON
        -DENABLE_SYSTEM_PROTOBUF=OFF # OFF; for ONNX, PaddlePaddle, TensorFlow
        -DENABLE_SYSTEM_FLATBUFFERS=OFF # ON; for Tensorflow Lite frontend
        -DENABLE_SYSTEM_OPENCL=ON # ON; use OpenCL installed on the system
        # Оптимизации размера и сборки
        -DENABLE_JS=OFF
        -DENABLE_SAMPLES=OFF
        -DENABLE_TESTS=OFF
        -DENABLE_FUNCTIONAL_TESTS=OFF
        -DENABLE_SNIPPETS_LIBXSMM_TPP=OFF
        -DENABLE_PYTHON=OFF
        -DENABLE_WHEEL=OFF
        -DENABLE_CLANG_FORMAT=OFF
        -DENABLE_PROFILING_ITT=OFF
        # Включаем аппаратные инструкции
        -DENABLE_SSE42=ON
        -DENABLE_AVX2=ON
        -DENABLE_AVX512F=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF)
        -DENABLE_FASTER_BUILD=OFF # OFF; precompiled headers and unity build
        # кросс-компиляция
        -DENABLE_API_VALIDATOR=OFF # поиск Windows SDK / apivalidator.exe
        -DENABLE_INTEL_ITT=OFF # убирает привязку к Windows ITT/VTune API
        -DENABLE_CPPLINT=OFF # не ищет python-линтеры
        -DENABLE_NCC_STYLE=OFF # Отключает проверку стилей OpenVINO
        # Дополнительно
        -DCMAKE_CXX_STANDARD=20
        -DCMAKE_CXX_STANDARD_REQUIRED=ON
        -DCMAKE_COMPILE_WARNING_AS_ERROR=OFF
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-D__TBB_DYNAMIC_LOAD_ENABLED=0"

    [[ "${USE_LTO}" == "1" ]] && LTO_flags="-Wno-odr -fno-lto-odr-type-merging"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $LTO_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $LTO_flags $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO} $LTO_flags -Wl,--allow-multiple-definition" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    log_info "Moving and restructuring OpenVINO layout..."

    # нужно превратить include/c/ в include/openvino/c/
    mkdir -p "${INSTALL_ROOT}/include/openvino"

    # Переносим внутренние папки (c, core, frontend, op, opsets, pass, runtime) в папку openvino
    find "${INSTALL_ROOT}/runtime/include/" -mindepth 1 -maxdepth 1 | while read -r src_dir; do
        mv "$src_dir" "${INSTALL_ROOT}/include/openvino/"
    done

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # Собираем все статические .a библиотеки, разбросанные по папкам, в единый lib
        mkdir -p "${INSTALL_ROOT}/lib"
        find "${INSTALL_ROOT}/runtime/lib" -name "*.a" -exec mv {} "${INSTALL_ROOT}/lib/" \;

        # Чистим LTO-секции из статических библиотек, чтобы сбросить вес с 1.7Гб до ~100Мб
        log_info "Stripping heavy GCC LTO sections from .a files to optimize size..."
        find "${INSTALL_ROOT}" -name "*.a" | while read -r LIB_FILE; do
            "${FFBUILD_CROSS_PREFIX}objcopy" --remove-section=.gnu.lto_* "$LIB_FILE" || true
        done
    fi

    # Переносим файлы CMake в правильную стандартную директорию
    mkdir -p "${INSTALL_ROOT}/lib/cmake"
    mv "${INSTALL_ROOT}/runtime/cmake" "${INSTALL_ROOT}/lib/cmake/"
    rm -rf "${INSTALL_ROOT}/runtime"

    # Патчим относительные пути внутри перенесенных CMake файлов
    log_info "Patching paths inside internal OpenVINO CMake files..."
    find "${INSTALL_ROOT}/lib/cmake" -name "*.cmake" | while read -r CMAKE_FILE; do
        # Меняем /runtime/include на /include/openvino
        sed -i 's|/runtime/include|/include/openvino|g' "$CMAKE_FILE"
        # Меняем /runtime/lib на /lib
        sed -i 's|/runtime/lib|/lib|g' "$CMAKE_FILE"
        # Исправляем относительные пути расчета IMPORT_PREFIX, так как файлы переехали глубез в lib/cmake/OpenVINO
        sed -i 's|get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)|get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)\n  get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)|g' "$CMAKE_FILE"
    done

    log_debug "Inspecting generated OpenVINO CMake configuration files:"
    if [ -f "${INSTALL_ROOT}/lib/cmake/OpenVINOConfig.cmake" ]; then
        log_info "--- Content of OpenVINOConfig.cmake ---"
        cat "${INSTALL_ROOT}/lib/cmake/OpenVINOConfig.cmake"
    fi
    if [ -f "${INSTALL_ROOT}/lib/cmake/OpenVINOTargets.cmake" ]; then
        log_info "--- Content of OpenVINOTargets.cmake ---"
        cat "${INSTALL_ROOT}/lib/cmake/OpenVINOTargets.cmake"
    fi

    log_info "Generating openvino.pc file for pkg-config..."
    mkdir -p "${PC_DIR}"
    cat <<EOF > "${PC_DIR}/openvino.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: OpenVINO
Description: Intel OpenVINO Runtime Static Library for FFmpeg
Version: 2026.3.0
Cflags: -I\${includedir} -I\${includedir}/openvino
Libs: -L\${libdir} -lopenvino -lopenvino_c -lopenvino_intel_cpu_plugin -lopenvino_ir_frontend -lopenvino_onednn_cpu -lopenvino_shape_inference -lopenvino_common_translators -lopenvino_reference -lopenvino_itt -lopenvino_util -lopenvino_xml_util -lopenvino_snippets -lpugixml
Libs.private: -ltbb -lshlwapi -lsetupapi -lws2_32 -lbcrypt
EOF

    # Фикс для старых проверок FFmpeg (Inference Engine C-API Wrapper)
    # Перенаправляем старый вызов c_api/ie_c_api.h на современный openvino/c/openvino.h
    mkdir -p "$INSTALL_ROOT/include/c_api"
    cat <<EOF > "$INSTALL_ROOT/include/c_api/ie_c_api.h"
#ifndef COMPAT_IE_C_API_H
#define COMPAT_IE_C_API_H
#include <openvino/c/openvino.h>

static __attribute__((unused)) const char* ie_c_api_version(void) { 
    return "2025.4.1"; 
}
#endif
EOF

    # Дублируем заголовок для persistent storage
    mkdir -p "$FFBUILD_PREFIX/include/c_api"
    cp "$INSTALL_ROOT/include/c_api/ie_c_api.h" "$FFBUILD_PREFIX/include/c_api/ie_c_api.h"

    # Создаем пустую библиотеку-пустышку libinference_engine_c_api.a, 
    # чтобы удовлетворить жесткий фоллбэк линковщика FFmpeg (-linference_engine_c_api)
    log_info "Creating inference_engine_c_api fallback stub for FFmpeg configure..."
    rm -f "$INSTALL_ROOT/lib/libinference_engine_c_api.a"
    ar rcs "$INSTALL_ROOT/lib/libinference_engine_c_api.a"

    # Дублируем библиотеку-пустышку для постоянного префикса
    mkdir -p "$FFBUILD_PREFIX/lib"
    cp "$INSTALL_ROOT/lib/libinference_engine_c_api.a" "$FFBUILD_PREFIX/lib/libinference_engine_c_api.a"
}

ffbuild_configure() {
    echo --enable-libopenvino
}

ffbuild_unconfigure() {
    echo --disable-libopenvino
}
