#!/bin/bash

SCRIPT_REPO="https://download.pytorch.org/libtorch/cpu/libtorch-cxx11-abi-static-with-deps-latest.zip"

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


    log_info "Applying final structural fix for LibTorch headers..."

    # Удаляем спецификаторы DLL, чтобы GCC не ругался на inline функции
    find include/ -name "*.h" -exec sed -i 's/__declspec(dllimport)//g' {} +
    find include/ -name "*.h" -exec sed -i 's/__declspec(dllexport)//g' {} +

    # Патчим макросы экспорта (важно для предотвращения ошибок линковки)
    for header in $(find include -name "Macros.h" -o -name "Export.h"); do
        sed -i '/#define.*_API/d' "$header" # Удаляем старые определения
        echo "#define C10_API" >> "$header"
        echo "#define TORCH_API" >> "$header"
        echo "#define AT_API" >> "$header"
        echo "#define CAFFE2_API" >> "$header"
    done

    # Добавляем cstdint для GCC 13+
    find include/ -type f -exec sed -i '1i #include <cstdint>' {} +

    mkdir -p "$INSTALL_ROOT"/{include,lib,bin}

    # Копируем заголовочные файлы
    cp -r include/* "$INSTALL_ROOT/include/"

    cp -v lib/*.a "$INSTALL_ROOT/lib/" 2>/dev/null || true
    # cp -v lib/*.dll "$INSTALL_ROOT/bin/" 2>/dev/null || true

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/libtorch.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: LibTorch
Description: PyTorch C++ API
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
