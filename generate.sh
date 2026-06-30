#!/bin/bash

set -e
# set -xe

shopt -s globstar
cd "$(dirname "$0")"

# Забираем аргументы из workflow.yaml для локального использования
TARGET="${1:-$TARGET}"
VARIANT="${2:-$VARIANT}"

# Загружаем переменные
source util/vars.sh "$TARGET" "$VARIANT" 2>&1 || {
    echo "ERROR: vars.sh failed (TARGET=$TARGET VARIANT=$VARIANT)" >&2
    exit 1
}

CONTAINER_ROOT="${CONTAINER_ROOT:-/builder}"

# build ADDINS array based on ENV VARIABLES
ADDINS=()
ADDINS_STR=""

# Check each potential addin based on ENV variables
if [[ "$USE_LTO" == "1" ]] && [[ -f "${ADDINS_DIR}/lto.sh" ]]; then
    ADDINS+=("lto")
    ADDINS_STR="${ADDINS_STR}${ADDINS_STR:+-}lto"
    log_info "${XCLAM_MARK} LTO addin enabled."
fi

if [[ "$USE_AVX512" == "1" ]] && [[ -f "${ADDINS_DIR}/avx512.sh" ]]; then
    ADDINS+=("avx512")
    ADDINS_STR="${ADDINS_STR}${ADDINS_STR:+-}avx512"
    log_info "${XCLAM_MARK} AVX512 addin enabled."
fi

if [[ "$PREFER_SHARED" == "1" ]] && [[ -f "${ADDINS_DIR}/shared.sh" ]]; then
    ADDINS+=("shared")
    ADDINS_STR="${ADDINS_STR}${ADDINS_STR:+-}shared"
    log_info "${XCLAM_MARK} SHARED addin enabled."
fi

# Allow custom addins via CUSTOM_ADDINS env var (space-separated)
if [[ -n "$CUSTOM_ADDINS" ]]; then
    for addin in $CUSTOM_ADDINS; do
        addin_path="${ADDINS_DIR}/${addin}.sh"
        if [[ -f "$addin_path" ]]; then
            ADDINS+=("$addin")
            ADDINS_STR="${ADDINS_STR}${ADDINS_STR:+-}${addin}"
            log_info "${XCLAM_MARK} Custom addin enabled: $addin"
        else
            log_warn "Custom addin not found at $addin_path"
            # exit 1
        fi
    done
fi
export ADDINS ADDINS_STR

log_info "${CHECK_MARK} Active addins: ${GREY_B}${ADDINS_STR:-none}${NC}"

# other early indications for "Run Download and Generate" build stage
[[ "$DEDUPE_FLAGS" == "1" ]]   && log_info "${XCLAM_MARK} Extended deduplication for stages collected LIBS is enabled!"
[[ "$FFMPEG_PATCHES" == "1" ]] && log_info "${XCLAM_MARK} Custom patches for FFmpeg are activated!"
[[ "$SAFE_CONFIGURE" == "1" ]] && log_info "${XCLAM_MARK} Safe FFmpeg flags configuration is enabled!"
[[ "$SKIP_FFMPEG" == "1" ]]    && log_info "${XCLAM_MARK} Component test mode activated! FFmpeg compilation will be skipped."
[[ "$USE_OPENMP" == "1" ]]     && log_info "${XCLAM_MARK} Open Multi-Processing runtime for shared-memory parallel programming is enabled!"
[[ "$SHADERC_UPDATE" == "1" ]] && log_info "${XCLAM_MARK} Shaderc dependencies will be updated from the local DEPS file."
[[ "$OLDER_FFNV" == "1" ]]     && log_info "${XCLAM_MARK} FFNVcodec sdk version 8.1 will be installed."
[[ "$DIR_NUMBERS" == "1" ]]    && log_info "${XCLAM_MARK} Script collector will ignore numbering of folders."
[[ "$BUILD_VINO" == "1" ]]     && log_info "${XCLAM_MARK} Will build OpenVINO from source. You'll gonna carry that weight..."
[[ "$USE_TENSORFLOW" == "1" ]] && log_info "${XCLAM_MARK} TensorFlow component is enabled."
[[ "$USE_LIBTORCH" == "1" ]]   && log_info "${XCLAM_MARK} LibTorch component is enabled."
[[ "$USE_ASAN" == "1" ]]       && log_info "${XCLAM_MARK} Address Sanitizer (ASAN) is enabled."
[[ "$DEBUG_MODE" == "1" ]]     && log_info "${XCLAM_MARK} Debug mode is enabled. Stripping will be disabled. Binary sizes will increase."
if [[ "$SEC_PROTO" == "openssl"  ]]; then
    log_info "${XCLAM_MARK} OpenSSL secure transport protocol is chosen."
