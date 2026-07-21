#!/bin/bash

# Tesseract (tessdata_best)
URL_TESS_BASE="https://raw.githubusercontent.com/tesseract-ocr/tessdata_best/refs/heads/main"
# NoMercy-Entertainment subs trained models
URL_TESS_BASE2="https://raw.githubusercontent.com/NoMercy-Entertainment/nomercy-tesseract/refs/heads/master/tessdata"
URL_TESS_SCRIPT="https://raw.githubusercontent.com/tesseract-ocr/tessdata_best/refs/heads/main/script"
# OpenVINO (ESPCN)
URL_VINO_BASE="https://storage.openvinotoolkit.org/repositories/open_model_zoo/2023.0/models_bin/1/single-image-super-resolution-1033/FP32"
# URL_OV_BASE2="https://storage.openvinotoolkit.org/repositories/open_model_zoo/2023.0/models_bin/1/single-image-super-resolution-1033/FP16"
# LibTorch (EDSR)
URL_TORCH_EDSR="https://github.com/pytorch/examples/raw/main/super_resolution/model.pth"
# APPLE AUDIOTOOLBOX
QTFILES_URL="https://github.com/AnimMouse/QTFiles/releases/download/v12.13.9.1/QTfiles64.7z"
# Whisper
URL_WHISPER_MODELS="https://github.com/NoMercy-Entertainment/nomercy-whisper-models"

# =========================================================

set -e

# Loading functions
source util/dl_functions.sh

ASSETS_DIR="${1:-${ASSETS_DIR}}"
FFMPEG_SOURCE_DIR="${2:-$FFMPEG_SOURCE_DIR}"

# Just in case, restore the path if FFMPEG_SOURCE_DIR suddenly turns out to be empty
if [[ -z "${FFMPEG_SOURCE_DIR:-}" ]]; then
    if [[ -d "${ROOT_DIR}/ffbuild/ffmpeg" ]]; then
        FFMPEG_SOURCE_DIR="${ROOT_DIR}/ffbuild/ffmpeg"
    elif [[ -d "./ffbuild/ffmpeg" ]]; then
        FFMPEG_SOURCE_DIR="$(pwd)/ffbuild/ffmpeg"
    else
        FFMPEG_SOURCE_DIR="."
    fi
fi

mkdir -p "${ASSETS_DIR}" "${FFBUILD_PREFIX}/bin"

# ASSETS_DIR is ".../bin/assets", go up 2 levels to get the root of the package
if [[ -z "${PKG_DIR}" && -n "${ASSETS_DIR}" ]]; then
    PKG_DIR=$(dirname $(dirname "${ASSETS_DIR}"))
fi

if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
    log_debug "${DIRS_MARK} FFmpeg source directory:\n${FFMPEG_SOURCE_DIR}"
    log_debug "${DIRS_MARK} FFmpeg assets directory:\n${ASSETS_DIR}"
    log_debug "${DIRS_MARK} FFmpeg package directory:\n${PKG_DIR}"
fi

# =================
# ASSET COLLECTION
# =================

# Copy the license BEFORE packaging
log_info "${SYNC_MARK} Adding licenses to package..."
LICENSE_FILES=("COPYING.GPLv3" "COPYING.LGPLv3" "LICENSE.md")
for lic in "${LICENSE_FILES[@]}"; do
    # Form the full absolute path to the license file
    FULL_LIC_PATH="${FFMPEG_SOURCE_DIR}/${lic}"

    if [[ -f "$FULL_LIC_PATH" ]]; then
        # Copy the file to the root of the archive (${PKG_DIR})
        cp ${OP_VERB} "$FULL_LIC_PATH" "${PKG_DIR}/"
        log_info "${CHECK_MARK} License bundled successfully from ${FFMPEG_SOURCE_DIR}: $lic"
    else
        # If not found it in main folder, look in the current working directory
        if [[ -f "./$lic" ]]; then
            cp ${OP_VERB} "./$lic" "${PKG_DIR}/"
            log_info "${CHECK_MARK} License bundled from current dir: $lic"
        else
            log_error "License file not found anywhere: $lic (Checked path: $FULL_LIC_PATH)"
        fi
    fi
done

