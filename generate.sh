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

# Базовый образ
to_df "FROM ${REGISTRY}/${REPO}/base-${TARGET}:latest AS build_stage"
to_df "ENV TARGET=$TARGET VARIANT=$VARIANT REPO=$REPO ADDINS_STR=$ADDINS_STR"
to_df "COPY --link util/run_stage.sh /usr/bin/run_stage"
to_df "WORKDIR /builder"

# Подготовка этапов сборки (Scripts.d)
to_df "RUN --mount=type=cache,target=/root/.cache/ccache \\"
to_df "    --mount=type=bind,source=scripts.d,target=/builder/scripts.d \\"
to_df "    --mount=type=bind,source=util,target=/builder/util \\"
to_df "    --mount=type=bind,source=patches,target=patches/ffmpeg \\"
to_df "    --mount=type=bind,source=.cache/downloads,target=/root/.cache/downloads \\"

# Находим все .sh файлы, сортируем их по имени (это обеспечит порядок 10, 20, 45, 50...)
# Мы используем -lexical сортировку, чтобы scripts.d/45-fonts/01-xx шел перед 50-xx
SCRIPTS=( $(find scripts.d -name "*.sh" | sort) )

for i in "${!SCRIPTS[@]}"; do
    STAGE="${SCRIPTS[$i]}"
    
    # Проверка, включен ли скрипт для данной цели (win64/nonfree)
    # Это важно сделать на этапе генерации, чтобы не плодить пустые RUN
    if ! ( source "$STAGE" && ffbuild_enabled ); then
        continue
    fi

    SEP=" && \\"
    [[ $i -eq $(( ${#SCRIPTS[@]} - 1 )) ]] && SEP=""
    
    # Используем абсолютный путь внутри контейнера (/builder/...)
    to_df "    run_stage /builder/$STAGE $SEP"
done

# Сборка FFmpeg (Флаги конфигурации)
# Собираем переменные для финального ./configure FFmpeg
source "variants/${TARGET}-${VARIANT}.sh"
for addin in ${ADDINS[*]}; do source "addins/${addin}.sh"; done

# Собираем флаги из всех активных скриптов
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
to_df "    FF_LDEXEFLAGS=\"$(xargs <<< "$FF_LDFLAGS")\" \\"
to_df "    FF_LIBS=\"$(xargs <<< "$FF_LIBS")\""

# Копируем исходники проекта (включая build.sh и patches)
to_df "COPY . /builder"

# Запуск финальной сборки FFmpeg
to_df "RUN --mount=type=cache,target=/root/.cache/ccache \\"
to_df "    ./build.sh $TARGET $VARIANT"

# 4. Экспорт артефактов
to_df ""
to_df "FROM scratch AS artifacts"
to_df "COPY --from=build_stage /opt/ffdest/ /"
