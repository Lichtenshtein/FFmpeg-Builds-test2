#!/bin/bash

set -e

# Загружаем функции
source util/dl_functions.sh

ASSETS_DIR="${1:-$ASSETS_DIR}"
FFMPEG_SOURCE_DIR="${2:-$FFMPEG_SOURCE_DIR}"

# На всякий случай восстанавливаем путь, если FFMPEG_SOURCE_DIR внезапно оказалась пустой
if [[ -z "${FFMPEG_SOURCE_DIR:-}" ]]; then
    if [[ -d "${ROOT_DIR}/ffbuild/ffmpeg" ]]; then
        FFMPEG_SOURCE_DIR="${ROOT_DIR}/ffbuild/ffmpeg"
    elif [[ -d "./ffbuild/ffmpeg" ]]; then
        FFMPEG_SOURCE_DIR="$(pwd)/ffbuild/ffmpeg"
    else
        FFMPEG_SOURCE_DIR="."
    fi
fi

mkdir -p "$ASSETS_DIR" "$FFBUILD_PREFIX/bin"

# ASSETS_DIR это ".../bin/assets", поднимаемся на 2 уровня вверх, чтобы получить корень пакета
if [[ -z "$PKG_DIR" && -n "$ASSETS_DIR" ]]; then
    PKG_DIR=$(dirname $(dirname "$ASSETS_DIR"))
fi

if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
    log_debug "${DIRS_MARK} FFmpeg source directory:\n${FFMPEG_SOURCE_DIR}"
    log_debug "${DIRS_MARK} FFmpeg assets directory:\n${ASSETS_DIR}"
    log_debug "${DIRS_MARK} FFmpeg package directory:\n${PKG_DIR}"
fi

# ====================
# # ASSET COLLECTION
# ====================

# Копируем лицензию ПЕРЕД упаковкой
log_info "${SYNC_MARK} Adding licenses to package..."
LICENSE_FILES=("COPYING.GPLv3" "COPYING.LGPLv3" "LICENSE.md")
for lic in "${LICENSE_FILES[@]}"; do
    # Формируем полный абсолютный путь к файлу лицензии
    FULL_LIC_PATH="${FFMPEG_SOURCE_DIR}/${lic}"

    if [[ -f "$FULL_LIC_PATH" ]]; then
        # Копируем файл в корень архива ($PKG_DIR)
        cp -v "$FULL_LIC_PATH" "$PKG_DIR/"
        log_info "${CHECK_MARK} License bundled successfully from ${FFMPEG_SOURCE_DIR}: $lic"
    else
        # Если не нашли в основной папке, ищем в текущей рабочей директории
        if [[ -f "./$lic" ]]; then
            cp -v "./$lic" "$PKG_DIR/"
            log_info "${CHECK_MARK} License bundled from current dir: $lic"
        else
            log_error "License file not found anywhere: $lic (Checked path: $FULL_LIC_PATH)"
        fi
    fi
done

# Плагины лежат в lib/frei0r-1, а для работы в Windows должны быть в bin/frei0r-1
if [[ -d "$FFBUILD_PREFIX/lib/frei0r-1" ]]; then
    log_info "${SYNC_MARK} Collecting frei0r plugins..."
    mkdir -p "$PKG_DIR/bin/frei0r-1"
    find "$FFBUILD_PREFIX/lib/frei0r-1" -name "*.dll" -exec cp -v {} "$PKG_DIR/bin/frei0r-1/" \; || true
else
    log_warn "Frei0r plugins not found in $FFBUILD_PREFIX/lib/frei0r-1"
fi

# Модели pocketsphinx
if [[ -d "$FFBUILD_PREFIX/share/pocketsphinx" ]]; then
    log_info "${SYNC_MARK} Collecting pocketsphinx models..."
    mkdir -p "$ASSETS_DIR/pocketsphinx"
    cp -v "$FFBUILD_PREFIX/share/pocketsphinx" "${ASSETS_DIR}/"
