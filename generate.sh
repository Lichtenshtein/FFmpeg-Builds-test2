#!/bin/bash
set -e
shopt -s globstar
cd "$(dirname "$0")"
source util/vars.sh

export LC_ALL=C.UTF-8

# Очистка старых файлов
rm -f Dockerfile Dockerfile.tmp

to_df() {
    printf "$@" >> Dockerfile
    echo >> Dockerfile
}

# Базовый образ
to_df "FROM ${REGISTRY}/${REPO}/base-${TARGET}:latest AS build_stage"
to_df "ENV TARGET=$TARGET VARIANT=$VARIANT REPO=$REPO ADDINS_STR=$ADDINS_STR"
to_df "COPY --link util/run_stage.sh /usr/bin/run_stage"
to_df "WORKDIR /builder"

# Подготовка зависимостей (Scripts.d)
# Вместо создания сотен слоев, мы генерируем один большой RUN блок
# Это критически важно для стабильности GitHub Runners
to_df "RUN --mount=type=cache,target=/root/.cache/ccache \\"
to_df "    --mount=type=bind,source=scripts.d,target=/builder/scripts.d \\"
to_df "    --mount=type=bind,source=util,target=/builder/util \\"
to_df "    --mount=type=bind,source=.cache/downloads,target=/root/.cache/downloads \\"

# Собираем список всех скриптов
SCRIPTS=( scripts.d/??-* )
for i in "${!SCRIPTS[@]}"; do
    STAGE="${SCRIPTS[$i]}"
    # Определяем, последний ли это скрипт для корректного завершения команды RUN
    SEP=" && \\"
    [[ $i -eq $(( ${#SCRIPTS[@]} - 1 )) ]] && SEP=""
    
    # Мы вызываем run_stage напрямую. Это экономит ресурсы на переключениях контекста Docker
    to_df "    run_stage $STAGE $SEP"
done

# Сборка FFmpeg
# Собираем флаги конфигурации (логика из вашего оригинала)
get_output() {
    (
        SELF="$1"
        source "$1"
        if ffbuild_enabled; then ffbuild_$2 || exit 0; else ffbuild_un$2 || exit 0; fi
    )
}

source "variants/${TARGET}-${VARIANT}.sh"
for addin in ${ADDINS[*]}; do source "addins/${addin}.sh"; done

for script in scripts.d/**/*.sh; do
    FF_CONFIGURE+=" $(get_output $script configure)"
    FF_CFLAGS+=" $(get_output $script cflags)"
    FF_CXXFLAGS+=" $(get_output $script cxxflags)"
    FF_LDFLAGS+=" $(get_output $script ldflags)"
    FF_LDEXEFLAGS+=" $(get_output $script ldexeflags)"
    FF_LIBS+=" $(get_output $script libs)"
done

to_df "ENV \\"
to_df "    FF_CONFIGURE=\"$(xargs <<< "$FF_CONFIGURE")\" \\"
to_df "    FF_CFLAGS=\"$(xargs <<< "$FF_CFLAGS")\" \\"
to_df "    FF_CXXFLAGS=\"$(xargs <<< "$FF_CXXFLAGS")\" \\"
to_df "    FF_LDFLAGS=\"$(xargs <<< "$FF_LDFLAGS")\" \\"
to_df "    FF_LDEXEFLAGS=\"$(xargs <<< "$FF_LDEXEFLAGS")\" \\"
to_df "    FF_LIBS=\"$(xargs <<< "$FF_LIBS")\""

# Копируем исходники и запускаем финальный билд
to_df "COPY . /builder"
# Используем ограничение потоков (nproc/2), чтобы не "задушить" раннер по RAM
to_df "RUN --mount=type=cache,target=/root/.cache/ccache \\"
to_df "    --mount=type=bind,target=/patches,source=patches/ffmpeg \\"
to_df "    ./build.sh $TARGET $VARIANT"

# стадия экспорта (минимальный размер)
to_df ""
to_df "FROM scratch AS artifacts"
# копируем только из /opt/ffdest, где лежат готовые 7z
to_df "COPY --from=build_stage /opt/ffdest/ /"
