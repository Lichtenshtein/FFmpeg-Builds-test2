#!/bin/bash

set -e
shopt -s globstar
cd "$(dirname "$0")"

# Забираем аргументы для локального использования
TARGET="${1:-$TARGET}"
VARIANT="${2:-$VARIANT}"
LTO_INPUT="${3:-nolto}"
SKIP_FFMPEG_INPUT="${4:-false}"
DEDUPE_INPUT="${5:-true}"

# Сначала загружаем переменные (включая вариант), 
# но перенаправляем их стандартный вывод в никуда, 
# чтобы случайные echo не попали в поток генерации.
source util/vars.sh "$@" > /dev/null 2>&1

SKIP_FFMPEG=0
[[ "$SKIP_FFMPEG_INPUT" == "skip_ffmpeg" ]] && SKIP_FFMPEG=1
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
to_df "ENV TARGET=$TARGET VARIANT=$VARIANT REPO=$REPO ADDINS_STR=$ADDINS_STR \\
    FFBUILD_VERBOSE=$FFBUILD_VERBOSE \\
    FFMPEG_REPO=$FFMPEG_REPO \\
    FFMPEG_BRANCH=$FFMPEG_BRANCH \\
    DEBUG_NO_HASH=$DEBUG_NO_HASH \\
    ONLY_STAGE=\"$ONLY_STAGE\" \\
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

# Общие монтирования (BIND) для каждого RUN. 
# Кэш сработает, если содержимое монтируемых файлов не менялось.
MOUNTS="--mount=type=cache,id=ccache-${TARGET},target=/root/.cache/ccache \\
    --mount=type=bind,source=scripts.d,target=/builder/scripts.d \\
    --mount=type=bind,source=util,target=/builder/util \\
    --mount=type=bind,source=patches,target=/builder/patches \\
    --mount=type=bind,source=variants,target=/builder/variants \\
    --mount=type=bind,source=addins,target=/builder/addins \\
    --mount=type=bind,source=.cache/downloads,target=/root/.cache/downloads"

active_scripts=()
for STAGE in "${SCRIPTS[@]}"; do
    if ( source "$STAGE" && ffbuild_enabled ); then
        active_scripts+=("$STAGE")
    fi
done

if [[ -n "$ONLY_STAGE" ]]; then
    log_info "Filtering stages by pattern: $ONLY_STAGE"
    active_scripts=( $(printf '%s\n' "${active_scripts[@]}" | grep -E "$ONLY_STAGE") )
fi

# Считаем хеши для инвалидации кэша слоев Docker. Импорт из workflow.
# Если поменяется vars.sh или любой патч - все последующие RUN пересоберутся
if [[ "$DEBUG_NO_HASH" == "true" ]]; then
    log_warn "DEBUG MODE: VARS_HASH is hardcoded to 'debug_static' to preserve cache."
    VARS_HASH="debug_static"
else
    VARS_HASH=$(sha256sum util/vars.sh util/run_stage.sh | sha256sum | cut -c1-8)
fi

# Генерируем блоки RUN для каждой стадии
for STAGE in "${active_scripts[@]}"; do
    STAGENAME="$(basename "$STAGE" .sh)"

    # ИСПОЛЬЗУЕМ ЕДИНУЮ ФУНКЦИЮ ДЛЯ ВСЕГО
    FULL_HASH=$(get_stage_hash "$STAGE")

    # Извлекаем имя компонента (напр., из 50-libmp3lame получаем libmp3lame)
    # Используем sed, чтобы отрезать все до первого дефиса включительно
    COMPONENT_NAME=$(echo "$STAGENAME" | sed 's/^[0-9]*-//')
    # Ищем патчи в двух местах:
    #    а) В папке с именем компонента (patches/libmp3lame/*)
    #    б) Файлы, начинающиеся с имени компонента (patches/libmp3lame-custom.patch)
    COMPONENT_PATCH_HASH=$( (
        find "patches/$COMPONENT_NAME" -type f 2>/dev/null
        find "patches" -maxdepth 1 -name "${COMPONENT_NAME}*" -type f 2>/dev/null
    ) | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -c1-8 || echo "none")
    # Если изменится vars.sh ($VARS_HASH), Docker пересоберет слой.
    # Если изменится скрипт ($FULL_HASH), Docker пересоберет слой.
    to_df "# Stage: $STAGENAME | Component: $COMPONENT_NAME | Vars Hash: $VARS_HASH | Patches Hash: $COMPONENT_PATCH_HASH | Full Hash: $FULL_HASH"

    to_df "RUN --mount=type=cache,id=ccache-${TARGET},target=/root/.cache/ccache \\"
    to_df "    --mount=type=bind,source=scripts.d,target=/builder/scripts.d \\"
    to_df "    --mount=type=bind,source=util,target=/builder/util \\"
    to_df "    --mount=type=bind,source=patches,target=/builder/patches \\"
    to_df "    --mount=type=bind,source=variants,target=/builder/variants \\"
    to_df "    --mount=type=bind,source=addins,target=/builder/addins \\"
    to_df "    --mount=type=bind,source=.cache/downloads,target=/root/.cache/downloads \\"
    to_df "    set -e; export _H=$FULL_HASH:$VARS_HASH:$COMPONENT_PATCH_HASH && . /builder/util/vars.sh $TARGET $VARIANT && run_stage /builder/$STAGE"
