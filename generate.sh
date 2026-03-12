#!/bin/bash

set -e
shopt -s globstar
cd "$(dirname "$0")"

# Забираем аргументы для локального использования
TARGET="${1:-$TARGET}"
VARIANT="${2:-$VARIANT}"
LTO_INPUT="${3:-nolto}"
SKIP_FFMPEG_INPUT="${4:-false}"
DEDUPE_INPUT="${DEDUPE_FLAGS:-true}"
USE_WINE_VAL="${USE_WINE:-auto}"

# Сначала загружаем переменные (включая вариант), 
# но перенаправляем их стандартный вывод в никуда, 
# чтобы случайные echo не попали в поток генерации.
# source util/vars.sh "$@" > /dev/null 2>&1
source util/vars.sh "$@" 2>/dev/null || { echo "ERROR: vars.sh failed to source (TARGET=$TARGET VARIANT=$VARIANT)" >&2; exit 1; }

SKIP_FFMPEG=0
if [[ "$SKIP_FFMPEG_INPUT" == "true" || "$SKIP_FFMPEG_INPUT" == "skip_ffmpeg" ]]; then
    SKIP_FFMPEG=1
    log_info "${XCLAM_MARK} FFmpeg compilation will be skipped (Component test mode)."
fi
USE_LTO=0
[[ "$LTO_INPUT" == "lto" ]] && USE_LTO=1

export LC_ALL=C.UTF-8

# Явно очищаем файл перед началом записи
echo -n "" > Dockerfile

to_df() {
    echo "$*" >> Dockerfile
}

# Базовый образ
to_df "FROM base-win64 AS build_stage"
to_df "SHELL [\"/bin/bash\", \"-c\"]"

# Объединяем все ENV в одну команду для оптимизации слоев
to_df "ENV TARGET=\"$TARGET\" VARIANT=\"$VARIANT\" REPO=\"$REPO\" ADDINS_STR=\"$ADDINS_STR\" \\
    FFBUILD_VERBOSE=\"$FFBUILD_VERBOSE\" \\
    FFMPEG_REPO=\"$FFMPEG_REPO\" \\
    FFMPEG_BRANCH=\"$FFMPEG_BRANCH\" \\
    DEBUG_NO_HASH=\"$DEBUG_NO_HASH\" \\
    ONLY_STAGE=\"$ONLY_STAGE\" \\
    USE_WINE=\"$USE_WINE\" \\
    DLL_PRESERVE_LIST=\"$DLL_PRESERVE_LIST\" \\
    GIT_PRESERVE_LIST=\"$GIT_PRESERVE_LIST\""

to_df "ENV C_INCLUDE_PATH=/opt/ffbuild/include CPATH=/opt/ffbuild/include LIBRARY_PATH=/opt/ffbuild/lib"

# Копируем утилиту один раз. Это стабильная точка для кэша.
to_df "COPY util/run_stage.sh /usr/bin/run_stage"
to_df "RUN chmod +x /usr/bin/run_stage"
to_df "WORKDIR /builder"

# Находим все скрипты
SCRIPTS=( $(find scripts.d -name "*.sh" | sort) )

# Создаем папку на хосте перед билдом, чтобы Docker не создал её от имени root с кривыми правами
mkdir -p .cache/ccache
mkdir -p ffbuild/config_parts

active_scripts=()
for STAGE in "${SCRIPTS[@]}"; do
    if ( source util/vars.sh "$TARGET" "$VARIANT" > /dev/null 2>&1 && source "$STAGE" && ffbuild_enabled ); then
        active_scripts+=("$STAGE")
    fi
done

if [[ -n "$ONLY_STAGE" ]]; then
    log_info "Filtering stages by pattern: $ONLY_STAGE"
    active_scripts=( $(printf '%s\n' "${active_scripts[@]}" | grep -E "$ONLY_STAGE") )
fi

# Environment Hash: Only changes if compiler flags, paths, or toolchain versions change.
# We extract only lines that EXPORT variables or set BASE_CFLAGS/LDFLAGS.
ENV_HASH=$(grep -E "^export |^BASE_|^SYSTEM_LIBS=" util/vars.sh | sha256sum | cut -c1-8)

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
    to_df "    set -e; export _H=$LAYER_ID && . /builder/util/vars.sh $TARGET $VARIANT && run_stage /builder/$STAGE"
done

# Сборка флагов конфигурации FFmpeg
# Временные файлы для сбора
TMPFILES=(.conf .cflags .ldflags .libs .cxxflags .cppflags .ldexeflags)
touch "${TMPFILES[@]}"
log_info "Temporary file created: ${TMPFILES[*]}"
trap 'rm -f "${TMPFILES[@]}"' EXIT

# Function to clean ANSI colors and log prefixes
# 1. Strip ANSI color codes (the \x1B parts)
# 2. Strip your custom log tags like [INFO], [DEBUG], etc.
# 3. Strip leading/trailing whitespace
clean_output() {
    sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" | \
    grep -vE "^\[(INFO|DEBUG|WARN|ERROR)\]" | \
    tail -n 1 | xargs
}

