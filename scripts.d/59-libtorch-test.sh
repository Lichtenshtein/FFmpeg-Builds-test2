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

    # вырезаем TORCH_API и аналогичные макросы из всех заголовков уберет "definition is marked dllimport"
    find include/ -type f -name "*.h" -exec sed -i 's/TORCH_API//g; s/C10_API//g; s/C10_IMPORT//g; s/AT_API//g;' {} +

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
Libs.private: -lshlwapi -luser32 -ladvapi32 -lstdc++
Cflags: -I\${includedir} -I\${includedir}/torch/csrc/api/include -D_GLIBCXX_USE_CXX11_ABI=1 -DNOMINMAX
EOF
}

ffbuild_cxxflags() {
    echo "-I$FFBUILD_PREFIX/include/torch/csrc/api/include \
          -D_GLIBCXX_USE_CXX11_ABI=1 -DNOMINMAX -DNDEBUG \
          -D_WIN32 -D_WIN64 -D_DLL=0 -D_WINDLL=0 \
          -DTORCH_API= -DC10_IMPORT= -DAT_API= -DCAFFE2_API="
}

ffbuild_configure() {
    echo --enable-libtorch
}

ffbuild_unconfigure() {
    echo --disable-libtorch
}