done

# Сборка флагов конфигурации FFmpeg
# Временные файлы для сбора
touch .conf .cflags .ldflags .libs .cxxflags .ldexeflags

# Функция для безопасного извлечения флагов
collect_all_flags() {
    local script_path="$1"
    (
        # Загружаем скрипт
        source "$script_path" > /dev/null 2>&1

        # Извлекаем флаги из переменных (для файлов из variants/ и addins/)
        [[ -n "$FF_CONFIGURE" ]] && echo "$FF_CONFIGURE" >> .conf
        [[ -n "$FF_CFLAGS" ]]    && echo "$FF_CFLAGS"    >> .cflags
        [[ -n "$FF_LDFLAGS" ]]   && echo "$FF_LDFLAGS"   >> .ldflags
        [[ -n "$FF_CXXFLAGS" ]]  && echo "$FF_CXXFLAGS"  >> .cxxflags
        [[ -n "$FF_LDEXEFLAGS" ]] && echo "$FF_LDEXEFLAGS" >> .ldexeflags
        [[ -n "$FF_LIBS" ]]      && echo "$FF_LIBS"      >> .libs

        # Извлекаем флаги из функций (для файлов из scripts.d/ и addins/)
        get_from_func() {
            local func=$1
            local out_file=$2
            if declare -F "$func" >/dev/null; then
                # Выполняем функцию.
                # Весь stderr оставляем как есть.
                # Из stdout берем только ПОСЛЕДНЮЮ непустую строку.
                local res=$($func 2>&1 | tee /dev/stderr | grep -vE "^\[(INFO|DEBUG|WARN)\]" | tail -n 1 | xargs)
                [[ -n "$res" ]] && echo "$res" >> "$out_file"
            fi
        }

        get_from_func "ffbuild_configure" ".conf"
        get_from_func "ffbuild_cflags" ".cflags"
        get_from_func "ffbuild_ldflags" ".ldflags"
        get_from_func "ffbuild_cxxflags" ".cxxflags"
        get_from_func "ffbuild_ldexeflags" ".ldexeflags"
        get_from_func "ffbuild_libs" ".libs"
    ) || log_error "Failed to collect flags from $script"
}

log_info "Collecting flags from variant and addins..."

# Сначала собираем флаги из основного варианта
collect_all_flags "variants/${TARGET}-${VARIANT}.sh"

# Затем из всех активных аддинов (например, lto.sh или debug.sh)
for addin in ${ADDINS[*]}; do
    collect_all_flags "addins/${addin}.sh"
done

log_info "Collecting flags from component scripts..."
# Затем из всех активных скриптов компонентов
for script in "${active_scripts[@]}"; do
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

# Читаем и очищаем итоговые строки
FF_CONFIGURE=$(dedupe "$FF_CONFIGURE")
FF_CFLAGS=$(dedupe "$FF_CFLAGS")
FF_LDFLAGS=$(smart_dedupe "$FF_LDFLAGS")
FF_CXXFLAGS=$(dedupe "$FF_CXXFLAGS")
FF_LDEXEFLAGS=$(dedupe "$FF_LDEXEFLAGS")
FF_LIBS=$(smart_dedupe "$FF_LIBS")

# Записываем в Dockerfile
to_df "ENV FF_CONFIGURE=\"$FF_CONFIGURE\""
to_df "ENV FF_CFLAGS=\"$FF_CFLAGS\""
to_df "ENV FF_LDFLAGS=\"$FF_LDFLAGS\""
to_df "ENV FF_CXXFLAGS=\"$FF_CXXFLAGS\""
to_df "ENV FF_LDEXEFLAGS=\"$FF_LDEXEFLAGS\""
to_df "ENV FF_LIBS=\"$FF_LIBS\""

rm .conf .cflags .ldflags .libs .cxxflags .ldexeflags

if [[ $SKIP_FFMPEG -eq 1 ]]; then
    log_info "Option 'skip_ffmpeg' is active. Final build stage will be omitted."
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
    to_df "    --mount=from=ffmpeg_src,target=/builder/ffbuild/ffmpeg \\"
    to_df "    ./build.sh $TARGET $VARIANT"
fi

to_df "FROM scratch AS artifacts"
to_df "COPY --from=build_stage /opt/ffdest/ /"
