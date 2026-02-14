#!/bin/bash

# Прямая ссылка на архив Runtime 2024.6.0
# SCRIPT_REPO="https://storage.openvinotoolkit.org/repositories/openvino/packages/2024.6/windows/w_openvino_toolkit_windows_2024.6.0.17404.4c0f47d2335_x86_64.zip"
SCRIPT_REPO="https://storage.openvinotoolkit.org/repositories/openvino/packages/2025.4.1/windows/openvino_toolkit_windows_2025.4.1.20426.82bbf0292c5_x86_64.zip"

ffbuild_enabled() {
    (( $(ffbuild_ffver) >= 404 )) || return -1
    return 0
}

ffbuild_dockerdl() {
    # Скачиваем с проверкой, что это действительно ZIP
    # echo "curl -L \"$SCRIPT_REPO\" --output openvino.zip && unzip -qq openvino.zip && mv w_openvino_* openvino_src"
    echo "curl -L \"$SCRIPT_REPO\" --output openvino.zip && unzip -qq openvino.zip && mv openvino_* openvino_src"
}

ffbuild_dockerbuild() {
    cd openvino_src

    # Инсталляция заголовков и библиотек
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/{include,lib,bin}
    cp -r runtime/include/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"
    cp runtime/lib/intel64/Release/*.lib "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
    cp runtime/bin/intel64/Release/*.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"
    cp runtime/3rdparty/tbb/bin/*.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"
    # Создаем именно lib/cmake и копируем туда
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/cmake"
    cp -r runtime/cmake/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/cmake/"

    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/openvino.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: OpenVINO
Description: Intel Distribution of OpenVINO Toolkit
Version: 2024.6.0
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
