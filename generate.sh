#!/bin/bash

set -e
shopt -s globstar
cd "$(dirname "$0")"

# Забираем аргументы из workflow.yaml для локального использования
TARGET="${1:-$TARGET}"
VARIANT="${2:-$VARIANT}"
USE_LTO_FLAG="${3:-nolto}"
SKIP_FFMPEG_FLAG="${4:-false}"
USE_AVX512_FLAG="${5:-false}"
DEDUPE_FLAGS="${DEDUPE_FLAGS:-true}"
USE_WINE="${USE_WINE:-auto}"

# Загружаем переменные
source util/vars.sh "$TARGET" "$VARIANT" 2>&1 || {
    echo "ERROR: vars.sh failed (TARGET=$TARGET VARIANT=$VARIANT)" >&2
    exit 1
}

SKIP_FFMPEG=0
[[ "$SKIP_FFMPEG_FLAG" == "true" || "$SKIP_FFMPEG_FLAG" == "skip_ffmpeg" ]] && SKIP_FFMPEG=1 && log_info "${XCLAM_MARK} FFmpeg compilation will be skipped (Component test mode)."
USE_LTO=0
[[ "$USE_LTO_FLAG" == "lto" ]] && USE_LTO=1 && log_info "${XCLAM_MARK} LTO enabled!"
USE_AVX512=0
[[ "$USE_AVX512_FLAG" == "true" ]] && USE_AVX512=1 && log_info "${XCLAM_MARK} AVX512 enabled!"

export LC_ALL=C.UTF-8

# Явно очищаем файл перед началом записи
echo -n "" > Dockerfile
to_df() {
    echo "$*" >> Dockerfile
}

# Базовый образ
to_df "FROM base-win64 AS build_stage"
to_df "SHELL [\"/bin/bash\", \"-l\", \"-c\"]"

# Объединяем все ENV в одну команду для оптимизации слоев
to_df "ENV TARGET=\"$TARGET\" VARIANT=\"$VARIANT\" REPO=\"$REPO\" ADDINS_STR=\"$ADDINS_STR\" \\
    FFBUILD_VERBOSE=\"$FFBUILD_VERBOSE\" \\
    FFMPEG_REPO=\"$FFMPEG_REPO\" \\
    FFMPEG_BRANCH=\"$FFMPEG_BRANCH\" \\
    DEBUG_NO_HASH=\"$DEBUG_NO_HASH\" \\
    ONLY_STAGE=\"$ONLY_STAGE\" \\
    USE_WINE=\"$USE_WINE\" \\
    USE_AVX512=\"$USE_AVX512\" \\
    USE_LTO=\"$USE_LTO\" \\
    CPU_ARCH=\"${CPU_ARCH:-broadwell}\" \\
    CPU_TUNE=\"${CPU_TUNE:-broadwell}\" \\
    DLL_PRESERVE_LIST=\"$DLL_PRESERVE_LIST\" \\
    GIT_PRESERVE_LIST=\"$GIT_PRESERVE_LIST\""

to_df "WORKDIR /builder"
to_df "COPY util/run_stage.sh /usr/bin/run_stage"
to_df "RUN chmod +x /usr/bin/run_stage"

# Находим все скрипты. If any script path contains spaces, this breaks.
mapfile -t SCRIPTS < <(find scripts.d -name "*.sh" | sort)

# Создаем папку на хосте перед билдом, чтобы Docker не создал её от имени root с кривыми правами
mkdir -p .cache/ccache
mkdir -p .cache/downloads
mkdir -p ffbuild/config_parts

active_scripts=()
for STAGE in "${SCRIPTS[@]}"; do
    grep -q 'ffbuild_enabled.*return 1' "$STAGE" 2>/dev/null && continue
    active_scripts+=("$STAGE")
done

if [[ -n "$ONLY_STAGE" ]]; then
    log_info "Filtering stages by pattern: $ONLY_STAGE"
    mapfile -t active_scripts < <(printf '%s\n' "${active_scripts[@]}" | grep -E "$ONLY_STAGE")
fi

# Environment Hash: Only changes if compiler flags, paths, or toolchain versions change.
# extract only lines that EXPORT variables or set BASE_CFLAGS/LDFLAGS.
ENV_HASH=$(
    {
        grep -E "^export |^BASE_|^SYSTEM_LIBS=" util/vars.sh
        echo "CPU_ARCH=${CPU_ARCH:-broadwell}"
        echo "CPU_TUNE=${CPU_TUNE:-broadwell}"
        echo "USE_AVX512=${USE_AVX512}"
    } | sha256sum | cut -c1-8
)

