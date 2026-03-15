#!/bin/bash

set -xe
shopt -s globstar
cd "$(dirname "$0")"

source util/vars.sh "${1:-$TARGET}" "${2:-$VARIANT}" \
    || { echo "ERROR: vars.sh failed in build.sh" >&2; exit 1; }

ccache -s

export PATH="/usr/local/bin:/usr/bin:/bin:/opt/ct-ng/bin:/opt/wine-stable/bin"

# быстрый дедупликатор
dedupe() {
    [[ -z "$1" ]] && return
    echo "$1" | awk 'BEGIN{RS=" "; ORS=" "} !x[$0]++' | xargs
}

# Вспомогательные функции для очистки финальных строк
smart_dedupe() {
    local input="$*"
    if [[ "$DEDUPE_FLAGS" == "true" ]]; then
        # Удаляет дубликаты, сохраняя порядок, и вырезает слова-ошибки (Package not found)
        echo "$input" | tr ' ' '\n' | grep -vE "Package|not|found|error" | awk '!x[$0]++' | xargs
    else
        echo "$input" | grep -vE "Package|not|found|error" | xargs
    fi
}

log_info "Loading component variables from cache..."
VARS_DIR="$FFBUILD_PREFIX/config_parts"
# Обнуляем FF_ переменные перед загрузкой, чтобы не было старых хвостов
unset FF_CONFIGURE FF_CFLAGS FF_CXXFLAGS FF_CPPFLAGS FF_LDFLAGS FF_LIBS