elif [[ "$SEC_PROTO" == "gnutls"  ]]; then
    log_info "${XCLAM_MARK} GnuTLS secure transport protocol is chosen."
elif [[ "$SEC_PROTO" == "mbedtls"  ]]; then
    log_info "${XCLAM_MARK} mbedTLS secure transport protocol is chosen."
elif [[ "$SEC_PROTO" == "schannel"  ]]; then
    log_info "${XCLAM_MARK} SChannel secure transport protocol is chosen."
fi

echo -n "" > Dockerfile # Явно очищаем файл перед началом записи
to_df() { echo "$*" >> Dockerfile; }

# Making ENV from workflow avaliable inside Docker 
# Объединяем все ENV в одну команду для оптимизации слоев
COMMON_ENV="ENV TARGET=\"$TARGET\" VARIANT=\"$VARIANT\" REPO=\"$REPO\" ADDINS_STR=\"$ADDINS_STR\" \\
    ROOT_DIR=\"${CONTAINER_ROOT}\" \\
    CACHE_DIR=\"${CONTAINER_ROOT}/.cache/downloads\" \\
    CCACHE_DIR=\"${CCACHE_DIR}\" \\
    CCACHE_MAXSIZE=\"${CCACHE_MAXSIZE:-2G}\" \\
    CCACHE_COMPRESS=\"${CCACHE_COMPRESS:-1}\" \\
    CCACHE_COMPRESSLEVEL=\"${CCACHE_COMPRESSLEVEL:-6}\" \\
    CCACHE_NOHASHDIR=\"${CCACHE_NOHASHDIR:-1}\" \\
    CCACHE_DEPEND=\"${CCACHE_DEPEND:-1}\" \\
    CCACHE_COMPILERCHECK=\"${CCACHE_COMPILERCHECK:-none}\" \\
    CCACHE_NLEVELS=\"${CCACHE_NLEVELS:-4}\" \\
    CCACHE_SLOPPINESS=\"${CCACHE_SLOPPINESS}\" \\
    FFMPEG_DIR=\"${CONTAINER_ROOT}/.cache/ffmpeg\" \\
    FFMPEG_BUILD_ROOT=\"${CONTAINER_ROOT}/ffbuild\" \\
    FFMPEG_SOURCE_DIR=\"${CONTAINER_ROOT}/ffbuild/ffmpeg\" \\
    FFMPEG_PKG_ROOT=\"${CONTAINER_ROOT}/ffbuild/pkgroot\" \\
    FFMPEG_CONFIG_LOG=\"${CONTAINER_ROOT}/ffbuild/ffmpeg/ffbuild/config.log\" \\
    FFMPEG_HASH_FILE=\"${CONTAINER_ROOT}/.cache/ffmpeg/.current_commit\" \\
    PATCHES_DIR=\"${CONTAINER_ROOT}/patches\" \\
    SCRIPTS_DIR=\"${CONTAINER_ROOT}/scripts.d\" \\
    TMP_DIR=\"${CONTAINER_ROOT}/.cache/tmp\" \\
    UTIL_DIR=\"${CONTAINER_ROOT}/util\" \\
    VARIANTS_DIR=\"${CONTAINER_ROOT}/variants\" \\
    FFBUILD_VERBOSE=\"${FFBUILD_VERBOSE}\" \\
    FFMPEG_REPO=\"${FFMPEG_REPO}\" \\
    FFMPEG_BRANCH=\"${FFMPEG_BRANCH}\" \\
    DEBUG_NO_HASH=\"${DEBUG_NO_HASH}\" \\
    DEDUPE_FLAGS=\"${DEDUPE_FLAGS}\" \\
    SAFE_CONFIGURE=\"${SAFE_CONFIGURE}\" \\
    FFMPEG_PATCHES=\"${FFMPEG_PATCHES}\" \\
    ONLY_STAGE=\"${ONLY_STAGE}\" \\
    USE_OPENMP=\"${USE_OPENMP}\" \\
    USE_WINE=\"${USE_WINE}\" \\
    USE_AVX512=\"${USE_AVX512}\" \\
    PREFER_SHARED=\"${PREFER_SHARED:-0}\" \\
    OLDER_FFNV=\"${OLDER_FFNV}\" \\
    BUILD_VINO=\"${BUILD_VINO}\" \\
    DIR_NUMBERS=\"${DIR_NUMBERS}\" \\
    USE_LTO=\"${USE_LTO}\" \\
    LOG_RAW_SYMB=\"${LOG_RAW_SYMB}\" \\
    LOG_SIZES=\"${LOG_SIZES}\" \\
    LOG_FF_SIZES=\"${LOG_FF_SIZES}\" \\
    LOG_INSTALLED=\"${LOG_INSTALLED}\" \\
    USE_TENSORFLOW=\"${USE_TENSORFLOW}\" \\
    USE_LIBTORCH=\"${USE_LIBTORCH}\" \\
    USE_ASAN=\"${USE_ASAN}\" \\
    DEBUG_MODE=\"${DEBUG_MODE}\" \\
    SEC_PROTO=\"${SEC_PROTO}\" \\
    CPU_ARCH=\"${CPU_ARCH:-broadwell}\" \\
    CPU_TUNE=\"${CPU_TUNE:-broadwell}\" \\
    DLL_PRESERVE_LIST=\"${DLL_PRESERVE_LIST}\" \\
    GIT_PRESERVE_LIST=\"${GIT_PRESERVE_LIST}\""

