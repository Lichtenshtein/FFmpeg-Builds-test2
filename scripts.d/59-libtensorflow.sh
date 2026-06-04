#!/bin/bash


SCRIPT_REPO="https://storage.googleapis.com/tensorflow/versions/2.16.1/libtensorflow-cpu-windows-x86_64.zip"

# WARNING! A ~960Mb library!
# SCRIPT_REPO="https://storage.googleapis.com/tensorflow/versions/2.18.1/libtensorflow-cpu-windows-x86_64.zip"

ffbuild_enabled() {
    [[ "$USE_TENSORFLOW" == "1" ]] && return 0
    return 1
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

    mkdir -p "$INSTALL_ROOT"/{include/tensorflow/c,bin,lib/pkgconfig}

    # Копируем заголовки
    cp -r include/* "$INSTALL_ROOT/include/"

    # DLL идет строго в bin к ffmpeg.exe
    cp lib/tensorflow.dll "$INSTALL_ROOT/bin/"

    # Библиотеку импорта кладем в lib, чтобы отработал флаг -ltensorflow
    cp lib/tensorflow.lib "$INSTALL_ROOT/lib/libtensorflow.a"

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/tensorflow.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: TensorFlow
Description: TensorFlow C API library
Version: 2.16.1
Libs: -L\${libdir} -ltensorflow
Cflags: -I\${includedir} -I\${includedir}/tensorflow -I\${includedir}/tsl
EOF
}

ffbuild_configure() {
    echo --enable-libtensorflow
}

ffbuild_unconfigure() {
    echo --disable-libtensorflow
}