else
    log_warn "Pocketsphinx models not found in $FFBUILD_PREFIX/share/pocketsphinx"
fi

# Плагин nnedi3
if [[ -f "$FFBUILD_PREFIX/lib/libvsznedi3.dll" ]]; then
    log_info "${SYNC_MARK} Moving nnedi3 plugin..."
    cp -v "$FFBUILD_PREFIX/lib/libvsznedi3.dll" "$PKG_DIR/bin/libvsznedi3.dll"
elif [[ -f "$FFBUILD_PREFIX/lib/libznedi3.a" ]]; then
    log_info "Found static libznedi3.a instead of libvsznedi3.dll in $FFBUILD_PREFIX/lib"
else
    log_warn "nnedi3 plugin not found in $FFBUILD_PREFIX/lib"
fi

# Плагины avisynth
if [[ -d "$FFBUILD_PREFIX/lib/avisynth" ]]; then
    log_info "${SYNC_MARK} Collecting avisynth plugins..."
    find "$FFBUILD_PREFIX/lib/avisynth" -name "*.dll" -exec cp -v {} "$PKG_DIR/bin/" \; || true
else
    log_warn "avisynth plugins not found in $FFBUILD_PREFIX/lib/avisynth"
fi

# Плагины lensfun
if [[ -d "$FFBUILD_PREFIX/share/lensfun" ]]; then
    log_info "${SYNC_MARK} Collecting lensfun profiles..."
    mkdir -p "$ASSETS_DIR/lensfun"
    find "$FFBUILD_PREFIX/share/lensfun/version_2" -name "*.xml" -exec cp -v {} "$ASSETS_DIR/lensfun/" \; || true
else
    log_warn "lensfun profiles not found in $FFBUILD_PREFIX/share/lensfun"
fi

# Пылесосим все оставшиеся DLL изсборочного префикса в папку с бинарниками
log_info "${SYNC_MARK} Collecting external component DLLs if present..."
find "$FFBUILD_PREFIX" -maxdepth 3 \( -name '*.dll' -o -name '*.pyd' -o -name '*.bin' -o -name '*.sign' -o -name '*.zip' \) -exec cp -v {} "$PKG_DIR/bin/" \; 2>/dev/null || true

# Автопоиск и упаковка системного рантайма MinGW (SSP, WinPthreads, GCC)
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

# Копируем лог сборки
log_info "${SYNC_MARK} Coping build log file..."
cp "$FFMPEG_CONFIG_LOG" "$PKG_DIR/config.log" || true

# ===================
# TERRITORY OF LINKS
# ===================

# Tesseract (tessdata_best)
URL_TESS_BASE="https://raw.githubusercontent.com/tesseract-ocr/tessdata_best/refs/heads/main"
URL_TESS_SCRIPT="https://raw.githubusercontent.com/tesseract-ocr/tessdata_best/refs/heads/main/script"

# OpenVINO (ESPCN)
URL_OV_BASE="https://storage.openvinotoolkit.org/repositories/open_model_zoo/2023.0/models_bin/1/single-image-super-resolution-1033/FP32"
# URL_OV_BASE2="https://storage.openvinotoolkit.org/repositories/open_model_zoo/2023.0/models_bin/1/single-image-super-resolution-1033/FP16"

# LibTorch (EDSR)
URL_TORCH_EDSR="https://github.com/pytorch/examples/raw/main/super_resolution/model.pth"

# APPLE AUDIOTOOLBOX
QTFILES_URL="https://github.com/AnimMouse/QTFiles/releases/download/v12.13.9.1/QTfiles64.7z"

# ===================
# DOWNLOADING LOGIC
# ===================

log_info "${START_MARK} Starting AI/OCR model and conditional asset collection..."