to_df "FROM ${TARGET_IMAGE} AS components_build"
to_df "SHELL [\"/bin/bash\", \"-l\", \"-c\"]"
to_df "$COMMON_ENV"
to_df "WORKDIR ${CONTAINER_ROOT}"
to_df "COPY --chmod=755 util/run_stage.sh /usr/bin/run_stage"

if [[ "${USE_TENSORFLOW}" == "1" ]]; then
    to_df "RUN --mount=type=bind,from=tf_models_ctx,target=/tmp/tf_ctx \\"
    to_df "    mkdir -p /opt/ffbuild/share/tensorflow_models && \\"
    to_df "    cp -fRP /tmp/tf_ctx/. /opt/ffbuild/share/tensorflow_models/"
fi

# Очищаем содержимое перед хешированием:
# 1. Берем только переменные, влияющие на бинарный код
# 2. Удаляем комментарии и лишние пробелы
# 3. Сортируем (чтобы порядок строк в файле не влиял на хеш)
ENV_HASH=$({
    grep -E "^(CFLAGS|CXXFLAGS|LDFLAGS|CPPFLAGS|RUSTFLAGS|BASE_CFLAGS|LIBS)=" "$UTIL_DIR/vars.sh" \
        | grep -v "^#" \
        | grep -v "^\s*$" \
        | sed 's/[[:space:]]\+/ /g' \
        | sort

    echo "TARGET=$TARGET"
    echo "CPU_ARCH=$CPU_ARCH"
    echo "VARIANT=$VARIANT"
    echo "USE_LTO=$USE_LTO"
    echo "USE_AVX512=$USE_AVX512"
    echo "USE_OPENMP=$USE_OPENMP"
    echo "FFBUILD_PREFIX=$FFBUILD_PREFIX"
} | sha256sum | cut -c1-8)

