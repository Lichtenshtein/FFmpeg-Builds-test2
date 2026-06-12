#!/bin/bash
export USE_VERS_FINDER=1
SCRIPT_REPO="https://github.com/openvinotoolkit/openvino.git"
SCRIPT_COMMIT="7b32f06bcaa24fc319a253251395c2061bbbdc0a"

# export SKIP_POST_PC_PATCH=1

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

    log_info "Fixing MSVC -EP flag to GCC -E -P for Intel GPU CM codegen..."
    find src/plugins/intel_gpu/src/graph/impls/ -name "CMakeLists.txt" -type f -exec sed -i 's/-EP/-E\ -P/g' {} +

    log_info "Neutralizing forced -Werror in Intel GPU root CMakeLists..."
    sed -i 's/ov_add_compiler_flags(-Werror)/# ov_add_compiler_flags(-Werror)/g' src/plugins/intel_gpu/CMakeLists.txt

    log_info "Completely neutralizing template_extension build via early return..."
    echo "return()" | cat - src/core/template_extension/CMakeLists.txt > temp && mv temp src/core/template_extension/CMakeLists.txt

    export TBBROOT="$FFBUILD_PREFIX"

    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        # Настройка многопоточности под статический TBB
        -DTHREADING=TBB # OMP for OpenMP
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
        -DENABLE_INTEL_CPU=ON # Оставляем только CPU плагин для Xeon
        -DENABLE_INTEL_GPU=OFF # GPU требует OpenCL/Vulkan заголовков; it's for integrated (iGPU) and discrete (dGPU) Intel graphics cards; build works
        -DENABLE_INTEL_NPU=OFF
        -DENABLE_HETERO=OFF
        -DENABLE_MULTI=OFF
        -DENABLE_AUTO=OFF
        -DENABLE_AUTO_BATCH=OFF
        -DENABLE_PROXY=OFF
        -DENABLE_TEMPLATE=OFF
        -DENABLE_OPENCV=OFF # OpenCV samples; provides -lprotobuf, but goes after
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
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-D__TBB_DYNAMIC_LOAD_ENABLED=0" && self_static_flags="-DOPENVINO_STATIC_LIBRARY"

    [[ "${USE_LTO}" == "1" ]] && LTO_FLAGS="-Wno-odr -fno-lto-odr-type-merging"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $LTO_FLAGS $self_static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $LTO_FLAGS $static_flags $self_static_flags -DWINAPI_PARTITION_SYSTEM=1" \
    LDFLAGS="$LDFLAGS ${USELTO} $LTO_FLAGS -Wl,--allow-multiple-definition" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    log_info "Moving and restructuring OpenVINO layout..."

    # нужно превратить include/c/ в include/openvino/c/
    mkdir -p "${INSTALL_ROOT}/include/openvino"

    # Переносим внутренние папки (c, core, frontend, op, opsets, pass, runtime) в папку openvino
    find "${INSTALL_ROOT}/runtime/include/" -mindepth 1 -maxdepth 1 | while read -r src_dir; do
        mv "$src_dir" "${INSTALL_ROOT}/include/"
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
    mv "${INSTALL_ROOT}/runtime/cmake" "${INSTALL_ROOT}/lib/"
    rm -rf "${INSTALL_ROOT}/runtime"

    # Патчим относительные пути внутри перенесенных CMake файлов
    log_info "Performing massive absolute path patching inside OpenVINO CMake files..."
    find "${INSTALL_ROOT}/lib/cmake" -name "*.cmake" -type f | while read -r CMAKE_FILE; do
        # Намертво фиксируем PACKAGE_PREFIX_DIR на наш абсолютный корень кросс-компиляции
        sed -i 's|get_filename_component(PACKAGE_PREFIX_DIR "${CMAKE_CURRENT_LIST_DIR}/../../" ABSOLUTE)|set(PACKAGE_PREFIX_DIR "/opt/ffbuild")|g' "$CMAKE_FILE"

        # Ссылки на проверки путей, если ACL (ARM Compute Library) или onednn_gpu_lib_root вызываются
        sed -i 's|"${PACKAGE_PREFIX_DIR}/runtime/lib/intel64/Release"|"/opt/ffbuild/lib"|g' "$CMAKE_FILE"

        # Сначала убираем вычисление относительного префикса в Targets, чтобы он не перезаписывал пути
        sed -i 's|get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)|# Использован абсолютный путь|g' "$CMAKE_FILE"

        # Заменяем все хитрые относительные конструкции Intel на жесткий абсолютный путь
        sed -i 's|"\${_IMPORT_PREFIX}/runtime/lib/intel64/Release/|"/opt/ffbuild/lib/|g' "$CMAKE_FILE"
        sed -i 's|"\${_IMPORT_PREFIX}/runtime/lib/intel64/Debug/|"/opt/ffbuild/lib/|g' "$CMAKE_FILE"
        sed -i 's|"\${_IMPORT_PREFIX}/runtime/lib/|"/opt/ffbuild/lib/|g' "$CMAKE_FILE"
        sed -i 's|"\${_IMPORT_PREFIX}/runtime/include|"/opt/ffbuild/include/openvino|g' "$CMAKE_FILE"
        sed -i 's|"\${_IMPORT_PREFIX}/runtime/bin/|"/opt/ffbuild/bin/|g' "$CMAKE_FILE"

        # Исправляем расширения и структуры под GCC/MinGW статику
        sed -i 's|\.lib|.a|g' "$CMAKE_FILE"
        sed -i 's|liblib|lib|g' "$CMAKE_FILE"
        sed -i 's|/intel64/Release/||g' "$CMAKE_FILE"
        sed -i 's|/intel64/Debug/||g' "$CMAKE_FILE"
        # Синхронизируем дебажные суффиксы, если они где-то проскочили
        sed -i -e 's/d\.a/.a/g' -e 's/fronten\.a/frontend.a/g' "$CMAKE_FILE"
        sed -i -e 's/Debug/Release/g' -e 's/DEBUG/RELEASE/g' "$CMAKE_FILE"
    done

    # log_debug "Inspecting generated OpenVINO CMake configuration files:"
    if [ -f "${INSTALL_ROOT}/lib/cmake/OpenVINOConfig.cmake" ]; then
        log_info "--- Content of OpenVINOConfig.cmake ---"
        while IFS= read -r line; do
            log_debug "  $line"
        done < "${INSTALL_ROOT}/lib/cmake/OpenVINOConfig.cmake"
    else
        log_error "OpenVINOConfig.cmake NOT FOUND in ${INSTALL_ROOT}/lib/cmake/"
    fi
    # if [ -f "${INSTALL_ROOT}/lib/cmake/OpenVINOTargets-release.cmake" ]; then
        # log_info "--- Content of OpenVINOTargets-release.cmake ---"
        # cat "${INSTALL_ROOT}/lib/cmake/OpenVINOTargets-release.cmake" >&2
    # fi

    # Фикс для старых проверок FFmpeg (Inference Engine C-API Wrapper)
    # Перенаправляем старый вызов c_api/ie_c_api.h на современный openvino/c/openvino.h
    if [[ ! -f "$INSTALL_ROOT/include/c_api/ie_c_api.h" ]]; then
    mkdir -p "$INSTALL_ROOT/include/c_api"
    cat <<EOF > "$INSTALL_ROOT/include/c_api/ie_c_api.h"
