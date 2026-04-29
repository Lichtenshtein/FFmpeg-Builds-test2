#!/bin/bash

SCRIPT_REPO="https://download.pytorch.org/libtorch/cpu/libtorch-win-shared-with-deps-2.10.0%2Bcpu.zip"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    # echo "curl -sL \"$SCRIPT_REPO\" --output libtorch.zip && unzip -qq libtorch.zip && mv libtorch libtorch_src"
    echo "download_file \"$SCRIPT_REPO\" \"libtorch.zip\""
}

ffbuild_dockerbuild() {
    set -e

    # Распаковываем (unzip должен быть в base образе)
    unzip -qq libtorch.zip

    # Находим папку (имя может меняться в зависимости от билда)
    local LT_DIR=$(find . -maxdepth 1 -type d -name "libtorch*" | head -n 1)
    cd "$LT_DIR"

    # cd libtorch_src

    log_info "Applying final structural fix for LibTorch headers..."

    find include/ -type f \( -name "*.h" -o -name "*.hpp" \) -exec sed -i \
        -e 's/__declspec(dllimport)//g' \
        -e 's/__declspec(dllexport)//g' {} +

    local MACRO_H=$(find include/c10 -name "Macros.h" | head -n 1)
    if [[ -f "$MACRO_H" ]]; then
        cat <<EOF >> "$MACRO_H"
#ifndef LIBTORCH_STATIC_FIX
#define LIBTORCH_STATIC_FIX
#define TORCH_API
#define C10_API
#define C10_IMPORT
#define C10_EXPORT
#define AT_API
#define CAFFE2_API
#define C10_API_ENUM
#define TORCH_API_ENUM
#endif
EOF
    fi

    find include/torch/csrc/autograd/ -name "profiler_legacy.h" -exec sed -i '1i #include <cstdint>' {} +
    find include/ATen/ -name "record_function.h" -exec sed -i '1i #include <cstdint>' {} +

    # Принудительно выставляем импорт для всех API макросов
    find include/ -type f \( -name "*.h" -o -name "*.hpp" \) -exec sed -i \
        -e 's/define [A-Z0-9_]*_API .*/define \0 __declspec(dllimport)/g' \
        -e 's/define [A-Z0-9_]*_IMPORT .*/define \0 __declspec(dllimport)/g' {} +

    # Исправляем конкретно Macros.h и Export.h, чтобы они не переопределили это назад
    find include/ -name "Export.h" -exec sed -i 's/define [A-Z0-9_]*_API.*/#define \0 __declspec(dllimport)/g' {} +

    mkdir -p "$INSTALL_ROOT"/{include,lib,bin}

    # Копируем заголовочные файлы
    cp -r include/* "$INSTALL_ROOT/include/"

    # Копируем библиотеки и DLL
    # копируем как есть. Общая функция сама решит, 
    # сделать ли из .lib -> .a или сгенерировать импорт из .dll
    cp lib/*.dll "$INSTALL_ROOT/bin/" 2>/dev/null || true
    # cp lib/*.lib "$INSTALL_ROOT/lib/" 2>/dev/null || true

    # LibTorch требует много флагов, создаем .pc файл
    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/libtorch.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: LibTorch
Description: PyTorch C++ API
Version: 2.10.0
Libs: -L\${libdir} -ltorch -ltorch_cpu -lc10
Cflags: -I\${includedir} -I\${includedir}/torch/csrc/api/include -D_GLIBCXX_USE_CXX11_ABI=1 -DNOMINMAX -D_DLL
EOF
}

ffbuild_cxxflags() {
    echo "-I$FFBUILD_PREFIX/include/torch/csrc/api/include -D_GLIBCXX_USE_CXX11_ABI=1 -DNOMINMAX -DNDEBUG \
          -D_DLL -DCAFFE2_USE_MKL -DUSE_CUDA=0"
}

ffbuild_configure() {
    echo --enable-libtorch
}

ffbuild_unconfigure() {
    echo --disable-libtorch
}
