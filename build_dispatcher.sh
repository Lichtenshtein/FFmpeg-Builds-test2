#!/bin/bash

# build_dispatcher.sh
set -e

TARGET="${1:-win64}"
VARIANT="${2:-nonfree}"

# Загружаем базовые переменные окружения на хосте
source util/vars.sh "$TARGET" "$VARIANT" 2>&1 || {
    echo "Failed to source vars.sh"
    exit 1
}

COMPONENTS_CACHE_DIR="${ROOT_DIR}/.cache/components"
SYSROOT_DIR="${ROOT_DIR}/.cache/sysroot"
mkdir -p "$COMPONENTS_CACHE_DIR" "$SYSROOT_DIR/opt/ffbuild"

# Сброс кэша цепочки
if [[ "${REBUILD_COMPONENTS}" == "1" ]]; then
    log_warn "${BROOM_MARK} REBUILD_COMPONENTS is active! Wiping out old pipeline cache..."
    rm -rf "${COMPONENTS_CACHE_DIR:?}"/*
    rm -rf "${SYSROOT_DIR:?}"/opt/ffbuild/*
    mkdir -p "$SYSROOT_DIR/opt/ffbuild"
fi

log_info "${TARGET_MARK} Starting Incremental Build Dispatcher for ${TARGET}-${VARIANT}"

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
    COMPONENT_CACHE_FILE="${COMPONENTS_CACHE_DIR}/${STAGENAME}_${COMBINED_HASH}.tar.zst"

    # Этот хэш становится базой для следующего компонента (эффект домино)
    PREVIOUS_CHAIN_HASH="$COMBINED_HASH"

    log_info "Component: ${BLUE_B}${STAGENAME}${NC} | Pipeline-Hash: ${GREY_B}${COMBINED_HASH}${NC}"

    # Если сборка этой цепочки уже выполнялась
    if [[ -f "$COMPONENT_CACHE_FILE" ]]; then
        log_info "${CACHE_MARK} Cache HIT. Extracting pre-built sysroot state..."
        tar -I 'zstd -d -T0' -xaf "$COMPONENT_CACHE_FILE" -C "$SYSROOT_DIR/"
        continue
    fi

    log_info "${BUILD_MARK} Cache MISS. Compiling ${STAGENAME} inside Docker toolchain..."

    # Запускаем контейнер для выполнения ровно ОДНОГО скрипта.
    # Мы монтируем текущее состояние хост-папки sysroot в контейнерный /opt/ffbuild.
    # Папка исходников .cache/downloads мантируется read-write, как и требовал run_stage.sh.
    docker run --rm \
        -v "${ROOT_DIR}:${CONTAINER_ROOT}" \
        -v "${SYSROOT_DIR}/opt/ffbuild:/opt/ffbuild" \
        -v "${ROOT_DIR}/.cache/downloads:${CONTAINER_ROOT}/.cache/downloads:rw" \
        --env-file <(env | grep -E '^(TARGET|VARIANT|CPU_|FFBUILD_|USE_|FFMPEG_|DEBUG_|DEDUPE_|SAFE_|ONLY_|DLL_|GIT_|STRIP_|OLDER_)') \
        "ghcr.io/${GITHUB_REPOSITORY,,}/base-${TARGET}:latest" \
        /bin/bash -l -c "${CONTAINER_ROOT}/util/run_stage.sh ${CONTAINER_ROOT}/${STAGE}"

    # После успешной сборки фиксируем, что именно добавил этот компонент, и упаковываем в кэш
    log_info "${SAVE_MARK} Packaging ${STAGENAME} artifacts to cache..."
    
    # Создаем слепок состояния /opt/ffbuild после сборки этого компонента
    # Для простоты и надёжности мы пакуем изменения всего sysroot, которые накопились к этому моменту
    tar -I 'zstd -T0 -3' -cf "$COMPONENT_CACHE_FILE" -C "$SYSROOT_DIR/" opt/
done

log_info "${CHECK_MARK} All intermediate components processed successfully!"
