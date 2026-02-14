#!/bin/bash

SCRIPT_REPO="https://download.pytorch.org/libtorch/cpu/libtorch-win-shared-with-deps-2.10.0%2Bcpu.zip"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "curl -L \"$SCRIPT_REPO\" --output libtorch.zip && unzip -qq libtorch.zip && mv libtorch libtorch_src"
}

ffbuild_dockerbuild() {
    cd libtorch_src

    mkdir -p "$FFBUILD_DESTPREFIX"/{include,lib,bin}
    
    # Копируем всё содержимое
    cp -r include/* "$FFBUILD_DESTPREFIX/include/"
    # Копируем заголовочные файлы
    # Для MinGW важно, чтобы .lib файлы имели префикс lib, иначе -l не всегда их видит
    for f in lib/*.lib; do cp "$f" "$FFBUILD_DESTPREFIX/lib/lib$(basename "$f")"; done
    cp lib/*.dll "$FFBUILD_DESTPREFIX/bin/"

    # LibTorch требует много флагов, создаем .pc файл
    mkdir -p "$FFBUILD_DESTPREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTPREFIX/lib/pkgconfig/libtorch.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: LibTorch
Description: PyTorch C++ API
Version: 2.10.0
# Переносим основные либы в Libs, чтобы они всегда были видны
Libs: -L\${libdir} -ltorch -ltorch_cpu -lc10
# Добавляем необходимые системные либы Windows в private
Libs.private: -lshlwapi -luser32 -ladvapi32
Cflags: -I\${includedir} -I\${includedir}/torch/csrc/api/include -D_GLIBCXX_USE_CXX11_ABI=1
EOF
}

ffbuild_configure() { echo --enable-libtorch; }
ffbuild_unconfigure() { echo --disable-libtorch; }
