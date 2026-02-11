#!/bin/bash

SCRIPT_REPO="https://storage.openvinotoolkit.org"

ffbuild_enabled() {
    (( $(ffbuild_ffver) >= 404 )) || return -1
    return 0
}

ffbuild_dockerdl() {
    # Используем wget, так как это прямой URL на zip
    echo "wget -O openvino.zip \"$SCRIPT_REPO\" && unzip openvino.zip && mv w_openvino_* openvino_src"
}

ffbuild_dockerbuild() {
    cd openvino_src

    # Копируем заголовки в префикс
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include"
    cp -r runtime/include/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"

    # Копируем библиотеки (DLL и LIB)
    # FFmpeg при линковке с MinGW будет искать .lib или .dll.a
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib"
    cp runtime/lib/intel64/Release/*.lib "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
    
    # Копируем рантайм-библиотеки в bin, чтобы они попали в финальный архив
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin"
    cp runtime/bin/intel64/Release/*.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"
    cp runtime/3rdparty/tbb/bin/*.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"

    # Генерируем заглушку .pc файла, чтобы FFmpeg нашел openvino через pkg-config
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/openvino.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: OpenVINO
Description: Intel(R) Distribution of OpenVINO(TM) Toolkit
Version: 2024.4.0
Libs: -L\${libdir} -lopenvino
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-libopenvino
}

ffbuild_unconfigure() {
    echo --disable-libopenvino
}
