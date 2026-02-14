#!/bin/bash

# Ссылка на официальный C-API архив (CPU-only для Windows x86_64)
SCRIPT_REPO="https://storage.googleapis.com/tensorflow/versions/2.16.1/libtensorflow-cpu-windows-x86_64.zip"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "curl -L \"$SCRIPT_REPO\" --output tensorflow.zip && unzip -qq tensorflow.zip -d tf_src"
}

ffbuild_dockerbuild() {
    cd tf_src

    # Подготавливаем структуру префикса
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/{include/tensorflow/c,lib,bin}

    # 1. Копируем заголовки
    cp -r include/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"

    # 2. Библиотеки и DLL
    # Для TensorFlow на Windows используется tensorflow.lib и tensorflow.dll
    cp lib/tensorflow.lib "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
    cp lib/tensorflow.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"

    # 3. Генерируем .pc файл для FFmpeg
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/tensorflow.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: TensorFlow
Description: TensorFlow C API library
Version: 2.16.1
Libs: -L\${libdir} -ltensorflow
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-libtensorflow
}

ffbuild_unconfigure() {
    echo --disable-libtensorflow
}
