#!/bin/bash

set -e

TARGET="${1:-win64}"
VARIANT="${2:-nonfree}"

# Загружаем базовые переменные окружения на хосте
source util/vars.sh "$TARGET" "$VARIANT" 2>&1 || {
    echo "Failed to source vars.sh"
    exit 1
}

# Подготовка локального sysroot хоста
SYSROOT_DIR="${ROOT_DIR}/.cache/sysroot"
mkdir -p "$SYSROOT_DIR/opt/ffbuild/config_vars"
mkdir -p "${ROOT_DIR}/.cache/ccache"

# Автоматически определяем имя репозитория в нижнем регистре для GHCR
REPO_LC="${GITHUB_REPOSITORY,,}"
REGISTRY="ghcr.io"
BASE_CACHE_IMAGE="${REGISTRY}/${REPO_LC}/component-cache"
TARGET_IMAGE="${REGISTRY}/${REPO_LC}/base-win64:latest"

log_info "${TARGET_MARK} Starting Permanent OCI-Registry Build Pipeline..."

# Находим активные скрипты (логика полностью скопирована из вашего generate.sh)
if [[ "$DIR_NUMBERS" == "1" ]]; then
    mapfile -t SCRIPTS < <(find scripts.d -name "*.sh" -printf "%f\t%p\n" | sort -n | cut -f2)
else
    mapfile -t SCRIPTS < <(find scripts.d -name "*.sh" | sort)
fi

ACTIVE_SCRIPTS=()
for STAGE in "${SCRIPTS[@]}"; do
    STAGE_BASE="$(basename "$STAGE" .sh)"
    if [[ -n "$ONLY_STAGE" ]]; then
        matched=0
        IFS='|' read -ra _patterns <<< "$ONLY_STAGE"
        for pattern in "${_patterns[@]}"; do
            if [[ "$STAGE_BASE" =~ $pattern ]]; then matched=1; break; fi
        done
        [[ $matched -eq 0 ]] && continue
    fi
    # Проверка ffbuild_enabled
    if ! ( source "util/vars.sh" "$TARGET" "$VARIANT" 2>/dev/null; source "$STAGE" 2>/dev/null; ffbuild_enabled ) 2>/dev/null; then
        continue
    fi
    ACTIVE_SCRIPTS+=("$STAGE")
done

log_info "Pipeline loaded with ${#ACTIVE_SCRIPTS[@]} active components."

# Инициализируем базовый хэш цепочки (чтобы изменение переменных окружения сбрасывало кэш)
PREVIOUS_CHAIN_HASH=$({
    grep "^export CFLAGS=" util/vars.sh || true
    grep "^export CXXFLAGS=" util/vars.sh || true
    grep "^export LDFLAGS=" util/vars.sh || true
    echo "TARGET=$TARGET"
    echo "CPU_ARCH=$CPU_ARCH"
} | sha256sum | cut -c1-16)

