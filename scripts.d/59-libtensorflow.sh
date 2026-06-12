#!/bin/bash

# WARNING! 2.18.1 is a ~960Mb library!
TF_VER="2.18.1"

SCRIPT_REPO="https://storage.googleapis.com/tensorflow/versions/${TF_VER}/libtensorflow-cpu-windows-x86_64.zip"

ffbuild_enabled() {
    [[ "$USE_TENSORFLOW" == "1" ]] && return 0
    return 1
}

ffbuild_dockerdl() {
    echo "download_file \"$SCRIPT_REPO\" \"tensorflow.zip\""
    echo "unzip -qq tensorflow.zip -d tf_src"
    echo "rm -f tensorflow.zip"
}

ffbuild_dockerbuild() {
    set -e

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
Version: ${TF_VER}
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
