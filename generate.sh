#!/bin/bash
set -e
shopt -s globstar
cd "$(dirname "$0")"

# Сначала загружаем переменные (включая вариант), 
# но перенаправляем их стандартный вывод в никуда, 
# чтобы случайные echo не попали в поток генерации.
source util/vars.sh "$@" > /dev/null 2>&1

export LC_ALL=C.UTF-8

# Явно очищаем файл перед началом записи
echo -n "" > Dockerfile

to_df() {
    printf "$@" >> Dockerfile
    echo >> Dockerfile
}

# Базовый образ
to_df "FROM base-win64:local AS build_stage"
to_df "ENV TARGET=$TARGET VARIANT=$VARIANT REPO=$REPO ADDINS_STR=$ADDINS_STR"
to_df "ENV C_INCLUDE_PATH=/opt/ffbuild/include CPATH=/opt/ffbuild/include LIBRARY_PATH=/opt/ffbuild/lib"
to_df "ENV BASH_ENV=/builder/util/vars.sh" 

# Копируем утилиту один раз. Это стабильная точка для кэша.
to_df "COPY util/run_stage.sh /usr/bin/run_stage"
to_df "RUN chmod +x /usr/bin/run_stage"
to_df "WORKDIR /builder"

# Находим все скрипты
SCRIPTS=( $(find scripts.d -name "*.sh" | sort) )

# Создаем папку на хосте перед билдом, чтобы Docker не создал её от имени root с кривыми правами
mkdir -p .cache/ccache

# Общие монтирования (BIND) для каждого RUN. 
# Кэш сработает, если содержимое монтируемых файлов не менялось.
MOUNTS="--mount=type=bind,source=.cache/ccache,target=/root/.cache/ccache \\
    --mount=type=bind,source=scripts.d,target=/builder/scripts.d \\
    --mount=type=bind,source=util,target=/builder/util \\
    --mount=type=bind,source=patches,target=/builder/patches \\
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

# Генерируем ОТДЕЛЬНЫЙ RUN для каждого активного скрипта
for STAGE in "${active_scripts[@]}"; do
    STAGENAME="$(basename "$STAGE" | sed 's/.sh$//')" # Получаем имя для лога
    SCRIPT_HASH=$(sha256sum "$STAGE" | cut -c1-8)
    to_df "# Hash: $SCRIPT_HASH"
    to_df "RUN $MOUNTS \\"
    to_df "    source /builder/util/vars.sh $TARGET $VARIANT &>/dev/null && \\"
    to_df "    log_info '>>> $STAGENAME <<<' && run_stage /builder/$STAGE"
done

# Сборка FFmpeg (Флаги конфигурации)
# Собираем переменные для финального ./configure FFmpeg
# Инициализируем пустые массивы
conf_args=()
cflags_args=()
ldflags_args=()
cxxflags_args=()
ldexeflags_args=()
libs_args=()


# Собираем конфигурацию из вариантов и аддинов
# (Предположим, функции ffbuild_... внутри них тоже возвращают строки)
source "variants/${TARGET}-${VARIANT}.sh"
conf_args+=( $(ffbuild_configure) )

for addin in ${ADDINS[*]}; do 
    source "addins/${addin}.sh"
    conf_args+=( $(ffbuild_configure) )
done

# Наполняем массивы из активных скриптов для финального билда
for script in "${active_scripts[@]}"; do
    if ( source "$script" && ffbuild_enabled ); then
        # Используем подстановку, которая корректно разбивает строку на элементы массива
        # Внимание: здесь мы полагаемся на то, что функции возвращают пробелы как разделители
        read -a cfg <<< "$(source "$script" && ffbuild_configure)"
        conf_args+=("${cfg[@]}")
        
        read -a cfl <<< "$(source "$script" && ffbuild_cflags)"
        cflags_args+=("${cfl[@]}")

        read -a ldf <<< "$(source "$script" && ffbuild_ldflags)"
        ldflags_args+=("${ldf[@]}")

        read -a cxx <<< "$(source "$script" && ffbuild_cxxflags)"
        cxxflags_args+=("${cxx[@]}")

        read -a ldexe <<< "$(source "$script" && ffbuild_ldexeflags)"
        ldexeflags_args+=("${ldexe[@]}")

        read -a libs <<< "$(source "$script" && ffbuild_libs)"
        libs_args+=("${libs[@]}")

   fi
done

# Превращаем массивы в ОДНУ правильно экранированную строку для Dockerfile
# Команда printf '%q ' экранирует все спецсимволы, сохраняя пробелы внутри кавычек
FF_CONFIGURE_SAFE=$(printf '%q ' "${conf_args[@]}")
FF_CFLAGS_SAFE=$(printf '%q ' "${cflags_args[@]}")
FF_LDFLAGS_SAFE=$(printf '%q ' "${ldflags_args[@]}")
FF_CXXFLAGS_SAFE=$(printf '%q ' "${cxxflags_args[@]}")
FF_LDEXEFLAGS_SAFE=$(printf '%q ' "${ldexeflags_args[@]}")
FF_LIBS_SAFE=$(printf '%q ' "${libs_args[@]}")

# Записываем в Dockerfile
to_df "ENV \\"
to_df "    FF_CONFIGURE=\"$FF_CONFIGURE_SAFE\" \\"
to_df "    FF_CFLAGS=\"$FF_CFLAGS_SAFE\" \\"
to_df "    FF_LDFLAGS=\"$FF_LDFLAGS_SAFE\" \\"
to_df "    FF_CXXFLAGS=\"$FF_CXXFLAGS_SAFE\" \\"
to_df "    FF_LDEXEFLAGS=\"$FF_LDEXEFLAGS_SAFE\" \\"
to_df "    FF_LIBS=\"$FF_LIBS_SAFE\""

# Копируем исходники проекта (включая build.sh и patches)
# to_df "COPY . /builder"
# Только в самом конце копируем остальное для финального шага билда
to_df "COPY build.sh /builder/build.sh"
to_df "COPY util /builder/util"
to_df "COPY patches /builder/patches"
# раскомментировать после отладки для сборки FFmpeg
# to_df "COPY variants /builder/variants"
# to_df "COPY addins /builder/addins"
to_df "RUN --mount=type=bind,source=.cache/ccache,target=/root/.cache/ccache \\"
to_df "    --mount=from=ffmpeg_src,target=/builder/ffbuild/ffmpeg \\" # Монтируем контекст FFmpeg
to_df "    ./build.sh $TARGET $VARIANT"

to_df "FROM scratch AS artifacts"
to_df "COPY --from=build_stage /opt/ffdest/ /"