# Plugins are in lib/frei0r-1, but to work on Windows they must be in bin/frei0r-1
if [[ -d "${FFBUILD_PREFIX}/lib/frei0r-1" ]]; then
    log_info "${SYNC_MARK} Collecting frei0r plugins..."
    mkdir -p "${PKG_DIR}/bin/frei0r-1"
    find "${FFBUILD_PREFIX}/lib/frei0r-1" -name "*.dll" -exec cp ${OP_VERB} {} "${PKG_DIR}/bin/frei0r-1/" \; || true
else
    log_warn "Frei0r plugins not found in ${FFBUILD_PREFIX}/lib/frei0r-1"
fi

# pocketsphinx models
if [[ -d "${FFBUILD_PREFIX}/share/pocketsphinx" ]]; then
    log_info "${SYNC_MARK} Collecting pocketsphinx models..."
    mkdir -p "${ASSETS_DIR}/pocketsphinx"
    cp -${OP_V}r "${FFBUILD_PREFIX}/share/pocketsphinx" "${ASSETS_DIR}/"
else
    log_warn "Pocketsphinx models not found in ${FFBUILD_PREFIX}/share/pocketsphinx"
fi

# Opencv models
if [[ -d "${FFBUILD_PREFIX}/share/opencv4" ]]; then
    log_info "${SYNC_MARK} Collecting OpenCV models..."
    mkdir -p "${ASSETS_DIR}/opencv4"/{haarcascades,lbpcascades}
    cp -${OP_V}r "${FFBUILD_PREFIX}/share/opencv4" "${ASSETS_DIR}/"
else
    log_warn "OpenCV models not found in ${FFBUILD_PREFIX}/share/opencv4"
fi

# nnedi3 plugin
if [[ -f "${FFBUILD_PREFIX}/lib/libvsznedi3.dll" ]]; then
    log_info "${SYNC_MARK} Moving nnedi3 plugin..."
    cp ${OP_VERB} "${FFBUILD_PREFIX}/lib/libvsznedi3.dll" "${PKG_DIR}/bin/libvsznedi3.dll"
elif [[ -f "${FFBUILD_PREFIX}/lib/libznedi3.a" ]]; then
    log_info "Found static libznedi3.a instead of libvsznedi3.dll in ${FFBUILD_PREFIX}/lib"
else
    log_warn "nnedi3 plugin not found in ${FFBUILD_PREFIX}/lib"
fi

# Avisynth plugins
if [[ -d "${FFBUILD_PREFIX}/lib/avisynth" ]]; then
    log_info "${SYNC_MARK} Collecting avisynth plugins..."
    find "${FFBUILD_PREFIX}/lib/avisynth" -name "*.dll" -exec cp ${OP_VERB} {} "${PKG_DIR}/bin/" \; || true
else
    log_warn "avisynth plugins not found in ${FFBUILD_PREFIX}/lib/avisynth"
fi

# lensfun plugins
if [[ -d "${FFBUILD_PREFIX}/share/lensfun" ]]; then
    log_info "${SYNC_MARK} Collecting lensfun profiles..."
    mkdir -p "${ASSETS_DIR}/lensfun/version_2"
    # find "${FFBUILD_PREFIX}/share/lensfun/version_2" -name "*.xml" -exec cp ${OP_VERB} {} "${ASSETS_DIR}/lensfun/" \; || true
    cp -${OP_V}r "${FFBUILD_PREFIX}/share/lensfun" "${ASSETS_DIR}/"
else
    log_warn "lensfun profiles not found in ${FFBUILD_PREFIX}/share/lensfun"
fi

# Vacuum all remaining DLLs from the build prefix into the binaries folder
log_info "${SYNC_MARK} Collecting external component DLLs if present..."
find "${FFBUILD_PREFIX}" -maxdepth 3 \( -name '*.dll' -o -name '*.pyd' -o -name '*.bin' -o -name '*.sign' -o -name '*.zip' \) -exec cp ${OP_VERB} {} "${PKG_DIR}/bin/" \; 2>/dev/null || true

