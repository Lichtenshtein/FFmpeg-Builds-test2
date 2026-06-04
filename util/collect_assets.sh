#!/bin/bash

set -e

# Загружаем функции
source util/dl_functions.sh

ASSETS_DIR="${1:-$ASSETS_DIR}"
FFMPEG_SOURCE_DIR="${2:-$FFMPEG_SOURCE_DIR}"
mkdir -p "$ASSETS_DIR" "$FFBUILD_PREFIX/bin"

# ASSETS_DIR это ".../bin/assets", поднимаемся на 2 уровня вверх, чтобы получить корень пакета
if [[ -z "$PKG_DIR" && -n "$ASSETS_DIR" ]]; then
    PKG_DIR=$(dirname $(dirname "$ASSETS_DIR"))
fi

# Копируем лицензию ПЕРЕД упаковкой
log_info "${SYNC_MARK} Adding license and logs to package..."
[[ -n "$LICENSE_FILE" ]] && cp "$FFMPEG_SOURCE_DIR/$LICENSE_FILE" "$PKG_DIR/LICENSE.txt"
cp "$FFMPEG_CONFIG_LOG" "$PKG_DIR/config.log" || true

# Плагины лежат в lib/frei0r-1, а для работы в Windows должны быть в bin/frei0r-1
if [[ -d "$FFBUILD_PREFIX/lib/frei0r-1" ]]; then
    log_info "${SYNC_MARK} Collecting frei0r plugins..."
    mkdir -p "$PKG_DIR/bin/frei0r-1"
    find "$FFBUILD_PREFIX/lib/frei0r-1" -name "*.dll" -exec mv -v {} "$PKG_DIR/bin/frei0r-1/" \; || true
else
    log_warn "Frei0r plugins not found in $FFBUILD_PREFIX/lib/frei0r-1"
fi

# Плагин nnedi3
if [[ -f "$FFBUILD_PREFIX/lib/libvsznedi3.dll" ]]; then
    log_info "${SYNC_MARK} Moving nnedi3 plugin..."
    mv -f "$FFBUILD_PREFIX/lib/libvsznedi3.dll" "$PKG_DIR/bin/libvsznedi3.dll"
else
    log_warn "nnedi3 plugin not found in $FFBUILD_PREFIX/lib"
fi

# Плагины avisynth
if [[ -d "$FFBUILD_PREFIX/lib/avisynth" ]]; then
    log_info "${SYNC_MARK} Collecting avisynth plugins..."
    find "$FFBUILD_PREFIX/lib/avisynth" -name "*.dll" -exec mv -v {} "$PKG_DIR/bin/" \; || true
else
    log_warn "avisynth plugins not found in $FFBUILD_PREFIX/lib/avisynth"
fi

# Плагины lensfun
if [[ -d "$FFBUILD_PREFIX/share/lensfun" ]]; then
    log_info "${SYNC_MARK} Collecting lensfun profiles..."
    mkdir -p "$PKG_DIR/share/lensfun"
    find "$FFBUILD_PREFIX/share/lensfun/version_2" -name "*.xml" -exec mv -v {} "$PKG_DIR/share/lensfun/" \; || true
else
    log_warn "lensfun profiles not found in $FFBUILD_PREFIX/share/lensfun"
fi

# Копируем все DLL из нашего сборочного префикса в папку с бинарниками
# Это подхватит DLL от OpenVINO, TBB, TensorFlow, LibTorch и других
# OpenVINO часто ищет файлы openvino_intel_cpu_plugin.dll в той же папке
# Если они лежат в /opt/ffbuild/bin, то всё ок. 
# Но если они в подпапках (runtime/bin/intel64/...), нужно убедиться, что они попали в $PKG_DIR/bin/
log_info "${SYNC_MARK} Collecting external component DLLs if present..."
find "$FFBUILD_PREFIX" -maxdepth 3 \( -name '*.dll' -o -name '*.pyd' -o -name '*.bin' -o -name '*.sign' -o -name '*.zip' \) -exec cp -v {} "$PKG_DIR/bin/" \; 2>/dev/null || true

