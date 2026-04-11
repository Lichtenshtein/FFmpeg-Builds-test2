#!/bin/bash

# Ссылка на официальный C-API архив (CPU-only для Windows x86_64)
SCRIPT_REPO="https://storage.googleapis.com/tensorflow/versions/2.16.1/libtensorflow-cpu-windows-x86_64.zip"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    # echo "curl -sL \"$SCRIPT_REPO\" --output tensorflow.zip && unzip -qq tensorflow.zip -d tf_src"
    echo "download_file \"$SCRIPT_REPO\" \"tensorflow.zip\""
}

ffbuild_dockerbuild() {
    set -e

    # Распаковываем (unzip должен быть в base образе)
    unzip -qq tensorflow.zip -d tf_src
    cd tf_src

    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/{include/tensorflow/c,lib,bin,lib/pkgconfig}

    # Копируем заголовки
    cp -r include/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"

    # В Windows архиве TF обычно лежит tensorflow.lib и tensorflow.dll
    # Для MinGW: 
    #  DLL идет в bin (чтобы быть рядом с ffmpeg.exe)
    # .lib копируем как .dll.a (стандарт импортной либы для MinGW)
    cp lib/tensorflow.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"
    cp lib/tensorflow.lib "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libtensorflow.dll.a"
    # На всякий случай создаем копию без .dll
    ln -sf libtensorflow.dll.a "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libtensorflow.a"

    # Генерируем .pc файл и добавляем -ltensorflow.lib явно для линковщика
    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/tensorflow.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
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
