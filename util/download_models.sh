#!/bin/bash

set -e

MODELS_DIR="${1:-./artifacts/models}"
FF_PREFIX="/opt/ffbuild"
mkdir -p "$MODELS_DIR"

log_info "### 🤖 Starting AI/OCR model collection..."

# TESSERACT MODELS (OCR)
# Скачиваем только если libtesseract была собрана
if [ -f "$FF_PREFIX/lib/libtesseract55.a" ] || [ -f "$FF_PREFIX/lib/libtesseract.a" ]; then
    log_info "Collecting Tesseract OCR models (tessdata_best)"
    TESS_DEST="$MODELS_DIR/tessdata"
    mkdir -p "$TESS_DEST/script"

    BASE_URL="https://raw.githubusercontent.com/tesseract-ocr/tessdata_best/refs/heads/main"
    BASE_URL2="https://raw.githubusercontent.com/tesseract-ocr/tessdata_best/refs/heads/main/script"

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

    for file in "${TESS_FILES[@]}"; do
        if [ ! -f "$TESS_DEST/$file" ]; then
            log_info "Downloading $file..."
            curl -L "$BASE_URL/$file" -o "$TESS_DEST/$file"
        fi
    done

    for file in "${TESS_FILES2[@]}"; do
        if [ ! -f "$TESS_DEST/script/$file" ]; then
            log_info "Downloading $file..."
            curl -L "$BASE_URL2/$file" -o "$TESS_DEST/script/$file"
        fi
    done
fi

# TENSORFLOW / DNN MODELS (Super Resolution)
# Проверяем, включен ли фильтр sr (Super Resolution)
if grep -q "CONFIG_SR_FILTER 1" ffbuild/ffmpeg/config.h 2>/dev/null; then
    log_info "Collecting TensorFlow SR models"
    # SRCNN (стандартная модель для фильтра 'sr' в FFmpeg)
    URL_SRCNN="https://github.com/uzh-rpg/rpg_vimo/raw/master/model/srcnn.pb"
    curl -L "$URL_SRCNN" -o "$MODELS_DIR/srcnn.pb"
fi

# OPENVINO MODELS (VPP_OPENVINO)
# OpenVINO Models (ESPCN - Super Resolution x2) работают через vpp_openvino
# URL_OV="https://storage.openvinotoolkit.org/repositories/open_model_zoo/2023.0/models_bin/1/single-image-super-resolution-1033/FP16"
if grep -q "CONFIG_VPP_OPENVINO_FILTER 1" ffbuild/ffmpeg/config.h 2>/dev/null; then
    log_info "--- Collecting OpenVINO models ---"
    OV_BASE="https://storage.openvinotoolkit.org/repositories/open_model_zoo/2023.0/models_bin/1/single-image-super-resolution-1033/FP32"
    curl -L "$OV_BASE/single-image-super-resolution-1033.xml" -o "$MODELS_DIR/sr_model.xml"
    curl -L "$OV_BASE/single-image-super-resolution-1033.bin" -o "$MODELS_DIR/sr_model.bin"
fi

# LibTorch Models (EDSR) Модели .torch для фильтра 'sr'
log_info "Downloading LibTorch models..."
URL_TORCH="https://github.com/pytorch/examples/raw/main/super_resolution"
curl -L "$URL_TORCH/model.pth" -o "$MODELS_DIR/edsr_x2.torch"

# Denoise Model (VGG-based denoiser)
URL_DENOISE="https://github.com/pkhungurn/vgg-denoiser/raw/master/model"
curl -L "$URL_DENOISE/vgg_denoiser.pb" -o "$MODELS_DIR/denoise.pb"

log_info "✅ All required models for enabled components are in $MODELS_DIR"