# Global Logic Hash: Changes if run_stage.sh or the internal functions of vars.sh change.
RUN_STAGE_HASH=$(sha256sum $UTIL_DIR/run_stage.sh | cut -c1-8 | tr -d '\n\r')
VARS_LOGIC_HASH=$(grep -E "^(ffbuild_|stage_vars|get_stage_hash)" $UTIL_DIR/vars.sh | sha256sum | cut -c1-8 | tr -d '\n\r')
LOGIC_HASH="${RUN_STAGE_HASH}_${VARS_LOGIC_HASH}"

# A static HASH ensures that when a variable in vars.sh is changed, all subsequent RUNs will NOT be rebuilt.
if [[ "$DEBUG_NO_HASH" == "1" ]]; then
    log_warn "Hashes are now hardcoded to preserve Docker cache."
    ENV_HASH="env_static"
    LOGIC_HASH="logic_static"
fi

# кумулятивный хэш цепочки для инвалидации последующих слоев
CHAIN_HASH="${ENV_HASH}_${LOGIC_HASH}"

# Сборка и фильтрация активных скриптов
if [[ "$DIR_NUMBERS" == "1" ]]; then
    # учитывать нумерацию только базового имени
    mapfile -t SCRIPTS < <(find scripts.d -name "*.sh" -printf "%f\t%p\n" | sort -n | cut -f2)
else
    # Учитывать нумерацию в папках
    mapfile -t SCRIPTS < <(find scripts.d -name "*.sh" | sort)
fi

active_scripts=()
for STAGE in "${SCRIPTS[@]}"; do
    # Фильтрация по регулярному выражению ONLY_STAGE
    # Match against basename only, with anchored component name
    STAGE_BASE="$(basename "$STAGE" .sh)"
    if [[ -n "$ONLY_STAGE" ]]; then
        matched=0
        IFS='|' read -ra _patterns <<< "$ONLY_STAGE"
        for pattern in "${_patterns[@]}"; do
            pattern="${pattern%.sh// /}" # trim spaces
            # Match full basename OR suffix component name
            if [[ "$STAGE_BASE" == "$pattern" ]] || \
               [[ "$STAGE_BASE" == *"-${pattern}" ]] || \
               [[ "$STAGE_BASE" =~ $pattern ]]; then
                matched=1; break
            fi
        done
        [[ $matched -eq 0 ]] && continue
    fi
    # Проверка на принудительное отключение внутри скрипта
    # Source in a clean subshell and call ffbuild_enabled
    if ! (
        source "$ROOT_DIR/util/vars.sh" "$TARGET" "$VARIANT" 2>/dev/null
        source "$STAGE" 2>/dev/null
        ffbuild_enabled
    ) 2>/dev/null; then
        log_info "${XCLAM_MARK} Skipping disabled stage: $(basename "$STAGE")"
        continue
    fi
    active_scripts+=("$STAGE")
done

