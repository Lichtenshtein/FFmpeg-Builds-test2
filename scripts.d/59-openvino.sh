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
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    # Исключаем сборку папки демонстрационных сниппетов из документации
    if [ -f "docs/CMakeLists.txt" ]; then
        sed -i 's/\badd_subdirectory(snippets)\b/# add_subdirectory(snippets)/g' docs/CMakeLists.txt
    fi

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

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO} -Wl,--allow-multiple-definition" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # mkdir -p "$PC_DIR"
    # cat <<EOF > "$PC_DIR/openvino.pc"
# prefix=$FFBUILD_PREFIX
# libdir=\${prefix}/lib
# includedir=\${prefix}/include

# Name: OpenVINO
# Description: Intel OpenVINO Runtime (Static MinGW Broadwell Clean Build)
# Version: 2025.4.1
# Libs: -L\${libdir} -lopenvino -lopenvino_intel_cpu_plugin -lopenvino_ir_frontend -lopenvino_shape_inference -lopenvino_onednn_cpu -lopenvino_common_translators -lopenvino_reference -lopenvino_util -lpugixml
# Libs.private: -ltbb12 -lstdc++ -lshlwapi -lws2_32
# Cflags: -I\${includedir} -I\${includedir}/openvino
# EOF
}

ffbuild_configure() {
    echo --enable-libopenvino
}

ffbuild_unconfigure() {
    echo --disable-libopenvino
}