# Автоматический поиск и упаковка системного рантайма MinGW (SSP, WinPthreads, GCC)
log_info "${SYNC_MARK} Analyzing ffmpeg.exe for missing MinGW runtime DLLs..."
if [[ -f "$PKG_DIR/bin/ffmpeg.exe" ]]; then
    # Находим sysroot и бинарную директорию тулчейна, где живут системные DLL
    TOOLCHAIN_SYSROOT=$(${FFBUILD_TOOLCHAIN}-gcc -print-sysroot)
    TOOLCHAIN_BIN_DIR=$(dirname "$(${FFBUILD_TOOLCHAIN}-gcc -print-file-name=libssp.a)")

    # Массив стандартных рантайм-библиотек MinGW, которые могут потребоваться
    RUNTIME_DLLS=("libssp-0.dll" "libwinpthread-1.dll" "libstdc++-6.dll" "libgcc_s_seh-1.dll" "libgomp-1.dll")

    for dll in "${RUNTIME_DLLS[@]}"; do
        # Проверяем, требует ли наш ffmpeg.exe эту конкретную DLL
        if ${FFBUILD_CROSS_PREFIX}objdump -p "$PKG_DIR/bin/ffmpeg.exe" | grep -q -i "$dll"; then
            log_warn "Detected dynamic dependency: $dll. Searching toolchain directories..."
            # Ищем DLL в sysroot или в папках компилятора
            FOUND_DLL=""
            if [[ -f "${TOOLCHAIN_SYSROOT}/bin/$dll" ]]; then
                FOUND_DLL="${TOOLCHAIN_SYSROOT}/bin/$dll"
            elif [[ -f "${TOOLCHAIN_BIN_DIR}/$dll" ]]; then
                FOUND_DLL="${TOOLCHAIN_BIN_DIR}/$dll"
            else
                # Глобальный поиск по всему каталогу ct-ng на крайний случай
                FOUND_DLL=$(find /opt/ct-ng -name "$dll" -type f -print -quit)
            fi
            if [[ -n "$FOUND_DLL" ]]; then
                cp -v "$FOUND_DLL" "$PKG_DIR/bin/"
                log_info "${CHECK_MARK} Successfully bundled system runtime: $dll"
            else
                log_error "Required system runtime $dll not found in toolchain!"
            fi
        fi
    done
fi

log_info "${START_MARK} Starting AI/OCR model and conditional asset collection..."

# ТЕРРИТОРИЯ ССЫЛОК

# Tesseract (tessdata_best)
URL_TESS_BASE="https://raw.githubusercontent.com/tesseract-ocr/tessdata_best/refs/heads/main"
URL_TESS_SCRIPT="https://raw.githubusercontent.com/tesseract-ocr/tessdata_best/refs/heads/main/script"

# TensorFlow (SRCNN)
URL_TF_SRCNN="https://github.com/uzh-rpg/rpg_vimo/raw/master/model/srcnn.pb"

# OpenVINO (ESPCN)
URL_OV_BASE="https://storage.openvinotoolkit.org/repositories/open_model_zoo/2023.0/models_bin/1/single-image-super-resolution-1033/FP32"
# URL_OV_BASE2="https://storage.openvinotoolkit.org/repositories/open_model_zoo/2023.0/models_bin/1/single-image-super-resolution-1033/FP16"

# LibTorch (EDSR)
URL_TORCH_EDSR="https://github.com/pytorch/examples/raw/main/super_resolution/model.pth"

# APPLE AUDIOTOOLBOX
QTFILES_URL="https://github.com/AnimMouse/QTFiles/releases/download/v12.13.9.1/QTfiles64.7z"

# ЛОГИКА ЗАГРУЗКИ

