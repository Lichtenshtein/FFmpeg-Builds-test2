#!/bin/bash

SCRIPT_REPO="https://download.pytorch.org/libtorch/cpu/libtorch-win-shared-with-deps-1.9.1%2Bcpu.zip"

export SKIP_POST_PATCH=1

ffbuild_enabled() {
    return 1
}

ffbuild_dockerdl() {
    # echo "curl -sL \"$SCRIPT_REPO\" --output libtorch.zip && unzip -qq libtorch.zip && mv libtorch libtorch_src"
    echo "download_file \"$SCRIPT_REPO\" \"libtorch.zip\""
}

ffbuild_dockerbuild() {
    set -e

    unzip -qq libtorch.zip
    local LT_DIR=$(find . -maxdepth 1 -type d -name "libtorch*" | head -n 1)
    cd "$LT_DIR"

    find include/ -type f -name "*.h" -exec sed -i 's/__declspec(dllimport)//g' {} +
    find include/ -type f -name "*.h" -exec sed -i 's/__declspec(dllexport)//g' {} +

    # Находим основной файл макросов. В разных версиях это Macros.h или Export.h
    local MACRO_H=$(find include -name "Macros.h" | grep "c10" | head -n 1)
    if [ -n "$MACRO_H" ]; then
        # Очищаем и записываем пустые макросы в начало
        sed -i '1i #define C10_API\n#define TORCH_API\n#define AT_API\n#define CAFFE2_API\n#define C10_IMPORT\n#define C10_EXPORT' "$MACRO_H"
    fi

    # Нейтрализуем Windows-специфичный файл, который может переопределить TORCH_API обратно
    if [ -f "include/torch/csrc/WindowsTorchApiMacro.h" ]; then
        echo "#define TORCH_API" > include/torch/csrc/WindowsTorchApiMacro.h
    fi

    # ИСПРАВЛЕНИЕ InlinedCallStack (через инклуд в ir.h)
    local SCOPE_H=$(find include -name "scope.h" | grep "jit" | head -n 1)
    local IR_H=$(find include -name "ir.h" | grep "jit" | head -n 1)
    if [ -n "$IR_H" ] && [ -n "$SCOPE_H" ]; then
        local REL_SCOPE=$(echo "$SCOPE_H" | sed 's|include/||')
        sed -i "1i #include <$REL_SCOPE>" "$IR_H"
    fi

    # Базовые типы для GCC 15
    find include/ -name "*.h" -exec sed -i '1i #include <cstdint>\n#include <string>\n#include <stdexcept>' {} +

    mkdir -p "$INSTALL_ROOT"/{include,lib,bin}
    cp -r include/* "$INSTALL_ROOT/include/"

    # Копируем библиотеки
    for libfile in lib/*.lib; do
        local name=$(basename "$libfile" .lib)
        cp -v "$libfile" "$INSTALL_ROOT/lib/lib${name}.a"
    done

    cp -v lib/*.dll "$INSTALL_ROOT/bin/" 2>/dev/null || true

    # Если в этой версии нет torch_cpu.lib, создаем заглушку
    if [ ! -f "$INSTALL_ROOT/lib/libtorch_cpu.a" ]; then
        ln -sf libtorch.a "$INSTALL_ROOT/lib/libtorch_cpu.a"
    fi

    # Убираем liblib в именах protobuf
    find "$INSTALL_ROOT/lib/" -name "liblib*.a" -exec bash -c 'mv "$1" "${1/liblib/lib}"' -- {} \;

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/libtorch.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: LibTorch
Description: PyTorch C++ API (Shared)
Version: 2.10.0
Libs: -L\${libdir} -ltorch -ltorch_cpu -lc10
Libs.private: -lstdc++
Cflags: -I\${includedir} -I\${includedir}/torch/csrc/api/include -D_GLIBCXX_USE_CXX11_ABI=0 -DNOMINMAX
EOF
}

ffbuild_cxxflags() {
    echo "-Wno-deprecated-declarations -Wno-error=deprecated-declarations -fpermissive -I$FFBUILD_PREFIX/include/torch/csrc/api/include -I$FFBUILD_PREFIX/include/torch/csrc/jit -D_GLIBCXX_USE_CXX11_ABI=0 -DNOMINMAX -DNDEBUG"
}

ffbuild_configure() {
    echo --enable-libtorch
}

ffbuild_unconfigure() {
    echo --disable-libtorch
}
