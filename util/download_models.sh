#!/bin/bash
set -e

MODELS_DIR="${1:-./artifacts/models}"
mkdir -p "$MODELS_DIR"

echo "Downloading AI models for FFmpeg backends..."

echo "Downloading OpenVINO models..."
# OpenVINO Models (ESPCN - Super Resolution x2) работают через vpp_openvino
# URL_OV="https://storage.openvinotoolkit.org/repositories/open_model_zoo/2023.0/models_bin/1/single-image-super-resolution-1033/FP16"
URL_OV="https://storage.openvinotoolkit.org/repositories/open_model_zoo/2023.0/models_bin/1/single-image-super-resolution-1033/FP32"
curl -L "$URL_OV/single-image-super-resolution-1033.xml" -o "$MODELS_DIR/sr_model.xml"
curl -L "$URL_OV/single-image-super-resolution-1033.bin" -o "$MODELS_DIR/sr_model.bin"

# 2. TensorFlow Models (SRCNN) s (EDSR - Enhanced Deep Residual Networks)
echo "Downloading TensorFlow models..."
URL_TF="https://github.com/uzh-rpg/rpg_vimo/raw/master/model/srcnn.pb"
curl -L "$URL_TF/srcnn.pb" -o "$MODELS_DIR/srcnn.pb"

# 3. LibTorch Models (EDSR) Модели .torch для фильтра 'sr'
echo "Downloading LibTorch models..."
URL_TORCH="https://github.com / pytorch / examples / raw / main / super_resolution"
curl -L "$URL_TORCH / model.pth" -o "$MODELS_DIR/edsr_x2.torch"

# Denoise Model (VGG-based denoiser)
URL_DENOISE="https://github.com / pkhungurn / vgg-denoiser / raw / master / model"
curl -L "$URL_DENOISE / vgg_denoiser.pb" -o "$MODELS_DIR/denoise.pb"

echo "All models downloaded to $MODELS_DIR"
