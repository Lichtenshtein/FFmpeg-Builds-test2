#!/bin/bash
set -e
shopt -s globstar
cd "$(dirname "$0")"
source util/vars.sh

export LC_ALL=C.UTF-8
rm -f Dockerfile

to_df() {
    printf "$@" >> Dockerfile
    echo >> Dockerfile
}

to_df "FROM ${REGISTRY}/${REPO}/base-${TARGET}:latest AS build_stage"
to_df "ENV TARGET=$TARGET VARIANT=$VARIANT REPO=$REPO ADDINS_STR=$ADDINS_STR"
to_df "COPY --link util/run_stage.sh /usr/bin/run_stage"
to_df "WORKDIR /builder"

# Находим все скрипты
SCRIPTS=( $(find scripts.d -name "*.sh" | sort) )

# Генерируем один большой слой RUN для всех зависимостей
to_df "RUN --mount=type=cache,target=/root/.cache/ccache \\"
to_df "    --mount=type=bind,source=scripts.d,target=/builder/scripts.d \\"
to_df "    --mount=type=bind,source=util,target=/builder/util \\"
to_df "    --mount=type=bind,source=patches,target=/builder/patches \\"
to_df "    --mount=type=bind,source=.cache/downloads,target=/root/.cache/downloads,ro \\" # Добавлен ,ro

active_scripts=()
for STAGE in "${SCRIPTS[@]}"; do
    # Проверка, включен ли скрипт для данной цели (win64/nonfree)
    # Это важно сделать на этапе генерации, чтобы не плодить пустые RUN
    if ( source "$STAGE" && ffbuild_enabled ); then
        # Проверяем, есть ли у скрипта что скачивать. 
        # Если ffbuild_dockerdl пуст, значит архив не создавался, и run_stage не нужен.
        DL_CHECK=$(bash -c "source util/vars.sh \"$TARGET\" \"$VARIANT\" &>/dev/null; source util/dl_functions.sh; source \"$STAGE\"; ffbuild_dockerdl" || echo "")
        
        # Если это не пропуск (SCRIPT_SKIP) и есть загрузка, или если это важный системный скрипт
        active_scripts+=("$STAGE")
    fi
done

for i in "${!active_scripts[@]}"; do
    STAGE="${active_scripts[$i]}"
    STAGENAME="$(basename "$STAGE" | sed 's/.sh$//')" # Получаем имя для лога
    SEP=" && \\"
    [[ $i -eq $(( ${#active_scripts[@]} - 1 )) ]] && SEP=""
    # Используем абсолютный путь внутри контейнера (/builder/...)
    # Добавляем вывод имени этапа перед запуском
    to_df "    echo '===> Building stage: $STAGENAME' && run_stage /builder/$STAGE $SEP"
done

# Сборка FFmpeg (Флаги конфигурации)
# Собираем переменные для финального ./configure FFmpeg
source "variants/${TARGET}-${VARIANT}.sh"
for addin in ${ADDINS[*]}; do source "addins/${addin}.sh"; done

# Собираем конфигурацию для финального билда
FF_CONFIGURE=""
for script in "${SCRIPTS[@]}"; do
    if ( source "$script" && ffbuild_enabled ); then
        FF_CONFIGURE+=" $( (source "$script" && ffbuild_configure) )"
        FF_CFLAGS+=" $( (source "$script" && ffbuild_cflags) )"
        FF_CXXFLAGS+=" $( (source "$script" && ffbuild_cxxflags) )"
        FF_LDFLAGS+=" $( (source "$script" && ffbuild_ldflags) )"
        FF_LDEXEFLAGS+=" $( (source "$script" && ffbuild_ldexeflags) )"
        FF_LIBS+=" $( (source "$script" && ffbuild_libs) )"
    fi
done

to_df "ENV \\"
to_df "    FF_CONFIGURE=\"$(xargs <<< "$FF_CONFIGURE")\" \\"
to_df "    FF_CFLAGS=\"$(xargs <<< "$FF_CFLAGS")\" \\"
to_df "    FF_CXXFLAGS=\"$(xargs <<< "$FF_CXXFLAGS")\" \\"
to_df "    FF_LDFLAGS=\"$(xargs <<< "$FF_LDFLAGS")\" \\"
to_df "    FF_LDEXEFLAGS=\"$(xargs <<< "$FF_LDEXEFLAGS")\" \\"
to_df "    FF_LIBS=\"$(xargs <<< "$FF_LIBS")\""

# Копируем исходники проекта (включая build.sh и patches)
to_df "COPY . /builder"
to_df "RUN --mount=type=cache,target=/root/.cache/ccache ./build.sh $TARGET $VARIANT"

to_df "FROM scratch AS artifacts"
to_df "COPY --from=build_stage /opt/ffdest/ /"
