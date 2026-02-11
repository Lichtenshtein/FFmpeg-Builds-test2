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

    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/{include,lib,bin}
    
    # Копируем всё содержимое
    cp -r include/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"
    cp lib/*.lib "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
    cp lib/*.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"

    # LibTorch требует много флагов, создаем .pc файл
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libtorch.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: LibTorch
Description: PyTorch C++ API
Version: 2.5.1
Libs: -L\${libdir} -ltorch -ltorch_cpu -lc10
Cflags: -I\${includedir} -I\${includedir}/torch/csrc/api/include
EOF
}

ffbuild_configure() { echo --enable-libtorch; }
ffbuild_unconfigure() { echo --disable-libtorch; }