if [[ ${#active_scripts[@]} -eq 0 ]]; then
    log_warn "No active scripts matched ONLY_STAGE=${ONLY_STAGE}"
fi

# Генерируем блоки RUN для каждой стадии
for STAGE in "${active_scripts[@]}"; do
    unset STAGE_HASH STAGENAME COMPONENT_NAME STAGE_CACHE_FILE STAGE_LATEST_LINK
    eval "$(stage_vars "$STAGE")"
    # Гранулярный поиск патчей
    # Для библиотек ищем в patches/zlib/ и т.д.
    PATCH_PATH="${PATCHES_DIR}/${COMPONENT_NAME}"
    if [[ ! -d "${PATCH_PATH}" ]] && [[ -d "${PATCHES_DIR}/${COMPONENT_NAME%%-*}" ]]; then
        log_debug "No patches for $COMPONENT_NAME (base patches exist at ${COMPONENT_NAME%%-*})"
    fi
    # Для FFmpeg ищем в patches/ffmpeg/master/ (или другой ветке)
    [[ "${COMPONENT_NAME}" == "ffmpeg" ]] && PATCH_PATH="${PATCHES_DIR}/ffmpeg/${FFMPEG_BRANCH}"
    # Считаем хеш только если папка существует, иначе "none"
    if [[ -d "${PATCH_PATH}" ]]; then
        PATCH_HASH=$(find "${PATCH_PATH}" -type f -exec md5sum {} + | sort | md5sum | cut -c1-8)
    else
        PATCH_HASH="none"
    fi
    # Combine them into a unique ID for this specific layer
    # If you change a log message in vars.sh, ENV_HASH stays the same -> NO REBUILD.
    # If you change CFLAGS in vars.sh, ENV_HASH changes -> GLOBAL REBUILD.
    # LAYER_ID="E:${ENV_HASH}_L:${LOGIC_HASH}_S:${STAGE_HASH}_P:${PATCH_HASH}"

    # Добавляем хэш текущего компонента в кумулятивную цепочку
    CHAIN_HASH=$(echo "${CHAIN_HASH}_${STAGE_HASH}_${PATCH_HASH}" | sha256sum | cut -c1-16)
    LAYER_ID="CH:${CHAIN_HASH}"

    to_df "# Component: $STAGENAME | LayerID: $LAYER_ID"
    to_df "ARG CACHE_BYPASS_${STAGENAME}=\"${LAYER_ID}\""

    to_df "RUN --mount=type=cache,id=ccache-${TARGET},target=/root/.cache/ccache \\"
    to_df "    --mount=type=bind,from=cache_downloads_ctx,source=/,target=${CONTAINER_ROOT}/.cache/downloads,ro \\"
    to_df "    --mount=type=bind,from=cache_ffmpeg_ctx,target=${CONTAINER_ROOT}/.cache/ffmpeg \\"
    to_df "    --mount=type=bind,source=scripts.d,target=${CONTAINER_ROOT}/scripts.d \\"
    to_df "    --mount=type=bind,source=util,target=${CONTAINER_ROOT}/util \\"
    to_df "    --mount=type=bind,source=patches,target=${CONTAINER_ROOT}/patches \\"
    to_df "    --mount=type=bind,source=variants,target=${CONTAINER_ROOT}/variants \\"
    to_df "    --mount=type=bind,source=addins,target=${CONTAINER_ROOT}/addins \\"
    to_df "    export _H=\${CACHE_BYPASS_${STAGENAME}} && . ${CONTAINER_ROOT}/util/vars.sh \"${TARGET}\" \"${VARIANT}\" && run_stage ${CONTAINER_ROOT}/${STAGE}"
done

# FINAL FFMPEG BUILD STAGE
to_df "FROM ${TARGET_IMAGE} AS final_build"
to_df "SHELL [\"/bin/bash\", \"-l\", \"-c\"]"
to_df "WORKDIR ${CONTAINER_ROOT}"
to_df "COPY --from=components_build ${FFBUILD_PREFIX}/ ${FFBUILD_PREFIX}/"
if [[ "${USE_TENSORFLOW}" == "1" ]]; then
    to_df "COPY --from=components_build /opt/ffbuild/share/tensorflow_models/ /opt/ffbuild/share/tensorflow_models/"
fi
to_df "$COMMON_ENV"
to_df "COPY build.sh ./build.sh"
to_df "COPY addins ./addins"
to_df "COPY patches ./patches"
to_df "COPY util ./util"
to_df "COPY variants ./variants"

if [[ "${SKIP_FFMPEG}" == "1" ]]; then
    to_df "RUN mkdir -p ${FFBUILD_DESTDIR} && \\"
    to_df "    echo 'Components built successfully' > ${FFBUILD_DESTDIR}/BUILD_SUCCESS"
else
    to_df "RUN --mount=type=cache,id=ccache-${TARGET},target=/root/.cache/ccache \\"
    to_df "    --mount=type=bind,from=cache_ffmpeg_ctx,source=/,target=/builder/.cache/ffmpeg,rw \\"
    to_df "    ./build.sh \"$TARGET\" \"$VARIANT\""
fi

# ARTIFACTS COLLECTOR STAGE
to_df ""
to_df "FROM scratch AS artifacts"
to_df "COPY --from=final_build ${FFBUILD_DESTDIR}/ ."