# Global Logic Hash: Changes if run_stage.sh or the internal functions of vars.sh change.
LOGIC_HASH=$(sha256sum util/run_stage.sh | cut -c1-8)

# Считаем хеши для инвалидации кэша слоев Docker. Импорт из workflow.
# Если поменяется vars.sh или любой патч - все последующие RUN пересоберутся
if [[ "$DEBUG_NO_HASH" == "true" ]]; then
    log_warn "${XCLAM_MARK} DEBUG: Hashes hardcoded to preserve cache."
    ENV_HASH="env_static"
    LOGIC_HASH="logic_static"
fi

# Генерируем блоки RUN для каждой стадии
for STAGE in "${active_scripts[@]}"; do
    STAGENAME="$(basename "$STAGE" .sh)"

    # Component Specific Hash: Only this script + its patches
    SCRIPT_HASH=$(get_stage_hash "$STAGE")

    # Извлекаем имя компонента (напр., из 50-libmp3lame получаем libmp3lame)
    # Используем sed, чтобы отрезать все до первого дефиса включительно
    COMPONENT_NAME=$(echo "$STAGENAME" | sed 's/^[0-9]*-//')
    # Ищем патчи в двух местах:
    #    а) В папке с именем компонента (patches/libmp3lame/*)
    #    б) Файлы, начинающиеся с имени компонента (patches/libmp3lame-custom.patch)
    PATCH_HASH=$( (
        find "patches/$COMPONENT_NAME" -type f 2>/dev/null
        find "patches" -maxdepth 1 -name "${COMPONENT_NAME}*" -type f 2>/dev/null
    ) | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -c1-8 || echo "none")
    # Combine them into a unique ID for this specific layer
    # If you change a log message in vars.sh, ENV_HASH stays the same -> NO REBUILD.
    # If you change CFLAGS in vars.sh, ENV_HASH changes -> GLOBAL REBUILD.
    LAYER_ID="E:${ENV_HASH}_L:${LOGIC_HASH}_S:${SCRIPT_HASH}_P:${PATCH_HASH}"

    to_df "# Stage: $STAGENAME | LayerID: $LAYER_ID"
    to_df "RUN --mount=type=cache,id=ccache-${TARGET},target=/root/.cache/ccache \\"
    to_df "    --mount=type=cache,id=prefix-${TARGET},target=$FFBUILD_PREFIX \\"
    to_df "    --mount=type=bind,source=scripts.d,target=/builder/scripts.d \\"
    to_df "    --mount=type=bind,source=util,target=/builder/util \\"
    to_df "    --mount=type=bind,source=patches,target=/builder/patches \\"
    to_df "    --mount=type=bind,source=variants,target=/builder/variants \\"
    to_df "    --mount=type=bind,source=addins,target=/builder/addins \\"
    to_df "    --mount=type=bind,source=.cache/downloads,target=/root/.cache/downloads,rw \\"
    to_df "    set -e && export _H=$LAYER_ID && export TARGET=\"$TARGET\" VARIANT=\"$VARIANT\" SCRIPT_PATH=\"/builder/$STAGE\" && . /builder/util/vars.sh \"$TARGET\" \"$VARIANT\" && run_stage /builder/$STAGE"
done

if [[ $SKIP_FFMPEG -eq 1 ]]; then
    log_info "${XCLAM_MARK} Option 'skip_ffmpeg' is active. Final build stage will be omitted."
    # Создаем пустой файл в artifacts, чтобы экшн загрузки не падал
    to_df "RUN mkdir -p /opt/ffdest && touch /opt/ffdest/COMPONENTS_BUILD_SUCCESS"
else
    # Копируем всё необходимое для финальной сборки
    to_df "COPY variants /builder/variants"
    to_df "COPY addins /builder/addins"
    to_df "COPY build.sh /builder/build.sh"
    to_df "COPY util /builder/util"
    to_df "COPY patches /builder/patches"

    # Мы не передаем флаги через ENV для ffmpeg, а подгружаем их внутри финального RUN
    # мы видим файлы .vars, созданные в Docker-кэше
    to_df "RUN --mount=type=cache,id=ccache-${TARGET},target=/root/.cache/ccache \\"
    to_df "    --mount=type=cache,id=prefix-${TARGET},target=${FFBUILD_PREFIX} \\"
    to_df "    --mount=from=ffmpeg_src,target=/builder/ffbuild/ffmpeg,rw \\"
    to_df "    ./build.sh \"$TARGET\" \"$VARIANT\""
fi

to_df "FROM scratch AS artifacts"
to_df "COPY --from=build_stage /opt/ffdest/ ." 