if [[ -d "$VARS_DIR" ]]; then
    # Подгрузка .vars файлов в обратном порядке помогает линковщику, так как зависимости (10-, 20-) оказываются в конце строки LIBS.
    for f in $(ls "$VARS_DIR"/*.vars | sort -r); do
        source "$f"
    done
fi

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
if [[ ! -f "ffbuild/ffmpeg/configure" ]]; then
    log_error "FFmpeg source not found at ffbuild/ffmpeg/configure — mount failed?"
    exit 1
fi
pushd ffbuild/ffmpeg

# Патчи теперь ищем по имени ветки, пришедшей из ENV
if [[ -d "/builder/patches/ffmpeg/$FFMPEG_BRANCH" ]]; then
    # git reset --hard HEAD 2>/dev/null || true
    for patch in "/builder/patches/ffmpeg/$FFMPEG_BRANCH"/*.patch; do
        [[ -e "$patch" ]] || continue
        log_info "${TARGET_MARK} APPLYING PATCH: $(basename "$patch")"
        if patch -p1 < "$patch"; then
            log_info "${CHECK_MARK} SUCCESS: Patch applied."
        else
            log_error "${CROSS_MARK} ERROR: Patch $(basename "$patch") failed to apply cleanly."
            # exit 1 # если нужно прервать сборку при ошибке
        fi
    done
fi

# Сброс статистики для чистого лога
ccache -z 

log_info "${BROOM_MARK} Cleaning up potential prefix pollution..."
# Удаляем пустые папки или старые логи, если они остались
find /opt/ffbuild -type d -empty -delete

# Подготовка ФИНАЛЬНЫХ флагов (Dedupe + Combine)
# объединяем базовые флаги из vars.sh и накопленные из компонентов
FINAL_CONFIGURE=$(dedupe "$FF_CONFIGURE")
FINAL_CFLAGS=$(dedupe "$CFLAGS" "$FF_CFLAGS" "$CPPFLAGS" "$FF_CPPFLAGS")
FINAL_CXXFLAGS=$(dedupe "$CXXFLAGS" "$FF_CXXFLAGS" "$CPPFLAGS" "$FF_CPPFLAGS")
FINAL_LDFLAGS=$(smart_dedupe "$LDFLAGS" "$FF_LDFLAGS")
FINAL_LDEXEFLAGS=$(dedupe "$LDEXEFLAGS" "$FF_LDEXEFLAGS")
FINAL_LIBS=$(smart_dedupe "$LIBS" "$FF_LIBS")

# Настройка хостового компилятора (чтобы он не трогал флаги таргета)
export HOST_CFLAGS="-O2 -pipe"
export HOST_CXXFLAGS="-O2 -pipe"
export HOST_LDFLAGS=""

# Unset cross-compilation flags so host compiler stays clean during configure
unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS ASFLAGS LIBS

log_info "Running flags diagnostic..."
# If the length shows more characters than -O2 (3 chars), there's a hidden character injected by vars.sh or the Docker ENV.
log_info "Diagnostic: CFLAGS content:"
printf 'HOST_CFLAGS bytes: '; echo -n "$HOST_CFLAGS" | xxd | head -5
printf 'HOST_CXXFLAGS bytes: '; echo -n "$HOST_CXXFLAGS" | xxd | head -5
printf 'FINAL_CFLAGS bytes: '; echo -n "$FINAL_CFLAGS" | xxd | head -15
log_info "Diagnostic: LDFLAGS content:"
printf 'FINAL_LDFLAGS bytes: '; echo -n "$FINAL_LDFLAGS" | xxd | head -15

log_info "--- DEBUG: PATH and binaries injection ---"

# какие именно as и ld видны в системе первыми
log_debug "Which 'as': $(which -a as)"
log_debug "Which 'ld': $(which -a ld)"
log_debug "Which 'x86_64-w64-mingw32-gcc': $(which -a x86_64-w64-mingw32-gcc)"

# содержимое папок тулчейна (только имена файлов)
log_debug "Contents of /opt/ct-ng/bin (first 20 files):"
ls -F /opt/ct-ng/bin | head -n 20

# папки, где могут прятаться "голые" (без префикса) as/ld
# If which -a as first outputs something in /opt/ct-ng/... rather than /usr/bin/as, this is the cause of the junk at end of line error.
# If in /opt/ct-ng/bin is a file simply as 'as' (without a prefix), then crosstool-ng created symlinks during compilation that poison PATH
# If as --version writes "Target: x86_64-w64-mingw32", and it is called from gcc-14 (host), the build will fail
log_debug "Search for all 'as' files in /opt/ct-ng/:"
find /opt/ct-ng -name "as" -type f

# что выдает ассемблер на команду версии
as --version | head -n 1
x86_64-w64-mingw32-as --version | head -n 1

log_info "--- END DEBUG ---"

# Формируем массив флагов для configure
read -ra TARGET_FLAGS_ARR <<< "$FFBUILD_TARGET_FLAGS"
read -ra FF_CONF_ARR <<< "$FINAL_CONFIGURE"

chmod +x configure

CONF_FLAGS=(
    --prefix="$FFBUILD_DESTPREFIX"
    --pkg-config-flags="--static"
    "${TARGET_FLAGS_ARR[@]}"
    --host-cc="gcc-14"
    --host-cflags="$HOST_CFLAGS"
    --host-ldflags="$HOST_LDFLAGS"
    --extra-cflags="$FINAL_CFLAGS"
    --extra-cxxflags="$FINAL_CXXFLAGS"
    --extra-ldflags="$FINAL_LDFLAGS"
    --extra-libs="$FINAL_LIBS"
    "${FF_CONF_ARR[@]}"
    --enable-filter=vpp_amf
    --enable-filter=sr_amf
    --enable-runtime-cpudetect
    --enable-pic
    --enable-static
    --disable-shared
    --disable-audiotoolbox
    --disable-videotoolbox
    --disable-securetransport
    # flags added by ffmpeg patches, not from mainline FFmpeg
    --h264-max-bit-depth=14
    --h265-bit-depths=8,9,10,12
    --cc="$CC" --cxx="$CXX" --ar="$AR" --ranlib="$RANLIB" --nm="$NM"
)

log_info "Starting FFmpeg configure..."
# Перенаправляем stderr в config.log для полноты картины
if ! ./configure "${CONF_FLAGS[@]}" 2>>ffbuild/config.log; then
    log_error "${CROSS_MARK} Configure failed. Check ffbuild/config.log!"
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
if [[ "$FF_CONFIGURE" =~ --enable-lto ]] || [[ "$USE_LTO" == "1" ]]; then
    log_warn "${XCLAM_MARK} LTO detected. Forcing single-thread build."
    MAKE_JOBS=1
else
    # Берем минимум между количеством ядер и лимитом по памяти
    MAKE_JOBS=$(( CPU_CORES < MEM_JOBS ? CPU_CORES : MEM_JOBS ))
    log_info "Memory: ${MEM_AVAILABLE}GB, Cores: ${CPU_CORES}. Setting MAKE_JOBS=${MAKE_JOBS}"
fi
# Сборка и установка
make -j"$MAKE_JOBS" ${MAKE_V:+$MAKE_V}
make install
make install-doc || log_warn "install-doc failed, but proceeding."
ccache -s

# Подготовка к упаковке (ОЧИСТКА МУСОРА)
popd
VERSION_SCRIPT="./ffbuild/ffmpeg/ffbuild/version.sh"
if [[ ! -x "$VERSION_SCRIPT" ]]; then
    log_warn "version.sh not found, using 'unknown' as version"
    FFMPEG_VERSION="unknown"
else
    FFMPEG_VERSION="$("$VERSION_SCRIPT" ffbuild/ffmpeg)"
fi
BUILD_NAME="ffmpeg_vvceasy-${FFMPEG_VERSION}-${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}"
PKG_DIR="ffbuild/pkgroot/$BUILD_NAME"

mkdir -p "$PKG_DIR"
if ! declare -F package_variant >/dev/null; then
    log_error "package_variant not defined - variant script missing or broken"
    exit 1
fi
package_variant "$FFBUILD_DESTPREFIX" "$PKG_DIR"

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
