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
    local OV_DIR=$(find . -maxdepth 1 -type d -name "*openvino_*" | head -n 1)
    cd "$OV_DIR"

    # Фикс BOOLEAN и дубликатов для MinGW
    sed -i 's/^#define BOOLEAN OV_BOOLEAN/#ifndef _WIN32\n#define BOOLEAN OV_BOOLEAN\n#endif/' runtime/include/openvino/c/openvino.h
    sed -i '/OPENVINO_C_VAR(const char\*) ov_property_key_intel_gpu_config_file;/d' runtime/include/openvino/c/gpu/gpu_plugin_properties.h

    mkdir -p "$INSTALL_ROOT"/{include,lib,bin,lib/cmake}
    cp -r runtime/include/* "$INSTALL_ROOT/include/"
    cp -r runtime/bin/intel64/Release/* "$INSTALL_ROOT/bin/"

    mkdir -p "$INSTALL_ROOT/lib/cmake"
    cp -r runtime/cmake/* "$INSTALL_ROOT/lib/cmake/"

    # Копируем ВСЕ библиотеки фронтендов, иначе OpenCV не соберется
    find runtime/lib/intel64/Release/ -name "*.lib" | while read -r f; do
        name=$(basename "$f" .lib)
        cp "$f" "$INSTALL_ROOT/lib/lib${name}.a"
        cp "$f" "$INSTALL_ROOT/lib/${name}.lib"
    done

    # Массированный патч путей и типов файлов
    find "$INSTALL_ROOT/lib/cmake" -name "*.cmake" -type f -exec sed -i \
        -e "s|runtime/lib/intel64/Release/|lib/lib|g" \
        -e "s|runtime/lib/intel64/Debug/|lib/lib|g" \
        -e "s|runtime/bin/intel64/Release/|bin/|g" \
        -e "s|runtime/bin/intel64/Debug/|bin/|g" \
        -e "s|runtime/include|include|g" \
        -e "s|\.lib|.a|g" \
        -e "s|liblib|lib|g" \
        {} +

    # код для удаления суффикса 'd'
    # Мы обрабатываем и .a, и .dll, и текстовые упоминания конфигураций
    find "$INSTALL_ROOT/lib/cmake" -name "*.cmake" -type f -exec sed -i \
        -e 's/d\.a/.a/g' -e 's/fronten\.a/frontend.a/g' \
        -e 's/d\.dll/.dll/g' -e 's/fronten\.dll/frontend.dll/g' \
        -e 's/Debug/Release/g' -e 's/DEBUG/RELEASE/g' \
        {} +

    # Это предотвратит ошибку "openvino_onnx_frontendd.a not found"
    # find "$INSTALL_ROOT/lib/cmake" -name "OpenVINOTargets-*.cmake" -exec sed -i \
        # -r 's/([a-zA-Z0-9_]+)d\.a/\1.a/g' {} +

    # Удаляем проверки существования файлов, которые часто ломают find_package в кросс-компиляции
    find "$INSTALL_ROOT/lib/cmake" -name "OpenVINOTargets-*.cmake" -exec sed -i '/_cmake_import_check_files_for_.* exists/d' {} +

    # Корректный pkg-config для динамической линковки
    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/openvino.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: OpenVINO
Description: Intel OpenVINO Runtime
Version: 2025.4.1
Libs: -L\${libdir} -lopenvino -lopenvino_c
Cflags: -I\${includedir}
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
