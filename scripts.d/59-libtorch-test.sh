#!/bin/bash

SCRIPT_REPO="https://download.pytorch.org/libtorch/cpu/libtorch-win-shared-with-deps-2.10.0%2Bcpu.zip"

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

    # Распаковываем (unzip должен быть в base образе)
    unzip -qq libtorch.zip

    # Находим папку (имя может меняться в зависимости от билда)
    local LT_DIR=$(find . -maxdepth 1 -type d -name "libtorch*" | head -n 1)
    cd "$LT_DIR"

    # cd libtorch_src

    # Patch LibTorch headers to force static linking (fixes dllimport/dllexport conflicts)
    log_info "Patching LibTorch headers to force static linking..."

    # 1. Force TORCH_API and C10_API to be empty (no import/export)
    find include/ -type f \( -name "*.h" -o -name "*.hpp" \) -exec sed -i \
        -e 's/#define TORCH_API.*/#define TORCH_API/g' \
        -e 's/#define C10_API.*/#define C10_API/g' \
        -e 's/#define C10_IMPORT.*/#define C10_IMPORT/g' \
        -e 's/#define C10_EXPORT.*/#define C10_EXPORT/g' \
        -e 's/#define AT_API.*/#define AT_API/g' \
        -e 's/#define CAFFE2_API.*/#define CAFFE2_API/g' \
        {} +

    # 2. Remove explicit __declspec directives that conflict with empty macros
    find include/ -type f \( -name "*.h" -o -name "*.hpp" \) -exec sed -i \
        -e 's/__declspec(dllimport)//g' \
        -e 's/__declspec(dllexport)//g' \
        {} +

    # 3. Fix missing includes that break compilation on newer GCC
    find include/ATen/ -name "record_function.h" -exec sed -i '1i #include <cstdint>' {} +
    find include/torch/csrc/autograd/ -name "profiler_legacy.h" -exec sed -i '1i #include <cstdint>' {} +

    mkdir -p "$INSTALL_ROOT"/{include,lib,bin}

    # Копируем заголовочные файлы
    cp -r include/* "$INSTALL_ROOT/include/"

    # Копируем библиотеки и DLL
    # копируем как есть. Общая функция сама решит, 
    # сделать ли из .lib -> .a или сгенерировать импорт из .dll
    cp lib/*.dll "$INSTALL_ROOT/bin/" 2>/dev/null || true
    # cp lib/*.lib "$INSTALL_ROOT/lib/" 2>/dev/null || true

    # не добавляем либы torch в Libs:
    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/libtorch.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: LibTorch
Description: PyTorch C++ API (DLL version)
Version: 2.10.0
Libs: -L\${libdir} -ltorch -ltorch_cpu -lc10
Libs.private: -lstdc++
Cflags: -I\${includedir} -I\${includedir}/torch/csrc/api/include -D_GLIBCXX_USE_CXX11_ABI=1 -DNOMINMAX
EOF
}

ffbuild_cxxflags() {
    echo "-I$FFBUILD_PREFIX/include/torch/csrc/api/include -D_GLIBCXX_USE_CXX11_ABI=1 -DNOMINMAX -DNDEBUG"
}

ffbuild_configure() {
    echo --enable-libtorch
}

ffbuild_unconfigure() {
    echo --disable-libtorch
}
