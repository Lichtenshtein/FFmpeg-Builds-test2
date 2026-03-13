#!/bin/bash

set -xe
shopt -s globstar
cd "$(dirname "$0")"
source util/vars.sh "${1:-$TARGET}" "${2:-$VARIANT}" \
    || { echo "ERROR: vars.sh failed in build.sh" >&2; exit 1; }
# Если "Hits" всегда 0, значит, монтирование --mount=type=cache в generate.sh не пробрасывается в build.sh (проверить совпадение путей /root/.cache/ccache).
ccache -s

# Определяем целевой вариант
source "variants/${TARGET}-${VARIANT}.sh"
for addin in ${ADDINS[*]}; do
    source "addins/${addin}.sh"
done

# В GitHub Actions мы уже внутри контейнера. 
# Путь /opt/ffdest должен совпадать с тем, что указан в Dockerfile (generate.sh)
FINAL_DEST="/opt/ffdest"
mkdir -p "$FINAL_DEST"
mkdir -p ffbuild

# Клонирование и патчинг (прямо в текущем слое Docker)
log_info "Using pre-mounted FFmpeg source..."
pushd ffbuild/ffmpeg

# Патчи теперь ищем по имени ветки, пришедшей из ENV
if [[ -d "/builder/patches/ffmpeg/$FFMPEG_BRANCH" ]]; then
    git reset --hard HEAD 2>/dev/null || true
    for patch in "/builder/patches/ffmpeg/$FFMPEG_BRANCH"/*.patch; do
        [[ -e "$patch" ]] || continue
            log_info "${TARGET_MARK} APPLYING PATCH: $patch"
        if patch -p1 < "$patch"; then
            log_info "${CHECK_MARK} SUCCESS: Patch applied."
        else
            log_error "${CROSS_MARK} ERROR: PATCH FAILED!"
            # exit 1 # если нужно прервать сборку при ошибке
        fi
    done
fi

ccache -z # Сброс статистики для чистого лога
log_info "${BROOM_MARK} Cleaning up potential prefix pollution..."
# Удаляем пустые папки или старые логи, если они остались
find /opt/ffbuild -type d -empty -delete

# Force update of pkg-config paths
# export PKG_CONFIG_PATH="/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig"
# export PKG_CONFIG_LIBDIR="/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig"

# Сборка FFmpeg
chmod +x configure

# We save the Target (MinGW) flags into new variables and UNSET the 
# standard ones so the Host compiler (gcc-14) stays clean.

export TARGET_CFLAGS="$CFLAGS"
export TARGET_LDFLAGS="$LDFLAGS"
export TARGET_CXXFLAGS="$CXXFLAGS"
export TARGET_CPPFLAGS="$CPPFLAGS"
export TARGET_LIBS="$LIBS"

# Unset cross-compilation flags so host compiler stays clean during configure
unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS ASFLAGS LIBS

CONF_FLAGS=(
    --prefix="$FFBUILD_DESTPREFIX"
    --pkg-config-flags="--static"
    $FFBUILD_TARGET_FLAGS
    --host-cc="gcc-14"
    --host-cflags="$HOST_CFLAGS"
    --host-ldflags="$HOST_LDFLAGS"
    --extra-cflags="$FF_CFLAGS $FF_CPPFLAGS"
    --extra-ldflags="$FF_LDFLAGS"
    --extra-cxxflags="$FF_CXXFLAGS"
    --extra-libs="$FF_LIBS"
    $FF_CONFIGURE
    --enable-filter=vpp_amf
    --enable-filter=sr_amf
    --enable-runtime-cpudetect
    --enable-pic
    --disable-audiotoolbox
    --disable-videotoolbox
    --disable-securetransport
    --h264-max-bit-depth=14
    --h265-bit-depths=8,9,10,12
    --cc="$CC" --cxx="$CXX" --ar="$AR" --ranlib="$RANLIB" --nm="$NM"
)

log_info "Running FFmpeg configure..."
# Перенаправляем stderr в config.log для полноты картины
if ! ./configure "${CONF_FLAGS[@]}" 2>>ffbuild/config.log; then
    log_error "${CROSS_MARK} Configure failed!"
    log_debug "${LOGS_MARK} ▼ CONTENT OF ffbuild/config.log ▼"
    tail -n 300 ffbuild/config.log
    log_debug "${LOGS_MARK} ▲ END OF ffbuild/config.log ▲"
    exit 1
fi

# Чтобы не перегружать RAM раннера (в среднем 7GB RAM / 2 ядра)
# лучше ограничить параллелизм или вовсе собирать в 1 поток, если включен LTO
# Считаем доступную память в ГБ (через awk, чтобы избежать ошибок деления)
MEM_AVAILABLE=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo)
# Рассчитываем лимит потоков по памяти (1 поток на каждые 2 ГБ)
# Если памяти меньше 2ГБ, результат будет 1
MEM_JOBS=$(( MEM_AVAILABLE / 2 ))
[[ $MEM_JOBS -lt 1 ]] && MEM_JOBS=1
# Выбираем финальное число потоков
CPU_CORES=$(nproc)
if [[ "$FF_CONFIGURE" == *"--enable-lto"* || "$USE_LTO" == "1" ]]; then
    log_warn "${XCLAM_MARK} LTO detected. Forcing single-thread build."
    MAKE_JOBS=1
else
    # Берем минимум между количеством ядер и лимитом по памяти
    MAKE_JOBS=$(( CPU_CORES < MEM_JOBS ? CPU_CORES : MEM_JOBS ))
    log_info "Memory: ${MEM_AVAILABLE}GB, Cores: ${CPU_CORES}. Setting MAKE_JOBS=${MAKE_JOBS}"
fi
# Сборка и установка
make -j"$MAKE_JOBS" $MAKE_V && \
make install && \
make install-doc || log_warn "install-doc failed, but proceeding."
ccache -s

# Подготовка к упаковке (ОЧИСТКА МУСОРА)
popd
BUILD_NAME="ffmpeg_vvceasy-$(./ffbuild/ffmpeg/ffbuild/version.sh ffbuild/ffmpeg)-${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}"
PKG_DIR="ffbuild/pkgroot/$BUILD_NAME"

mkdir -p "$PKG_DIR"
package_variant "$FFBUILD_DESTPREFIX" "$PKG_DIR"
if ! declare -F package_variant >/dev/null; then
    log_error "package_variant not defined - variant script missing or broken"
    exit 1
fi

# Копируем лицензию
[[ -n "$LICENSE_FILE" ]] && cp "ffbuild/ffmpeg/$LICENSE_FILE" "$PKG_DIR/LICENSE.txt"

log_info "${SYNC_MARK} Collecting external DLLs for AI support..."
mkdir -p "$PKG_DIR/bin"
# Копируем все DLL из нашего сборочного префикса в папку с бинарниками
# Это подхватит DLL от OpenVINO, TBB, TensorFlow, LibTorch и других
log_info "Copying OpenVINO plugins..."
# OpenVINO часто ищет файлы openvino_intel_cpu_plugin.dll в той же папке
# Если они лежат в /opt/ffbuild/bin, то всё ок. 
# Но если они в подпапках (runtime/bin/intel64/...), нужно убедиться, что они попали в $PKG_DIR/bin/
if [[ -d "/opt/ffbuild/bin" ]]; then
    find "/opt/ffbuild/bin" -name "*.dll" -exec cp -v {} "$PKG_DIR/bin/" \; || true
else
    log_warn "/opt/ffbuild/bin not found, skipping DLL copy."
fi
# Проверяем наличие критических библиотек (для отладки в логах)
ls -lh "$PKG_DIR/bin/"
# Скачиваем модели для ИИ
# log_info "${DOWN_MARK} Downloading Additional Models for AI..."
# MODELS_FINAL_DIR="$PKG_DIR/models"
# /builder/util/download_models.sh "$MODELS_FINAL_DIR"

# Стриппинг бинарников (удаление отладочных символов)
pushd "$PKG_DIR/bin"
for bin in *.exe; do
    if [[ -f "$bin" ]]; then
        ${FFBUILD_CROSS_PREFIX}strip --strip-unneeded "$bin" || log_warn "strip failed for $bin, continuing."
    fi
done
popd

# Создание архива
OUTPUT_FNAME="${BUILD_NAME}.7z"

# Упаковываем только финальный результат, игнорируя 5ГБ объектных файлов
7z a -mx7 -mmt=on "${FINAL_DEST}/${OUTPUT_FNAME}" "./$PKG_DIR"

# Генерация метаданных для GitHub Actions
if [[ -n "$GITHUB_ACTIONS" ]]; then
    echo "build_name=${BUILD_NAME}" >> "$GITHUB_OUTPUT"
    echo "${OUTPUT_FNAME}" > "${FINAL_DEST}/${TARGET}-${VARIANT}.txt"
    # Вывод статистики ccache (теперь через прямую команду)
    log_info "${CACHE_MARK} CCACHE STATISTICS:"
    ccache -s
fi

# Очистка рабочего пространства ПЕРЕД завершением слоя Docker
# Это освободит место на диске раннера до того, как он начнет экспорт
cp ffbuild/ffmpeg/ffbuild/config.log "${FINAL_DEST}/config.log" 2>/dev/null || true
log_info "Build finished. Cleaning up..."
rm -rf ffbuild/pkgroot ffbuild/config_parts 2>/dev/null || true
exit 0
