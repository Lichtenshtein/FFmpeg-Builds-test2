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

    # Распаковываем (unzip должен быть в base образе)
    unzip -qq tensorflow.zip -d tf_src
    # Находим папку (имя может меняться в зависимости от билда)
    local TF_DIR=$(find . -maxdepth 1 -type d -name "tf_src*" | head -n 1)
    cd "$TF_DIR"

    # Структура архива обычно содержит папку 'lib' и 'include'
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/{include/tensorflow/c,lib,bin}

    # Копируем заголовки (сохраняя структуру)
    cp -r include/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"

    # Библиотеки и DLL
    # Для MinGW лучше сделать копию .lib с префиксом 'lib'
    cp lib/tensorflow.lib "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libtensorflow.dll.a"
    # Сама DLL должна быть в bin, чтобы попасть в финальный архив
    cp lib/tensorflow.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"

    # Генерируем .pc файл и добавляем -ltensorflow.lib явно для линковщика
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTPREFIX/lib/pkgconfig/tensorflow.pc"
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

ffbuild_libs() {
    echo "-lbcrypt -ldbghelp"
}
