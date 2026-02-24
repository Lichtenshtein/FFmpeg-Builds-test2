#!/bin/bash

# Прямая ссылка на архив Runtime 2024.6.0
# SCRIPT_REPO="https://storage.openvinotoolkit.org/repositories/openvino/packages/2024.6/windows/w_openvino_toolkit_windows_2024.6.0.17404.4c0f47d2335_x86_64.zip"
SCRIPT_REPO="https://storage.openvinotoolkit.org/repositories/openvino/packages/2025.4.1/windows/openvino_toolkit_windows_2025.4.1.20426.82bbf0292c5_x86_64.zip"

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
    # Включаем расширенный glob (если еще не включен)
    shopt -s extglob

    # Распаковываем (unzip должен быть в base образе)
    unzip -qq openvino.zip
    # Находим папку (имя может меняться в зависимости от билда)
    local OV_DIR=$(find . -maxdepth 1 -type d -name "openvino_*" | head -n 1)
    cd "$OV_DIR"

    log_info "Installing OpenVINO Runtime to $FFBUILD_PREFIX"

    mkdir -p "$FFBUILD_DESTPREFIX"/{include,lib,bin}

    # 1. Инсталляция заголовков и библиотек
    cp -r runtime/include/* "$FFBUILD_DESTPREFIX/include/"

    # 2. Библиотеки импорта для MinGW (.lib -> .dll.a)
    for f in runtime/lib/intel64/Release/*.lib; do 
        # убираем 'lib' из basename, если он там уже есть, или добавляем аккуратно
        [[ -e "$f" ]] || continue
        local NAME=$(basename "$f" .lib)
        # Для MinGW: lib + имя + .dll.a
        cp "$f" "$FFBUILD_DESTPREFIX/lib/lib${NAME}.dll.a"
    done

    # 3. Копируем ВСЕ DLL (включая TBB и плагины)
    # Основные DLL рантайма
    cp runtime/bin/intel64/Release/*.dll "$FFBUILD_DESTPREFIX/bin/"
    # Плагины (без них OpenVINO не найдет девайсы)
    # Копируем всё содержимое папки Release (плагины и конфиги)
    cp -r runtime/bin/intel64/Release/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"
    cp runtime/bin/intel64/Release/openvino_intel_cpu_plugin.dll "$FFBUILD_DESTPREFIX/bin/" 2>/dev/null || true

    # Копируем всё, что заканчивается на .dll, НО не содержит _debug перед расширением
    # TBB (библиотека потоков от Intel)
    if [[ -d "runtime/3rdparty/tbb/bin" ]]; then
        find runtime/3rdparty/tbb/bin/ -name "*.dll" ! -name "*_debug.dll" -exec cp {} "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/" \;
        # Также копируем lib-файлы для TBB
        for f in runtime/3rdparty/tbb/lib/*.lib; do
            [[ -e "$f" ]] || continue
            local TBB_NAME=$(basename "$f" .lib)
            cp "$f" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/lib${TBB_NAME}.dll.a"
        done
    fi

    # Создаем именно lib/cmake и копируем туда
    mkdir -p "$FFBUILD_DESTPREFIX/lib/cmake"
    cp -r runtime/cmake/* "$FFBUILD_DESTPREFIX/lib/cmake/"

    # 4. Генерация pkg-config
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/openvino.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: OpenVINO
Description: Intel OpenVINO Runtime (Dynamic)
Version: 2025.4.1
Libs: -L\${libdir} -lopenvino -lopenvino_c
Libs.private: -ltbb12 -ltbb
Cflags: -I\${includedir} -DOPENVINO_STATIC_COMPILATION
EOF
}

ffbuild_configure() {
    echo --enable-libopenvino
}

ffbuild_unconfigure() {
    echo --disable-libopenvino
}