# Функция для безопасного извлечения флагов
collect_all_flags() {
    local script_path="$1"
    
    if [[ ! -f "$script_path" ]]; then
        log_warn "Flag file not found: $script_path"
        return 0
    fi

    # 1. Clear variables
    unset FF_CONFIGURE FF_CFLAGS FF_LDFLAGS FF_CXXFLAGS FF_CPPFLAGS FF_LDEXEFLAGS FF_LIBS
    
    # 2. Source the script but disable 'exit on error' temporarily
    set +e
    source "$script_path" >/dev/null 2>&1
    local src_status=$?
    set -e

    if [[ $src_status -ne 0 ]]; then
        log_error "Failed to source $script_path (Exit code: $src_status)"
        return 0 # We return 0 so the whole generate.sh doesn't die
    fi

    # 3. Check enabled
    if declare -F ffbuild_enabled >/dev/null; then
        if ! ffbuild_enabled; then return 0; fi
    fi
    
    # 4. Collection logic (Variables)
    [[ -n "$FF_CONFIGURE" ]] && echo "$FF_CONFIGURE" | clean_output >> .conf
    [[ -n "$FF_CFLAGS" ]]    && echo "$FF_CFLAGS"    | clean_output >> .cflags
    [[ -n "$FF_LDFLAGS" ]]   && echo "$FF_LDFLAGS"   | clean_output >> .ldflags
    [[ -n "$FF_LIBS" ]]      && echo "$FF_LIBS"      | clean_output >> .libs

    # 5. Collection logic (Functions)
    get_from_func() {
        local func=$1
        local out_file=$2
        if declare -F "$func" >/dev/null; then
            # Run in subshell to isolate potential 'exit' calls in components
            local res
            res=$( ($func) 2>&1 | clean_output )
            [[ -n "$res" ]] && echo "$res" >> "$out_file"
        fi
    }

    get_from_func "ffbuild_configure" ".conf"
    get_from_func "ffbuild_cflags" ".cflags"
    get_from_func "ffbuild_ldflags" ".ldflags"
    get_from_func "ffbuild_libs" ".libs"
}



log_info "Collecting flags from variant and addins..."

# Сначала собираем флаги из основного варианта
log_debug "Target Variant: variants/${TARGET}-${VARIANT}.sh"
collect_all_flags "variants/${TARGET}-${VARIANT}.sh" || exit 1

for addin in ${ADDINS[*]}; do
    log_debug "Addin: addins/${addin}.sh"
    collect_all_flags "addins/${addin}.sh" || exit 1
done

log_info "Collecting flags from filtered component scripts..."
# We only iterate over scripts that are actually being BUILT in this run
for script in "${active_scripts[@]}"; do
    STAGENAME="$(basename "$script" .sh)"
    # If ONLY_STAGE is active, skip scripts that don't match the regex
    if [[ -n "$ONLY_STAGE" ]]; then
        if ! echo "$STAGENAME" | grep -qE "$ONLY_STAGE"; then
            log_debug "Skipping flag collection for $STAGENAME (not in ONLY_STAGE)"
            continue
        fi
    fi
    log_info "${SEARCH_MARK} Collecting flags: $STAGENAME"
    collect_all_flags "$script"
done

# Функция для удаления дубликатов с сохранением порядка
# Для флагов компиляции (CFLAGS) порядок менее важен, 
# но для LDFLAGS/LIBS мы просто склеиваем строки, 
# удаляя лишние пробелы, но сохраняя последовательность.
dedupe() {
    echo "$1" | xargs | tr ' ' '\n' | awk '!x[$0]++' | xargs
}
smart_dedupe() {
    local input="$1"
    if [[ "$DEDUPE_INPUT" == "true" ]]; then
        # Удаляем дубликаты, сохраняя ПЕРВОЕ вхождение (традиционный подход)
        echo "$input" | xargs -n1 | awk '!x[$0]++' | xargs
    else
        # Просто склеиваем в одну строку, убирая лишние пробелы
        echo "$input" | xargs
    fi
}

for key in CONFIGURE CFLAGS LDFLAGS CXXFLAGS CPPFLAGS LDEXEFLAGS LIBS; do
    # Ensure the file exists before catting
    [[ -f ".$key" ]] || touch ".$key"
    val=$(cat ".$key" | xargs)
    # If the value is empty, don't generate an empty ENV line
    if [[ -n "$val" ]]; then
        [[ "$key" =~ LDFLAGS|LIBS ]] && func="smart_dedupe" || func="dedupe"
        final_val=$($func "$val")
        to_df "ENV FF_$key=\"$final_val\""
    fi
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

    to_df "RUN --mount=type=cache,id=ccache-${TARGET},target=/root/.cache/ccache \\"
    to_df "    --mount=from=ffmpeg_src,target=/builder/ffbuild/ffmpeg,rw \\"
    to_df "    ./build.sh $TARGET $VARIANT"
fi

to_df "FROM scratch AS artifacts"
to_df "COPY --from=build_stage /opt/ffdest/ /"