#ifndef COMPAT_IE_C_API_H
#define COMPAT_IE_C_API_H
#include <openvino/c/openvino.h>

static __attribute__((unused)) const char* ie_c_api_version(void) { 
    return "${VER_FULL}"; 
}
#endif
EOF
    fi

    # Создаем пустую библиотеку-пустышку libinference_engine_c_api.a, 
    # чтобы удовлетворить жесткий фоллбэк линковщика FFmpeg (-linference_engine_c_api)
    log_info "Creating inference_engine_c_api fallback stub for FFmpeg configure..."
    rm -f "$INSTALL_ROOT/lib/libinference_engine_c_api.a"
    ar rcs "$INSTALL_ROOT/lib/libinference_engine_c_api.a"

    # собираем все либы
    log_info "Dynamically collecting installed OpenVINO libraries..."

    # Собираем главные интерфейсные либы, которые должны быть первыми в очереди линковки
    local CORE_LIBS=""
    for main_lib in libopenvino.a libopenvino_c.a; do
        if [ -f "${INSTALL_ROOT}/lib/${main_lib}" ]; then
            CORE_LIBS="${CORE_LIBS} -l${main_lib%.a}"
            CORE_LIBS="${CORE_LIBS#lib}" # убираем префикс lib для флага -l
        fi
    done
    # Исправляем строку (превращаем -llibopenvino в -lopenvino)
    CORE_LIBS=$(echo "$CORE_LIBS" | sed 's/-llib/-l/g')

    # Собираем все остальные внутренние компоненты OpenVINO, исключая уже добавленные и сторонние (tbb, pugixml)
    local COMPONENT_LIBS=$(find "${INSTALL_ROOT}/lib" -name "libopenvino_*.a" | sed "s|.*/lib\(.*\)\.a|-l\1|" | xargs)

    # Принудительно добавляем pugixml, если он собрался внутри OpenVINO
    local PUGI_LIB=""
    [ -f "${INSTALL_ROOT}/lib/libpugixml.a" ] && PUGI_LIB="-lpugixml"

    local INTER_LIB=""
    [ -f "${INSTALL_ROOT}/lib/libinference_engine_c_api.a" ] && INTER_LIB="-linference_engine_c_api"

    log_info "Generated Libs sequence: ${CORE_LIBS} ${INTER_LIB} ${COMPONENT_LIBS} ${PUGI_LIB}"

    log_info "Generating openvino.pc file for pkg-config..."
    mkdir -p "${PC_DIR}"
    cat <<EOF > "${PC_DIR}/openvino.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: OpenVINO
Description: Intel OpenVINO Runtime Static Library for FFmpeg
Version: ${VER_FULL}
Cflags: -I\${includedir} -I\${includedir}/openvino $static_flags $self_static_flags
Libs: -L\${libdir} ${CORE_LIBS} ${INTER_LIB} ${COMPONENT_LIBS} ${PUGI_LIB}
Libs.private: -ltbb -lshlwapi -lsetupapi -lws2_32 -lbcrypt
EOF
}

ffbuild_configure() {
    echo --enable-libopenvino
}

ffbuild_unconfigure() {
    echo --disable-libopenvino
}
