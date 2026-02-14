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
    # Структура архива обычно содержит папку 'lib' и 'include'
    
    mkdir -p "$FFBUILD_DESTPREFIX"/{include/tensorflow/c,lib,bin}

    # Копируем заголовки (сохраняя структуру)
    cp -r include/* "$FFBUILD_DESTPREFIX/include/"

    # Библиотеки и DLL
    # Для MinGW лучше сделать копию .lib с префиксом 'lib'
    cp lib/tensorflow.lib "$FFBUILD_DESTPREFIX/lib/libtensorflow.lib"
    # Сама DLL должна быть в bin, чтобы попасть в финальный архив
    cp lib/tensorflow.dll "$FFBUILD_DESTPREFIX/bin/"

    # Генерируем .pc файл
    # ВАЖНО: Добавляем -ltensorflow.lib явно для линковщика
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
