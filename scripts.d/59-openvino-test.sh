#!/bin/bash

# Прямая ссылка на архив Runtime 2024.6.0
# SCRIPT_REPO="https://storage.openvinotoolkit.org/repositories/openvino/packages/2024.6/windows/w_openvino_toolkit_windows_2024.6.0.17404.4c0f47d2335_x86_64.zip"
SCRIPT_REPO="https://storage.openvinotoolkit.org/repositories/openvino/packages/2025.4.1/windows/openvino_toolkit_windows_2025.4.1.20426.82bbf0292c5_x86_64.zip"

ffbuild_depends() {
    echo tbbmalloc
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    # Скачиваем с проверкой, что это действительно ZIP
    # echo "curl -L \"$SCRIPT_REPO\" --output openvino.zip && unzip -qq openvino.zip && mv w_openvino_* openvino_src"
    # echo "curl -sL \"$SCRIPT_REPO\" --output openvino.zip && unzip -qq openvino.zip && mv openvino_* openvino_src"
    echo "download_file \"$SCRIPT_REPO\" \"openvino.zip\""
}

ffbuild_dockerbuild() {
    set -e

    unzip -qq openvino.zip
    # Находим папку (имя может меняться в зависимости от билда)
    local OV_DIR=$(find . -maxdepth 1 -type d -name "*openvino_*" | head -n 1)
    cd "$OV_DIR"

    log_info "Installing OpenVINO Runtime to $FFBUILD_PREFIX"

    mkdir -p "$INSTALL_ROOT"/{include,lib,bin,lib/cmake}

    # заголовки
    cp -r runtime/include/* "$INSTALL_ROOT/include/"

    # Библиотеки
    find runtime/lib/intel64/Release/ -name "*.lib" -exec cp {} "$INSTALL_ROOT/lib/" \;

    # Бинарники (DLL и плагины)
    # Копируем всё содержимое Release в bin (включая плагины и json конфиги)
    cp -r runtime/bin/intel64/Release/* "$INSTALL_ROOT/bin/"

    # TBB (Intel Threading Building Blocks)
    # if [[ -d "runtime/3rdparty/tbb" ]]; then
        # find runtime/3rdparty/tbb/bin/ -name "*.dll" ! -name "*_debug.dll" -exec cp {} "$INSTALL_ROOT/bin/" \;
        # find runtime/3rdparty/tbb/lib/ -name "*.lib" ! -name "*_debug.lib" -exec cp {} "$INSTALL_ROOT/lib/" \;
    # fi

    # CMake файлы
    cp -r runtime/cmake/* "$INSTALL_ROOT/lib/cmake/"

    cd "$INSTALL_ROOT/lib/cmake"

    # Сначала исправляем пути и расширения во всех файлах
    # Мы используем 'lib/lib' и 'liblib' чтобы гарантировать префикс lib для MinGW
    find . -name "*.cmake" -type f -exec sed -i \
        -e "s|runtime/lib/intel64/Release/|lib/lib|g" \
        -e "s|runtime/lib/intel64/Debug/|lib/lib|g" \
        -e "s|runtime/bin/intel64/Release/|bin/|g" \
        -e "s|runtime/bin/intel64/Debug/|bin/|g" \
        -e "s|lib/intel64/Release/|lib/lib|g" \
        -e "s|\.lib|.dll.a|g" \
        -e "s|liblib|lib|g" \
        {} +

    # Убиваем дебажные суффиксы 'd', которые ищутся в Targets-debug.cmake
    # Например: openvino_onnx_frontendd.dll.a -> openvino_onnx_frontend.dll.a
    # И подменяем конфигурацию Debug на Release прямо в тексте
    find . -name "*Targets-debug.cmake" -type f -exec sed -i \
        -e "s|frontendd\.dll\.a|frontend.dll.a|g" \
        -e "s|vinod\.dll\.a|vino.dll.a|g" \
        -e "s|onnxd\.dll\.a|onnx.dll.a|g" \
        -e "s|paddled\.dll\.a|paddle.dll.a|g" \
        -e "s|pytorchd\.dll\.a|pytorch.dll.a|g" \
        -e "s|tensorflowd\.dll\.a|tensorflow.dll.a|g" \
        -e "s|/Debug/|/Release/|g" \
        -e "s|DEBUG|RELEASE|g" \
        {} +

    # Радикальный шаг: если Targets-debug все еще мешает, просто обнулим его
    # (OpenCV все равно собирается в Release и дебажные символы внешних либ ему не нужны)
    # echo > OpenVINOTargets-debug.cmake 

    echo "--- DEBUG: Checking if any 'runtime' strings left ---"
    grep -r "runtime" . || echo "Clean!"

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/openvino.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: OpenVINO
Description: Intel OpenVINO Runtime (Dynamic)
Version: 2025.4.1
Libs: -L\${libdir} -lopenvino -lopenvino_c
# Libs.private: -ltbb12 -ltbb
Cflags: -I\${includedir} -DOPENVINO_STATIC_COMPILATION
EOF
}

ffbuild_libs() {
    echo "-lopenvino_c -lopenvino"
}

ffbuild_configure() {
    echo --enable-libopenvino
}

ffbuild_unconfigure() {
    echo --disable-libopenvino
}