# Auto search and packaging of MinGW system runtimes (SSP, WinPthreads, GCC)
log_info "${SYNC_MARK} Analyzing binaries for missing MinGW runtime DLLs..."
if [[ -d "${PKG_DIR}/bin" ]]; then
    # Find the sysroot and toolchain binary directory where the system DLLs live
    TOOLCHAIN_SYSROOT=$(${FFBUILD_TOOLCHAIN}-gcc -print-sysroot)
    TOOLCHAIN_BIN_DIR=$(dirname "$(${FFBUILD_TOOLCHAIN}-gcc -print-file-name=libssp.a)")

    # An array of standard MinGW runtime libraries that may be required
    RUNTIME_DLLS=("libssp-0.dll" "libwinpthread-1.dll" "libstdc++-6.dll" "libgcc_s_seh-1.dll" "libgomp-1.dll")

    # Dynamically determine the list of files for analysis
    FILES_TO_CHECK=()
    if [[ "$HAS_LIBTORCH" == "1" || "$HAS_LIBTENSORFLOW" == "1" ]]; then
        # take all .exe and .dll 
        # nullglob prevents an error if there are no files of some type
        shopt -s nullglob
        FILES_TO_CHECK=("${PKG_DIR}/bin"/*.{exe,dll})
        shopt -u nullglob
    else
        # Otherwise, strictly check only ffmpeg.exe, if it exists
        if [[ -f "${PKG_DIR}/bin/ffmpeg.exe" ]]; then
            FILES_TO_CHECK=("${PKG_DIR}/bin/ffmpeg.exe")
        fi
    fi

    # Run the scan only if there are files to analyze
    if [[ ${#FILES_TO_CHECK[@]} -gt 0 ]]; then
        for dll in "${RUNTIME_DLLS[@]}"; do
            # Scan the files defined above for dependencies
            if ${FFBUILD_CROSS_PREFIX}objdump -p "${FILES_TO_CHECK[@]}" 2>/dev/null | grep -q -i "$dll"; then
                # Check if we copied it earlier
                if [[ -f "${PKG_DIR}/bin/$dll" ]]; then
                    continue
                fi
                log_warn "Detected dynamic dependency: $dll. Searching toolchain directories..."
                # look for DLLs in sysroot or in the compiler folders
                FOUND_DLL=""
                if [[ -f "${TOOLCHAIN_SYSROOT}/bin/$dll" ]]; then
                    FOUND_DLL="${TOOLCHAIN_SYSROOT}/bin/$dll"
                elif [[ -f "${TOOLCHAIN_BIN_DIR}/$dll" ]]; then
                    FOUND_DLL="${TOOLCHAIN_BIN_DIR}/$dll"
                else
                    # Search throughout the entire ct-ng dir as a last resort
                    FOUND_DLL=$(find /opt/ct-ng -name "$dll" -type f -print -quit)
                fi
                if [[ -n "$FOUND_DLL" ]]; then
                    cp ${OP_VERB} "$FOUND_DLL" "${PKG_DIR}/bin/"
                    log_info "${CHECK_MARK} Successfully bundled system runtime: $dll"
                else
                    log_error "Required system runtime $dll not found in toolchain!"
                fi
            fi
        done
    else
        log_info "No targets found for runtime analysis."
    fi
fi

# Copy the build log
log_info "${SYNC_MARK} Coping build log file..."
cp ${OP_VERB} "$FFMPEG_CONFIG_LOG" "${PKG_DIR}/config.log" || true

[[ "$DEBUG_MODE" == "0" && "$GRAB_MODELS" == "1" ]] && log_info "${START_MARK} Starting AI/OCR model and conditional asset collection..."

# ==========================================
# TESSERACT PROCESSING
# ==========================================

# TESSERACT MODELS (OCR)
if [[ "$DEBUG_MODE" == "0" && "$HAS_LIBTESSERACT" == "1" && "$GRAB_MODELS" == "1" ]]; then
    log_info "${DOWN_MARK} Downloading Tesseract OCR models (tessdata_best)"
    TESS_DEST="${PKG_DIR}/bin/tessdata"
    mkdir -p "$TESS_DEST/script"

    TESS_FILES=(
# "eng.traineddata"
# "rus.traineddata"
"osd.traineddata" # Important for determining orientation
# "chi_sim.traineddata"
# "chi_sim_vert.traineddata"
# "jpn.traineddata"
# "jpn_vert.traineddata"
"pdf.ttf"
    )

    TESS_FILES2=(
"Cyrillic.traineddata"
"Japanese.traineddata"
"Japanese_vert.traineddata"
    )

    TESS_FILES3=(
"eng.traineddata"
"rus.traineddata"
"jpn.traineddata"
"jpn_vert.traineddata"
    )

    # Clean links from spaces before using
    LINK_BASE=$(echo "$URL_TESS_BASE" | tr -d ' ')
    LINK_BASE2=$(echo "$URL_TESS_BASE2" | tr -d ' ')
    LINK_SCRIPT=$(echo "$URL_TESS_SCRIPT" | tr -d ' ')

    for file in "${TESS_FILES[@]}"; do
        download_file "$LINK_BASE/$file" "$TESS_DEST/$file" ""
    done

    for file in "${TESS_FILES2[@]}"; do
        download_file "$LINK_SCRIPT/$file" "$TESS_DEST/script/$file" ""
    done

    for file in "${TESS_FILES3[@]}"; do
        download_file "$LINK_BASE2/$file" "$TESS_DEST/$file" ""
    done

    log_info "${SYNC_MARK} Coping tessdata configs..."
    if [ -d "${FFBUILD_PREFIX}/share/tessdata" ]; then
        # -a (archive) enables recursion (-r) and preserves all file permissions/structure
        # -v (verbose) shows in the logs which files are being copied
        cp -a${OP_V} "${FFBUILD_PREFIX}/share/tessdata"/* "$TESS_DEST/"
    else
        log_warn "Source tessdata configs directory not found in ${FFBUILD_PREFIX}/share/tessdata"
    fi
fi

# ==========================================
# TENSORFLOW PROCESSING
# ==========================================

# TENSORFLOW / DNN MODELS (Super Resolution)
if [[ "$DEBUG_MODE" == "0" && "$HAS_LIBTENSORFLOW" == "1" && "$GRAB_MODELS" == "1" ]]; then

    log_info "${SYNC_MARK} Collecting TensorFlow SR models from build context..."

    TARGET_MODEL_DIR="${ASSETS_DIR}/tensorflow"
    TENSOR_MODEL_DIR="${FFBUILD_PREFIX}/share/tensorflow_models"

    mkdir -p "$TARGET_MODEL_DIR"

    if [[ -d "$TENSOR_MODEL_DIR" && "$(ls -A "$TENSOR_MODEL_DIR" 2>/dev/null)" ]]; then
        cp ${OP_VERB} "$TENSOR_MODEL_DIR"/*.pb "$TARGET_MODEL_DIR/"
        log_info "${CHECK_MARK} TensorFlow SR models successfully bundled into package!"
    else
        log_error "TensorFlow SR models not found in internal storage ($TENSOR_MODEL_DIR)!"
        # exit 1
    fi
fi

# ==================================
# OPENVINO PROCESSING
# ==================================

# OPENVINO MODELS (VPP_OPENVINO)
# OpenVINO Models (ESPCN - Super Resolution x2) work via vpp_openvino
if [[ "$DEBUG_MODE" == "0" && "$HAS_LIBOPENVINO" == "1" && "$GRAB_MODELS" == "1" ]]; then

    mkdir -p "${ASSETS_DIR}/openvino"

    log_info "${DOWN_MARK} Downloading OpenVINO models..."

    LINK_VINO=$(echo "$URL_VINO_BASE" | tr -d ' ')

    download_file "$LINK_VINO/single-image-super-resolution-1033.xml" "${ASSETS_DIR}/openvino/sr_model.xml" ""
    download_file "$LINK_VINO/single-image-super-resolution-1033.bin" "${ASSETS_DIR}/openvino/sr_model.bin" ""
fi

# ==========================================
# WHISPER PROCESSING
# ==========================================

if [[ "$DEBUG_MODE" == "0" && "$HAS_WHISPER" == "1" && "$GRAB_MODELS" == "1" ]]; then

    # Valid options: base, small, medium, large-v3
    WHISPER_MODEL="${WHISPER_MODEL:-small}"

    mkdir -p "${ASSETS_DIR}/whisper"

    WHISPER_MODEL_DIR="${ASSETS_DIR}/whisper"

    # Getting the current release tag
    WHISPER_LATEST_TAG=$(curl -sIL -o /dev/null -w '%{url_effective}' "${URL_WHISPER_MODELS}/releases/latest" | awk -F'/' '{print $NF}')

    log_info "Whisper model version found: ${WHISPER_LATEST_TAG}"
    log_info "Selected Whisper model configuration: ${WHISPER_MODEL}"

    DOWNLOAD_SUCCESS=0

    case "${WHISPER_MODEL}" in
        base|small|medium)
            WHISPER_MODEL_FILE="ggml-${WHISPER_MODEL}.bin"
            WHISPER_DOWNLOAD_URL="${URL_WHISPER_MODELS}/releases/download/${WHISPER_LATEST_TAG}/${WHISPER_MODEL_FILE}"

            log_info "${DOWN_MARK} Downloading Whisper ${WHISPER_MODEL} model..."
            if download_file "${WHISPER_DOWNLOAD_URL}" "${WHISPER_MODEL_DIR}/${WHISPER_MODEL_FILE}" ""; then
                DOWNLOAD_SUCCESS=1
            fi
            ;;

        large-v3)
            WHISPER_MODEL_FILE="ggml-large-v3.bin"
            PART_A="${WHISPER_MODEL_FILE}.part-aa"
            PART_B="${WHISPER_MODEL_FILE}.part-ab"

            log_info "${DOWN_MARK} Downloading parts for Whisper large-v3 model..."

            mkdir -p "${TMP_DIR}/whisper_parts"

            if download_file "${URL_WHISPER_MODELS}/releases/download/${WHISPER_LATEST_TAG}/${PART_A}" "${TMP_DIR}/whisper_parts/${PART_A}" "" && \
               download_file "${URL_WHISPER_MODELS}/releases/download/${WHISPER_LATEST_TAG}/${PART_B}" "${TMP_DIR}/whisper_parts/${PART_B}" ""; then

                log_info "${BUILD_MARK} Reassembling Whisper large-v3 model from parts..."

                # Glue the parts directly into the target file
                if cat "${TMP_DIR}/whisper_parts/${PART_A}" "${TMP_DIR}/whisper_parts/${PART_B}" > "${WHISPER_MODEL_DIR}/${WHISPER_MODEL_FILE}"; then
                    DOWNLOAD_SUCCESS=1

                    rm -rf "${TMP_DIR}/whisper_parts"
                else
                    log_error "Failed to glue large-v3 model parts together!"
                fi
            else
                log_error "Failed to download all required parts for large-v3 model."
            fi
            ;;

        *)
            log_error "Unknown WHISPER_MODEL option: '${WHISPER_MODEL}'. Valid types: base, small, medium, large-v3"
            exit 1
            ;;
    esac

    if [[ ${DOWNLOAD_SUCCESS} -eq 1 ]] && [[ -s "${WHISPER_MODEL_DIR}/${WHISPER_MODEL_FILE}" ]]; then
        log_info "${CHECK_MARK} Whisper model (${WHISPER_MODEL_FILE}) successfully deployed to:\n${WHISPER_MODEL_DIR}"
    else
        log_error "Whisper model deployment verification failed!"
        # exit 1
    fi

fi

# ==========================================
# LIBTORCH PROCESSING
# ==========================================

# LIBTORCH MODELS (EDSR) Torch models for the 'sr' filter. TorchScript.
# if [[ "$HAS_LIBTORCH" == "1" ]]; then
    # log_info "${DOWN_MARK} Downloading LibTorch models..."
    # mkdir -p "${ASSETS_DIR}/torch"
    # LINK_TORCH=$(echo "$URL_TORCH_EDSR" | tr -d ' ')
    # download_file "$LINK_TORCH" "${ASSETS_DIR}/torch/edsr_x2.torch" ""
# fi

# ==========================================
# AUDIOTOOLBOX PROCESSING
# ==========================================

# APPLE AUDIOTOOLBOX DLLS (Special handling)
if [[ "$HAS_AUDIOTOOLBOX" == "1" ]]; then

    QT_DIR="${PKG_DIR}/bin/QTfiles64"
    mkdir -p "${QT_DIR}"

    log_info "${DOWN_MARK} Downloading Apple AudioToolbox DLLs..."

    if download_file "$QTFILES_URL" "qtfiles64.7z" ""; then
        log_info "${EXTR_MARK} Extracting Apple DLLs directly to package..."

        7z e qtfiles64.7z -o"${QT_DIR}" "*.dll" -y > /dev/null

        if ls "${QT_DIR}"/CoreAudioToolbox.dll >/dev/null 2>&1; then
            log_info "${CHECK_MARK} Apple AudioToolbox DLLs successfully deployed to:\n${QT_DIR}"
        else
            log_error "AudioToolbox DLLs deployment verification failed!"
        fi
        rm -f qtfiles64.7z
    else
        log_warn "Assets download failed, but continuing..."
    fi

fi

log_info "${CHECK_MARK} All models and asset collection finished for enabled components."

# Check for the presence of critical libraries (for debugging in logs)
if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
    ls -lh "${PKG_DIR}/bin/"
fi