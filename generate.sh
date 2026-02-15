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
to_df "FROM base-win64 AS build_stage"
# to_df "FROM ${REGISTRY}/${REPO}/base-${TARGET}:latest AS build_stage"
to_df "ENV TARGET=$TARGET VARIANT=$VARIANT REPO=$REPO ADDINS_STR=$ADDINS_STR"
to_df "ENV C_INCLUDE_PATH=/opt/ffbuild/include CPATH=/opt/ffbuild/include LIBRARY_PATH=/opt/ffbuild/lib"

# Копируем утилиту один раз. Это стабильная точка для кэша.
to_df "COPY util/run_stage.sh /usr/bin/run_stage"
to_df "RUN chmod +x /usr/bin/run_stage"
to_df "WORKDIR /builder"

# Находим все скрипты
SCRIPTS=( $(find scripts.d -name "*.sh" | sort) )
# Временно для тестов в generate.sh:
# SCRIPTS=( scripts.d/20-zlib.sh scripts.d/47-vulkan/40-vulkan-headers.sh scripts.d/50-dvd/40-libdvdread.sh scripts.d/47-vulkan/45-vulkan-loader.sh scripts.d/45-vmaf.sh scripts.d/47-vulkan/46-glslang-test.sh scripts.d/47-vulkan/47-shaderc.sh scripts.d/50-aom.sh scripts.d/50-libcodec2-test.sh scripts.d/50-flite-test.sh scripts.d/47-vulkan/55-spirv-cross.sh )

# SCRIPTS=( scripts.d/10-mingw.sh scripts.d/10-mingw-std-threads.sh scripts.d/15-base.sh scripts.d/20-libiconv.sh scripts.d/20-zlib.sh scripts.d/30-libffi.sh scripts.d/20-pcre2.sh scripts.d/40-glib2.sh scripts.d/50-lensfun-test.sh )


# scripts.d/20-libiconv.sh lame and glib2 need it
# scripts.d/45-fonts/25-freetype.sh

# Общие монтирования (BIND) для каждого RUN. 
# Кэш сработает, если содержимое монтируемых файлов не менялось.
MOUNTS="--mount=type=cache,target=/root/.cache/ccache \\
    --mount=type=bind,source=scripts.d,target=/builder/scripts.d \\
    --mount=type=bind,source=util,target=/builder/util \\
    --mount=type=bind,source=patches,target=/builder/patches \\
    --mount=type=bind,source=.cache/downloads,target=/root/.cache/downloads,ro" 
   # Добавлен ,ro к /root/.cache/downloads,ro . Eсли какой-то скрипт в scripts.d во время фазы run_stage пытается докачать патч или обновить индекс внутри этой папки, билд упадет с Read-only file system.

active_scripts=()
for STAGE in "${SCRIPTS[@]}"; do
    if ( source "$STAGE" && ffbuild_enabled ); then
        active_scripts+=("$STAGE")
    fi
done

# Генерируем ОТДЕЛЬНЫЙ RUN для каждого активного скрипта
for STAGE in "${active_scripts[@]}"; do
    STAGENAME="$(basename "$STAGE" | sed 's/.sh$//')" # Получаем имя для лога
    to_df "RUN $MOUNTS \\"
    to_df "    echo '>>> $STAGENAME <<<' && run_stage /builder/$STAGE"
done

# Сборка FFmpeg (Флаги конфигурации)
# Собираем переменные для финального ./configure FFmpeg
source "variants/${TARGET}-${VARIANT}.sh"
for addin in ${ADDINS[*]}; do source "addins/${addin}.sh"; done

# Собираем конфигурацию для финального билда

FF_CONFIGURE=""
for script in "${active_scripts[@]}"; do
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
# to_df "COPY . /builder"
# Только в самом конце копируем остальное для финального шага билда
to_df "COPY build.sh /builder/build.sh"
to_df "COPY util /builder/util"
to_df "COPY patches /builder/patches"
# раскомментировать после отладки для сборки FFmpeg
# to_df "COPY variants /builder/variants"
# to_df "COPY addins /builder/addins"
to_df "RUN --mount=type=cache,target=/root/.cache/ccache \\"
to_df "    --mount=from=ffmpeg_src,target=/builder/ffbuild/ffmpeg \\" # Монтируем контекст FFmpeg
to_df "    ./build.sh $TARGET $VARIANT"

to_df "FROM scratch AS artifacts"
to_df "COPY --from=build_stage /opt/ffdest/ /"