# TESSERACT MODELS (OCR)
if [[ "$HAS_LIBTESSERACT" == "1" ]]; then
    log_info "${DOWN_MARK} Downloading Tesseract OCR models (tessdata_best)"
    TESS_DEST="$PKG_DIR/bin/tessdata"
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

    log_info "${SYNC_MARK} Moving tessdata configs..."
    if [ -d "$FFBUILD_PREFIX/share/tessdata" ]; then
        # -a (archive) включает рекурсию (-r) и сохраняет все права/структуру файлов
        # -v (verbose) покажет в логах, какие файлы копируются
        cp -av "$FFBUILD_PREFIX/share/tessdata"/* "$TESS_DEST/"
    else
        log_warn "Source tessdata configs directory not found in $FFBUILD_PREFIX/share/tessdata"
    fi
fi

# TENSORFLOW / DNN MODELS (Super Resolution)
if [[ "$HAS_LIBTENSORFLOW" == "1" ]]; then
    log_info "${SYNC_MARK} Collecting TensorFlow SR models from build context..."

    TARGET_MODEL_DIR="$ASSETS_DIR/tensorflow"
    INTERNAL_MODELS_DIR="${FFBUILD_PREFIX}/share/tensorflow_models"

    mkdir -p "$TARGET_MODEL_DIR"

    if [[ -d "$INTERNAL_MODELS_DIR" && "$(ls -A "$INTERNAL_MODELS_DIR" 2>/dev/null)" ]]; then
        cp -v "$INTERNAL_MODELS_DIR"/*.pb "$TARGET_MODEL_DIR/"
        log_info "${CHECK_MARK} TensorFlow SR models successfully bundled into package!"
    else
        log_error "TensorFlow SR models not found in internal storage ($INTERNAL_MODELS_DIR)!"
        # exit 1
    fi
fi

# OPENVINO MODELS (VPP_OPENVINO)
# OpenVINO Models (ESPCN - Super Resolution x2) работают через vpp_openvino
if [[ "$HAS_LIBOPENVINO" == "1" ]]; then
    log_info "${DOWN_MARK} Downloading OpenVINO models..."
    mkdir -p "$ASSETS_DIR/openvino"
    LINK_OV=$(echo "$URL_OV_BASE" | tr -d ' ')
    download_file "$LINK_OV/single-image-super-resolution-1033.xml" "$ASSETS_DIR/openvino/sr_model.xml" ""
    download_file "$LINK_OV/single-image-super-resolution-1033.bin" "$ASSETS_DIR/openvino/sr_model.bin" ""
fi

# LIBTORCH MODELS (EDSR) Модели .torch для фильтра 'sr'
if [[ "$HAS_LIBTORCH" == "1" ]]; then
    log_info "${DOWN_MARK} Downloading LibTorch models..."
    mkdir -p "$ASSETS_DIR/torch"
    LINK_TORCH=$(echo "$URL_TORCH_EDSR" | tr -d ' ')
    download_file "$LINK_TORCH" "$ASSETS_DIR/torch/edsr_x2.torch" ""
fi

# APPLE AUDIOTOOLBOX DLLS (Special handling)
if [[ "$HAS_AUDIOTOOLBOX" == "1" ]]; then
    log_info "${DOWN_MARK} Downloading Apple AudioToolbox DLLs..."

    if download_file "$QTFILES_URL" "qtfiles64.7z" ""; then
        log_info "${EXTR_MARK} Extracting Apple DLLs directly to package..."

        mkdir -p "$PKG_DIR/bin"

        7z e qtfiles64.7z -o"$PKG_DIR/bin" "*.dll" -y > /dev/null

        if ls "$PKG_DIR/bin"/CoreAudioToolbox.dll >/dev/null 2>&1; then
            log_info "${CHECK_MARK} Apple AudioToolbox DLLs successfully deployed to:\n${PKG_DIR}/bin"
        else
            log_error "AudioToolbox DLLs deployment verification failed!"
        fi
        rm -f qtfiles64.7z
    else
        log_warn "Assets download failed, but continuing..."
    fi
fi

log_info "${CHECK_MARK} All models and asset collection finished for enabled components."

# Проверяем наличие критических библиотек (для отладки в логах)
if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
    ls -lh "$PKG_DIR/bin/"
fi