# TESSERACT MODELS (OCR)
if [[ "$HAS_LIBTESSERACT" == "1" ]]; then
    log_info "${DOWN_MARK} Downloading Tesseract OCR models (tessdata_best)"
    TESS_DEST="$PKG_DIR/tessdata"
    mkdir -p "$TESS_DEST/script"

    # Список необходимых файлов
    TESS_FILES=(
"eng.traineddata"
"rus.traineddata"
"osd.traineddata" # Важен для определения ориентации
# "chi_sim.traineddata"
# "chi_sim_vert.traineddata"
"jpn.traineddata"
"jpn_vert.traineddata"
"pdf.ttf"
    )

    TESS_FILES2=(
"Cyrillic.traineddata"
"Japanese.traineddata"
"Japanese_vert.traineddata"
    )

    # Чистим ссылки от пробелов перед использованием
    LINK_BASE=$(echo "$URL_TESS_BASE" | tr -d ' ')
    LINK_SCRIPT=$(echo "$URL_TESS_SCRIPT" | tr -d ' ')

    for file in "${TESS_FILES[@]}"; do
        download_file "$LINK_BASE/$file" "$TESS_DEST/$file" ""
    done

    for file in "${TESS_FILES2[@]}"; do
        download_file "$LINK_SCRIPT/$file" "$TESS_DEST/script/$file" ""
    done
fi

# TENSORFLOW / DNN MODELS (Super Resolution)
# Проверяем флаг HAS_LIBTENSORFLOW или наличие в config.h
if [[ "$HAS_LIBTENSORFLOW" == "1" ]] || grep -q "CONFIG_SR_FILTER 1" "$FFMPEG_SOURCE_DIR/config.h" 2>/dev/null; then
    log_info "${DOWN_MARK} Downloading TensorFlow SR models"
    LINK_TF=$(echo "$URL_TF_SRCNN" | tr -d ' ')
    download_file "$LINK_TF" "$ASSETS_DIR/srcnn.pb" ""
fi

# OPENVINO MODELS (VPP_OPENVINO)
# OpenVINO Models (ESPCN - Super Resolution x2) работают через vpp_openvino
if [[ "$HAS_LIBOPENVINO" == "1" ]] || grep -q "CONFIG_VPP_OPENVINO_FILTER 1" "$FFMPEG_SOURCE_DIR/config.h" 2>/dev/null; then
    log_info "${DOWN_MARK} Downloading OpenVINO models"
    LINK_OV=$(echo "$URL_OV_BASE" | tr -d ' ')
    download_file "$LINK_OV/single-image-super-resolution-1033.xml" "$ASSETS_DIR/sr_model.xml" ""
    download_file "$LINK_OV/single-image-super-resolution-1033.bin" "$ASSETS_DIR/sr_model.bin" ""
fi

# LIBTORCH MODELS (EDSR) Модели .torch для фильтра 'sr'
if [[ "$HAS_LIBTORCH" == "1" ]]; then
    log_info "${DOWN_MARK} Downloading LibTorch models..."
    LINK_TORCH=$(echo "$URL_TORCH_EDSR" | tr -d ' ')
    download_file "$LINK_TORCH" "$ASSETS_DIR/edsr_x2.torch" ""
fi

# APPLE AUDIOTOOLBOX DLLS (Special handling)
if [[ "$HAS_AUDIOTOOLBOX" == "1" ]]; then
    log_info "${DOWN_MARK} Downloading Apple AudioToolbox DLLs..."

    if download_file "$QTFILES_URL" "qtfiles64.7z" ""; then
        log_info "${EXTR_MARK} Extracting Apple DLLs directly to package..."

        # Гарантируем, что целевая папка существует
        mkdir -p "$PKG_DIR/bin"

        # Распаковываем все DLL плоско (без подпапок) напрямую в $PKG_DIR/bin
        7z e qtfiles64.7z -o"$PKG_DIR/bin" "*.dll" -y > /dev/null

        # Проверяем, что файлы успешно легли на место
        if ls "$PKG_DIR/bin"/CoreAudioToolbox.dll >/dev/null 2>&1; then
            log_info "${CHECK_MARK} Apple AudioToolbox DLLs successfully deployed to $PKG_DIR/bin"
        else
            log_error "AudioToolbox DLLs deployment verification failed!"
        fi
        rm -f qtfiles64.7z
    else
        log_warn "Assets download failed, but continuing..."
    fi
fi

log_info "${CHECK_MARK} All models and asset collection finished for enabled components and moved to:\n$ASSETS_DIR"