# Перебираем компоненты последовательно
for STAGE in "${ACTIVE_SCRIPTS[@]}"; do
    unset STAGE_HASH STAGENAME COMPONENT_NAME
    eval "$(stage_vars "$STAGE")"

    # Вычисляем хэш патчей
    PATCH_PATH="${PATCHES_DIR}/${COMPONENT_NAME}"
    [[ "${COMPONENT_NAME}" == "ffmpeg" ]] && PATCH_PATH="${PATCHES_DIR}/ffmpeg/${FFMPEG_BRANCH}"
    PATCH_HASH="none"
    if [[ -d "${PATCH_PATH}" ]]; then
        PATCH_HASH=$(find "${PATCH_PATH}" -type f -exec md5sum {} + | sort | md5sum | cut -c1-8)
    fi

    # КУМУЛЯТИВНЫЙ ХЭШ: зависит от себя, патчей и ВСЕЙ цепочки до него
    COMBINED_HASH=$(echo "${PREVIOUS_CHAIN_HASH}_S:${STAGE_HASH}_P:${PATCH_HASH}" | sha256sum | cut -c1-16)
    PREVIOUS_CHAIN_HASH="$COMBINED_HASH"

    # Имя OCI-образа для кэша этого конкретного компонента
    COMPONENT_IMAGE="${BASE_CACHE_IMAGE}/${STAGENAME}:${COMBINED_HASH}"

    log_info "Processing component: ${BLUE_B}${STAGENAME}${NC} | Pipeline-Hash: ${GREY_B}${COMBINED_HASH}${NC}"

    # ПРОВЕРКА CACHE HIT В GHCR
    # Принудительный ребилд (REBUILD_COMPONENTS=1) пропускает этот шаг
    if [[ "${REBUILD_COMPONENTS}" != "1" ]] && docker manifest inspect "$COMPONENT_IMAGE" >/dev/null 2>&1; then
        log_info "${CACHE_MARK} Cache HIT in GHCR! Extracting OCI artifact layers..."
        # Создаем контейнер-пустышку и копируем файлы напрямую в sysroot хоста
        docker create --name "temp_extract_${STAGENAME}" "$COMPONENT_IMAGE" ""
        docker cp "temp_extract_${STAGENAME}:/opt/ffbuild" "$SYSROOT_DIR/opt/"
        docker rm "temp_extract_${STAGENAME}"
        continue
    fi

    # CACHE MISS ЗАПУСК КОМПИЛЯЦИИ В DOCKER
    log_info "${BUILD_MARK} Cache MISS. Launching Docker compiler toolchain..."

    # Создаем папку config_vars на хосте перед запуском, чтобы Docker не создал её от имени root
    mkdir -p "${SYSROOT_DIR}/opt/ffbuild/config_vars"

    docker run --rm \
        --workdir "${CONTAINER_ROOT}" \
        -v "${ROOT_DIR}:${CONTAINER_ROOT}" \
        -v "${SYSROOT_DIR}/opt/ffbuild:/opt/ffbuild" \
        -v "${SYSROOT_DIR}/opt/ffbuild/config_vars:/opt/ffbuild/config_vars:rw" \
        -v "${ROOT_DIR}/.cache/downloads:${CONTAINER_ROOT}/.cache/downloads:rw" \
        -v "${ROOT_DIR}/.cache/ccache:/root/.cache/ccache:rw" \
        -e TARGET="$TARGET" \
        -e VARIANT="$VARIANT" \
        -e ADDINS_STR="$ADDINS_STR" \
        -e CPU_ARCH="$CPU_ARCH" \
        -e CPU_TUNE="$CPU_TUNE" \
        -e DEDUPE_FLAGS="$DEDUPE_FLAGS" \
        -e DEBUG_NO_HASH="$DEBUG_NO_HASH" \
        -e REBUILD_COMPONENTS="$REBUILD_COMPONENTS" \
        -e FFMPEG_PATCHES="$FFMPEG_PATCHES" \
        -e SKIP_FFMPEG="$SKIP_FFMPEG" \
        -e SAFE_CONFIGURE="$SAFE_CONFIGURE" \
        -e USE_AVX512="$USE_AVX512" \
        -e USE_LTO="$USE_LTO" \
        -e USE_WINE="$USE_WINE" \
        -e USE_OPENMP="$USE_OPENMP" \
        -e SHADERC_UPDATE="$SHADERC_UPDATE" \
        -e CLEAN_INACTIVE="$CLEAN_INACTIVE" \
        -e PREFER_SHARED="$PREFER_SHARED" \
        -e OLDER_FFNV="$OLDER_FFNV" \
        -e DIR_NUMBERS="$DIR_NUMBERS" \
        -e BUILD_VINO="$BUILD_VINO" \
        -e FFMPEG_REPO="$FFMPEG_REPO" \
        -e FFMPEG_BRANCH="$FFMPEG_BRANCH" \
        -e ONLY_STAGE="$ONLY_STAGE" \
        -e FFBUILD_VERBOSE="$FFBUILD_VERBOSE" \
        -e GIT_PRESERVE_LIST="$GIT_PRESERVE_LIST" \
        -e DLL_PRESERVE_LIST="$DLL_PRESERVE_LIST" \
        -e LIB_PRESERVE_LIST="$LIB_PRESERVE_LIST" \
        -e STRIP_EXCLUDE_LIST="$STRIP_EXCLUDE_LIST" \
        "${TARGET_IMAGE}" \
        /bin/bash -l -c "./util/run_stage.sh ${CONTAINER_ROOT}/${STAGE}"

    # УПАКОВКА И ПУШ КЭШ-СЛОЯ В GHCR ПОСЛЕ УСПЕШНОЙ СБОРКИ
    log_info "${SAVE_MARK} Packaging and pushing OCI cache layer to GHCR..."

    # Генерируем временный микро-Dockerfile на лету
    cat <<EOF > "$SYSROOT_DIR/Dockerfile.component.cache"
FROM scratch
COPY opt/ffbuild /opt/ffbuild
EOF

    # Запускаем сборку, передавая в качестве контекста КОРЕНЬ репозитория ($ROOT_DIR).
    # Флаг --provenance=false отключает генерацию избыточных метаданных BuildKit, 
    # которые часто приводят к ошибкам 'unknown blob' при пуше scratch-контейнеров.
    docker build \
        --provenance=false \
        -t "$COMPONENT_IMAGE" \
        -f "$SYSROOT_DIR/Dockerfile.component.cache" "$SYSROOT_DIR"

    # Отправляем образ в реестр пакетов GitHub
    docker push "$COMPONENT_IMAGE"

    # Удаляем временный Dockerfile и локальный образ
    rm -f "$SYSROOT_DIR/Dockerfile.component.cache"
    docker rmi "$COMPONENT_IMAGE" || true
    docker builder prune --filter type=exec.cachemount --force || true
done

log_info "${CHECK_MARK} All intermediate pipeline components synchronized with GHCR successfully!"
