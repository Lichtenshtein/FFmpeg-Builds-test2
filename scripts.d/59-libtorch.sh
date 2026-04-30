#!/bin/bash

SCRIPT_REPO="https://download.pytorch.org/libtorch/cpu/libtorch-win-shared-with-deps-1.9.1%2Bcpu.zip"

export SKIP_POST_PATCH=1

ffbuild_enabled() {
    return 0
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

    # Очищаем Windows-макросы, которые форсируют импорт
    : > include/torch/csrc/WindowsTorchApiMacro.h

    # Принудительно подключаем определение стека в начало IR (Interm. Representation)
    sed -i '1i #include <torch/csrc/jit/api/module.h>\n#include <torch/csrc/jit/serialization/callstack_at_node_serialization.h>' include/torch/csrc/jit/ir.h
    # Также патчим scope.h, чтобы он гарантированно имел все определения
    find include/torch/csrc/jit/ -name "ir.h" -exec sed -i '1i #include <torch/csrc/jit/frontend/source_range.h>' {} +

    # Добавляем необходимые инклуды для GCC 13+
    find include/ -name "*.h" -exec sed -i '1i #include <cstdint>\n#include <string>\n#include <stdexcept>' {} +

    mkdir -p "$INSTALL_ROOT"/{include,lib,bin}

    # Копируем заголовочные файлы
    cp -r include/* "$INSTALL_ROOT/include/"

    # MinGW ищет -ltorch как libtorch.a или libtorch.dll.a. 
    # Мы копируем .lib файлы как .a, чтобы линковщик их подхватил.
    for libfile in lib/*.lib; do
        local name=$(basename "$libfile" .lib)
        cp -v "$libfile" "$INSTALL_ROOT/lib/lib${name}.a"
    done

    cp -v lib/*.dll "$INSTALL_ROOT/bin/" 2>/dev/null || true

    ln -sf libtorch.a "$INSTALL_ROOT/lib/libtorch_cpu.a"

    # Исправляем имена protobuf (удаляем двойное 'liblib')
    if [ -f "$INSTALL_ROOT/lib/liblibprotobuf.a" ]; then
        mv "$INSTALL_ROOT/lib/liblibprotobuf.a" "$INSTALL_ROOT/lib/libprotobuf.a"
        mv "$INSTALL_ROOT/lib/liblibprotobuf-lite.a" "$INSTALL_ROOT/lib/libprotobuf-lite.a"
        mv "$INSTALL_ROOT/lib/liblibprotoc.a" "$INSTALL_ROOT/lib/libprotoc.a"
    fi

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
Cflags: -I\${includedir} -I\${includedir}/torch/csrc/api/include -D_GLIBCXX_USE_CXX11_ABI=1 -DNOMINMAX
EOF
}

ffbuild_cxxflags() {
    echo "-fpermissive -I$FFBUILD_PREFIX/include/torch/csrc/api/include -I$FFBUILD_PREFIX/include/torch/csrc/jit -D_GLIBCXX_USE_CXX11_ABI=1 -DNOMINMAX -DNDEBUG -D\"is_xpu()=is_cpu()\" -D\"hasXPU()=false\""
}

ffbuild_configure() {
    echo --enable-libtorch
}

ffbuild_unconfigure() {
    echo --disable-libtorch
}
