#!/bin/bash

set -e
# set -xe
shopt -s globstar
cd "$(dirname "$0")"

source util/vars.sh "${1:-$TARGET}" "${2:-$VARIANT}" \
    || { echo "ERROR: vars.sh failed in build.sh" >&2; exit 1; }

# Определяем функцию очистки
cleanup() {
    local exit_code=$? # Запоминаем код завершения (0 - успех, >0 - ошибка)
    local duration=$SECONDS # Запоминаем время выполнения
    local elapsed=$(printf '%02dh:%02dm:%02ds' $((duration/3600)) $((duration%3600/60)) $((duration%60)))

    log_info "Running cleanup (Exit code: $exit_code)..."

    # Удаляем временную папку сборки (pkgroot, временные логи и т.д.)
    rm -rf "$FFMPEG_PKG_ROOT" "$VARS_DIR" 2>/dev/null

    # Если сборка упала, можно оставить лог конфига в доступном месте
    if [[ $exit_code -ne 0 && -f "$FFMPEG_CONFIG_LOG" ]]; then
        cp "$FFMPEG_CONFIG_LOG" "$FFBUILD_DESTDIR/failed_config.log" 2>/dev/null || true
    else
    # Просто копируем лог в папку для упаковки
        cp "$FFMPEG_CONFIG_LOG" "$FFBUILD_DESTDIR/config.log" 2>/dev/null || true
    fi

    log_info "Cleanup done."
}

# Устанавливаем ловушку
# EXIT сработает всегда: и при успехе, и при ошибке, и при прерывании
trap cleanup EXIT

log_info "${CACHE_MARK} CCACHE STATISTICS:"
ccache -s
# Сброс статистики для чистого лога
ccache -z > /dev/null
# Сбрасываем счетчик секунд в начале этапа
SECONDS=0

export PATH="/usr/local/bin:/usr/bin:/bin:/opt/ct-ng/bin:/opt/wine-stable/bin"
# Настройка хостового компилятора (чтобы он не трогал флаги таргета)
export HOST_CFLAGS="-march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe"
export HOST_CXXFLAGS="-march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe"
export HOST_LDFLAGS=""

# Инициализация локальных (не экспортируемых!) переменных
# Обнуляем FF_ переменные перед загрузкой, чтобы не было старых хвостов
TOTAL_FF_CONFIGURE=""
TOTAL_FF_CFLAGS=""
TOTAL_FF_CXXFLAGS=""
TOTAL_FF_CPPFLAGS=""
TOTAL_FF_LDFLAGS=""
TOTAL_FF_LDEXEFLAGS=""
TOTAL_FF_LIBS=""

log_info "Loading component variables from cache..."

if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
    log_debug "Checking the connection with the variable caches in .vars"
    # Проверка связи с кэшем (zlib)
    # Если файл пустой проблема в run_stage.sh или vars.sh во время сборки компонента.
    # Если файл не пустой, но в configure пусто проблема в build.sh (в команде source или dedupe)
    # Используем nullglob, чтобы массив был пустым, если файлов нет
    shopt -s nullglob
    Z_FILES=("${VARS_DIR}"/[0-9]*-zlib.vars)
    shopt -u nullglob
    
    if [[ ${#Z_FILES[@]} -gt 0 ]]; then
        ZLIB_VARS="${Z_FILES[0]}"
        if [[ -s "$ZLIB_VARS" ]]; then
            log_debug "Found zlib vars: $ZLIB_VARS"
            cat "$ZLIB_VARS"
        else
            log_warn "zlib.vars found but it is EMPTY. Check run_stage.sh logic."
        fi
    else
        log_info "${SEARCH_MARK} zlib not found in this build chain (ONLY_STAGE filter might have skipped it)." || true
    fi
fi

# Сортировка важна: зависимости (низкие номера) должны быть в начале для CFLAGS 
# и в конце для LIBS (но мы это решим дедупликацией tac)
counter=0
while IFS= read -r f; do
    # Обнуляем временные переменные перед каждым source
    unset FF_CONFIGURE FF_LIBS FF_CFLAGS FF_CXXFLAGS FF_CPPFLAGS FF_LDFLAGS FF_LDEXEFLAGS
    log_debug "Sourcing $f"
    [[ -s "$f" ]] && source "$f"

    # Аккумулируем данные из файла в итоговые переменные
    TOTAL_FF_CONFIGURE+=" ${FF_CONFIGURE:-}"
    TOTAL_FF_LIBS+=" ${FF_LIBS:-}"
    TOTAL_FF_CFLAGS+=" ${FF_CFLAGS:-}"
    TOTAL_FF_LDFLAGS+=" ${FF_LDFLAGS:-}"
    TOTAL_FF_CXXFLAGS+=" ${FF_CXXFLAGS:-}"
    TOTAL_FF_CPPFLAGS+=" ${FF_CPPFLAGS:-}"
    TOTAL_FF_LDEXEFLAGS+=" ${FF_LDEXEFLAGS:-}"

    counter=$((counter + 1))

    # Промежуточная очистка каждых 20 файлов,
    # чтобы не допустить взрывного роста строк в памяти
    if (( counter % 20 == 0 )); then
        TOTAL_FF_LIBS=$(smart_libs_dedupe "$TOTAL_FF_LIBS")
        TOTAL_FF_CFLAGS=$(smart_dedupe "$TOTAL_FF_CFLAGS")
        TOTAL_FF_LDFLAGS=$(smart_dedupe "$TOTAL_FF_LDFLAGS")
        TOTAL_FF_CXXFLAGS=$(smart_dedupe "$TOTAL_FF_CXXFLAGS")
        TOTAL_FF_CPPFLAGS=$(smart_dedupe "$TOTAL_FF_CPPFLAGS")
        TOTAL_FF_LDEXEFLAGS=$(smart_dedupe "$TOTAL_FF_LDEXEFLAGS")
    fi
done < <(find "$VARS_DIR" -name "*.vars" | sort)

if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
    # size guard for early failure diagnosis
    TOTAL_LEN=$(echo "$TOTAL_FF_LIBS $TOTAL_FF_CFLAGS" | wc -c)
    log_debug "Total accumulated flag length: $TOTAL_LEN chars"
    if (( TOTAL_LEN > 50000 )); then
        log_warn "Flag accumulation is suspiciously large ($TOTAL_LEN chars) - check .vars files"
    fi
fi

# загружаем целевой вариант со своими --enable флагами ffbuild_configure()
source "${VARIANTS_DIR}/${TARGET}-${VARIANT}.sh"
for addin in ${ADDINS[*]}; do
    source "${ADDINS_STR}/${addin}.sh"
done

# Capture echo-style output from "variants/${TARGET}-${VARIANT}.sh"
_variant_conf=$(ffbuild_configure 2>/dev/null || true)
_variant_cflags=$(ffbuild_cflags 2>/dev/null || true)
_variant_cppflags=$(ffbuild_cppflags 2>/dev/null || true)
_variant_cxxflags=$(ffbuild_cxxflags 2>/dev/null || true)
_variant_ldflags=$(ffbuild_ldflags 2>/dev/null || true)
_variant_ldexeflags=$(ffbuild_ldexeflags 2>/dev/null || true)
_variant_libs=$(ffbuild_libs 2>/dev/null || true)
[[ -n "$_variant_conf" ]]       && VARIANT_FF_CONFIGURE+=" ${FF_CONFIGURE} ${_variant_conf}"
[[ -n "$_variant_cflags" ]]     && VARIANT_FF_CFLAGS+=" ${FF_CFLAGS} ${_variant_cflags}"
[[ -n "$_variant_cppflags" ]]   && VARIANT_FF_CPPFLAGS+=" ${FF_CPPFLAGS} ${_variant_cppflags}"
[[ -n "$_variant_cxxflags" ]]   && VARIANT_FF_CXXFLAGS+=" ${FF_CXXFLAGS} ${_variant_cxxflags}"
[[ -n "$_variant_ldflags" ]]    && VARIANT_FF_LDFLAGS+=" ${FF_LDFLAGS} ${_variant_ldflags}"
[[ -n "$_variant_ldexeflags" ]] && VARIANT_FF_LDEXEFLAGS+=" ${FF_LDEXEFLAGS} ${_variant_ldexeflags}"
[[ -n "$_variant_libs" ]]       && VARIANT_FF_LIBS+=" ${FF_LIBS} ${_variant_libs}"

# Клонирование и патчинг (прямо в текущем слое Docker)
log_info "Using pre-mounted FFmpeg source..."
if [[ ! -f "$FFMPEG_SOURCE_DIR/configure" ]]; then
    log_error "FFmpeg source not found at $FFMPEG_SOURCE_DIR/configure! Check if it is mounted correctly."
    exit 1
fi

pushd "$FFMPEG_SOURCE_DIR"

if [[ "$FFMPEG_PATCHES" == "1" ]]; then
    log_info_line
    log_info "${SEARCH_MARK} Looking for FFmpeg patches..."
    # Патчи ищем по имени ветки, пришедшей из ENV
    if [[ -d "$PATCHES_DIR/ffmpeg/$FFMPEG_BRANCH" ]]; then
        # git reset --hard HEAD 2>/dev/null || true
        for patch in "$PATCHES_DIR/ffmpeg/$FFMPEG_BRANCH"/*.patch; do
            [[ -e "$patch" ]] || continue
            log_info "${TARGET_MARK} APPLYING PATCH: $(basename "$patch")"
            if patch -p1 < "$patch"; then
                log_info "${CHECK_MARK} SUCCESS: Patch applied."
            else
                log_error "ERROR: Patch $(basename "$patch") failed to apply cleanly."
                # exit 1 # если нужно прервать сборку при ошибке
            fi
        done
        log_info_line
    fi
fi

[[ "$DEDUPE_FLAGS" == "1" ]] && log_info "${BROOM_MARK} Deduplicating ALL flags..."

# Подготовка ФИНАЛЬНЫХ флагов (Dedupe + Combine)
# объединяем базовые флаги из vars.sh и накопленные из компонентов
# Конфигурация: сначала базовые, потом специфичные для варианта
FINAL_CONFIGURE=$(smart_dedupe "$TOTAL_FF_CONFIGURE" "$VARIANT_FF_CONFIGURE")
# CFLAGS: Сначала кладем CPPFLAGS, затем CFLAGS компонентов, затем варианта.
# Так как мы оставляем ПЕРВОЕ вхождение, самые важные флаги должны быть левее.
FINAL_CFLAGS=$(smart_dedupe "$CFLAGS" "$CPPFLAGS" "$TOTAL_FF_CFLAGS" "$TOTAL_FF_CPPFLAGS" "$VARIANT_FF_CFLAGS" "$VARIANT_FF_CPPFLAGS")
FINAL_CXXFLAGS=$(smart_dedupe "$CXXFLAGS" "$CPPFLAGS" "$TOTAL_FF_CXXFLAGS" "$TOTAL_FF_CPPFLAGS" "$VARIANT_FF_CXXFLAGS" "$VARIANT_FF_CPPFLAGS")
# LDFLAGS: Аналогично флагам компиляции
FINAL_LDFLAGS=$(smart_dedupe "$LDFLAGS" "$TOTAL_FF_LDFLAGS" "$VARIANT_FF_LDFLAGS")
FINAL_LDEXEFLAGS=$(smart_dedupe "$LDEXEFLAGS" "$TOTAL_FF_LDEXEFLAGS")
# LIBS: ОБРАТНАЯ логика; smart_libs_dedupe оставляет ПОСЛЕДНЕЕ вхождение, 
# базовые системные либы ($LIBS) лучше ставить в начало списка аргументов, 
# чтобы если компонент принес свою версию, она вытеснила базовую в конец (право).
FINAL_LIBS=$(smart_libs_dedupe "$LIBS" "$TOTAL_FF_LIBS" "$ADDITIONAL_LIBS" "$VARIANT_FF_LIBS")

# Используем группы для решения проблем циклических зависимостей (особенно для Tesseract)
FINAL_LIBS_GROUPED="-Wl,--start-group ${FINAL_LIBS} -Wl,--end-group -Wl,--allow-multiple-definition -lstdc++"

if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
    log_info_line
    log_info "### ${BUILD_MARK} Start of DEBUG audit section"
    log_info_line

    log_debug "RAW CONFIGURE: \n$TOTAL_FF_CONFIGURE"
    log_debug "RAW CFLAGS: \n$TOTAL_FF_CFLAGS"
    log_debug "RAW LDFLAGS: \n$TOTAL_FF_LDFLAGS"
    log_debug "RAW LIBS: \n$TOTAL_FF_LIBS"

    log_debug "DEDUPED CONFIGURE: \n${FINAL_CONFIGURE}"
    log_debug "DEDUPED CFLAGS: \n${FINAL_CFLAGS}"
    log_debug "DEDUPED LDFLAGS: \n${FINAL_LDFLAGS}"
    log_debug "DEDUPED LIBS: \n${FINAL_LIBS}"

    log_debug "STATS:\nCONF: ${#FINAL_CONFIGURE} chars\nCFLAGS: ${#FINAL_CFLAGS} chars\nLDFLAGS: ${#FINAL_LDFLAGS} chars\nLIBS: ${#FINAL_LIBS_GROUPED} chars"

    # If the length shows more characters than -O2 (3 chars), there's a hidden character injected by vars.sh or the Docker ENV.
    log_debug 'DIAGNOSTIC: HOST_CFLAGS bytes:'
    echo -n "$HOST_CFLAGS" | xxd | head -5
    log_debug 'DIAGNOSTIC: HOST_CXXFLAGS bytes:'
    echo -n "$HOST_CXXFLAGS" | xxd | head -5
    log_debug 'DIAGNOSTIC: FINAL_CFLAGS bytes:'
    echo -n "$FINAL_CFLAGS" | xxd | head -5
    log_debug 'DIAGNOSTIC: FINAL_LDFLAGS bytes:'
    echo -n "$FINAL_LDFLAGS" | xxd | head -5
    # какие именно as и ld видны в системе первыми
    log_debug "PRIORITY: 'as' priority: \n$(which -a as)"
    log_debug "PRIORITY: 'ld' priority: \n$(which -a ld)"
    log_debug "PRIORITY: 'x86_64-w64-mingw32-gcc' priority: \n$(which -a x86_64-w64-mingw32-gcc)"
    # содержимое папок тулчейна (только имена файлов)
    log_debug "${DIRS_MARK} Contents of /opt/ct-ng/bin (first 20 files):"
    ls -F /opt/ct-ng/bin | head -n 20
    # папки, где могут прятаться "голые" (без префикса) as/ld
    # If which -a as first outputs something in /opt/ct-ng/... rather than /usr/bin/as, this is the cause of the junk at end of line error.
    # If in /opt/ct-ng/bin is a file simply as 'as' (without a prefix), then crosstool-ng created symlinks during compilation that poison PATH
    # If as --version writes "Target: x86_64-w64-mingw32", and it is called from gcc-14 (host), the build will fail
    log_debug "${SEARCH_MARK} Search for all 'as' files in /opt/ct-ng/:"
    find /opt/ct-ng -name "as" -type f || true
    log_debug "GNU assembler version:"
    # что выдает ассемблер на команду версии
    as --version | head -n 1
    x86_64-w64-mingw32-as --version | head -n 1

    # ГЕНЕРАЦИЯ ПЕРЕМЕННЫХ СОСТОЯНИЯ КОМПОНЕНТОВ
    log_debug "${SEARCH_MARK} Scanning FFmpeg configuration for enabled components..."
    # Список компонентов для проверки
    COMPONENTS=(libtorch libopenvino libflite audiotoolbox libtensorflow libtesseract libfdk-aac openssl amf)
    # Создаем имя переменной libtesseract -> HAS_LIBTESSERACT
    for comp in "${COMPONENTS[@]}"; do
        clean_name="${comp^^}"
        clean_name="${clean_name//-/_}"
        var_name="HAS_${clean_name}"
        if [[ "$FINAL_CONFIGURE" == *"--enable-$comp"* ]]; then
            export "$var_name=1"
            log_debug "Component $comp: ${GREEN}ENABLED${NC} (${var_name}=1)"
        else
            export "$var_name=0"
            log_debug "Component $comp: ${RED}DISABLED${NC} (${var_name}=0)"
        fi
    done
    # Специальная обработка для ASAN (fdk-aac); should be at the end of all flags.
    # Вообще-то, я не помню нахера ASAN нужен fdk-aac. Вырубаем.
    # if [[ "$HAS_LIBFDK_AAC" == "0" ]]; then
        # ASAN_CFLAGS=""
        # ASAN_CXXFLAGS=""
        # ASAN_LDFLAGS=""
    # else
        # ASAN_CFLAGS=" -fsanitize=address,undefined -fno-omit-frame-pointer"
        # ASAN_CXXFLAGS=" -fsanitize=address,undefined -fno-omit-frame-pointer"
        # ASAN_LDFLAGS="-static-libasan -fsanitize=address,undefined "
        # log_info "ASAN flags enabled due to fdk-aac presence."
    # fi

    log_info_line
    log_info "### ${BUILD_MARK} End of DEBUG audit section"
fi

# экспортируем флаги
export FINAL_CONFIGURE FINAL_CFLAGS FINAL_CXXFLAGS FINAL_LDFLAGS FINAL_LDEXEFLAGS FINAL_LIBS_GROUPED
# Очищаем тяжелые переменные, чтобы не мешать запуску процессов
unset TOTAL_FF_CONFIGURE TOTAL_FF_LIBS TOTAL_FF_CFLAGS TOTAL_FF_CXXFLAGS TOTAL_FF_CPPFLAGS TOTAL_FF_LDFLAGS
# Unset cross-compilation flags so host compiler stays clean during configure
unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS LDEXEFLAGS ASFLAGS LIBS

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
    --extra-cflags="${FINAL_CFLAGS}${ASAN_CFLAGS}"
    --extra-cxxflags="${FINAL_CXXFLAGS}${ASAN_CXXFLAGS}"
    --extra-ldflags="${ASAN_LDFLAGS}${FINAL_LDFLAGS}"
    --extra-ldexeflags="$FINAL_LDEXEFLAGS"
    --extra-libs="${FINAL_LIBS_GROUPED}"
    "${FF_CONF_ARR[@]}"
    --enable-runtime-cpudetect
    --enable-opengl
    --enable-pic
    --enable-static
    --disable-shared
    --disable-debug
    --cc="$CC" --cxx="$CXX" --ar="$AR" --ranlib="$RANLIB" --nm="$NM"
)

[[ "$HAS_AUDIOTOOLBOX" == "0" ]] && CONF_FLAGS+=( --disable-audiotoolbox --disable-videotoolbox )
[[ "$HAS_OPENSSL" == "0" ]] && CONF_FLAGS+=( --disable-securetransport )
[[ "$HAS_AMF" == "1" ]] && CONF_FLAGS+=( --enable-filter=vpp_amf --enable-filter=sr_amf )
# flags added by ffmpeg patches, not from mainline FFmpeg
[[ "$FFMPEG_PATCHES" == "true" ]] && CONF_FLAGS+=( --h264-max-bit-depth=14 --h265-bit-depths=8,9,10,12 )

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
if [[ "$FINAL_CONFIGURE" =~ --enable-lto ]] || [[ "$USE_LTO" == "1" ]]; then
    log_warn "LTO detected. Forcing dual-thread build."
    MAKE_JOBS=2
else
    # Берем минимум между количеством ядер и лимитом по памяти
    MAKE_JOBS=$(( CPU_CORES < MEM_JOBS ? CPU_CORES : MEM_JOBS ))
    log_info_line
    log_info "### ${CACHE_MARK} HOST: MEMORY: ${MEM_AVAILABLE}GB, CPU CORES: ${CPU_CORES}; Setting MAKE_JOBS=${MAKE_JOBS}"
fi

log_info_line
log_info "### ${START_MARK} Launching FFmpeg Configure..."
log_info_line
# Функция проверки и валидации флагов ffmpeg SAFE_CONFIGURE
check_and_fix_configure && printf "  %s\n" "${CONF_FLAGS[@]}"

# Перенаправляем stderr в config.log для полноты картины
if ! ./configure "${CONF_FLAGS[@]}" 2>"$FFMPEG_CONFIG_LOG"; then
    log_error "Configure failed!"
    log_debug "${LOGS_MARK} ▼ CONTENT OF $FFMPEG_CONFIG_LOG ▼"
    tail -n 300 "$FFMPEG_CONFIG_LOG"
    log_debug "${LOGS_MARK} ▲ END OF $FFMPEG_CONFIG_LOG ▲"
    exit 1
fi

# Сборка и установка ffmpeg
make -j"$MAKE_JOBS" ${MAKE_V:+$MAKE_V}
make install
make install-doc || log_warn "install-doc failed, but proceeding."

log_info "${DIRS_MARK} Leaving FFmpeg folder..."
popd # Выход из ffbuild/ffmpeg

log_info "${BROOM_MARK} Cleaning up potential prefix pollution..."
# Удаляем пустые папки или старые логи, если они остались
find /opt/ffbuild -type d -empty -delete || true

# Определение версии
if [[ -f "$FFMPEG_SOURCE_DIR/VERSION" ]]; then
    FFMPEG_VERSION=$(cat $FFMPEG_SOURCE_DIR/VERSION)-$(date +%Y-%m-%d)
elif [[ -d "$FFMPEG_SOURCE_DIR/.git" ]]; then
    FFMPEG_VERSION=$(git -C $FFMPEG_SOURCE_DIR describe --tags --always)-$(date +%Y-%m-%d)
else
    FFMPEG_VERSION=$(date +%Y-%m-%d)
fi

BUILD_NAME="ffmpeg-git-${FFMPEG_VERSION}-${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}"
PKG_DIR="$FFMPEG_PKG_ROOT/${BUILD_NAME}"

mkdir -p "$PKG_DIR/bin" "$PKG_DIR/doc"

if ! declare -F package_variant >/dev/null; then
    log_error "package_variant not defined - variant script missing or broken"
    exit 1
fi
package_variant "$FFBUILD_DESTPREFIX" "$PKG_DIR"

# Копируем лицензию ПЕРЕД упаковкой
log_info "${SYNC_MARK} Adding license and logs to package..."
[[ -n "$LICENSE_FILE" ]] && cp "$FFMPEG_SOURCE_DIR/$LICENSE_FILE" "$PKG_DIR/LICENSE.txt"
cp "$FFMPEG_CONFIG_LOG" "$PKG_DIR/config.log" || true

# Копируем все DLL из нашего сборочного префикса в папку с бинарниками
# Это подхватит DLL от OpenVINO, TBB, TensorFlow, LibTorch и других
# OpenVINO часто ищет файлы openvino_intel_cpu_plugin.dll в той же папке
# Если они лежат в /opt/ffbuild/bin, то всё ок. 
# Но если они в подпапках (runtime/bin/intel64/...), нужно убедиться, что они попали в $PKG_DIR/bin/
if [[ -d "$FFBUILD_PREFIX/bin" ]]; then
    find "$FFBUILD_PREFIX/bin" -name "*.dll" -exec cp -v {} "$PKG_DIR/bin/" \; || true
    log_info "${SYNC_MARK} Collecting external DLLs and plugins..."
else
    log_warn "$FFBUILD_PREFIX/bin not found! Skipping DLLs copy."
fi

# Проверяем наличие критических библиотек (для отладки в логах)
ls -lh "$PKG_DIR/bin/"

# Скачиваем модели и ассеты
log_info "${DOWN_MARK} Checking for additional assets..."

export ASSETS_DIR="$PKG_DIR/assets"
mkdir -p "$ASSETS_DIR"
"$UTIL_DIR"/download_assets.sh "$ASSETS_DIR" "$(pwd)" || log_warn "Assets download failed, but continuing..."

# Стриппинг бинарников (удаление отладочных символов)
log_info "${BROOM_MARK} Stripping binaries..."
find "$PKG_DIR/bin" -name "*.exe" -exec ${FFBUILD_CROSS_PREFIX}strip --strip-unneeded {} \;

# Упаковка
log_info "${ARCH_MARK} Creating archive: ${BUILD_NAME}.7z"
# Заходим в pkgroot, чтобы внутри архива не было лишних вложенных папок
pushd "$FFMPEG_PKG_ROOT"
7z a -mx7 -mmt=on "$FFBUILD_DESTDIR/$BUILD_NAME" "./${BUILD_NAME}.7z/*"
popd

# Генерация метаданных для GitHub Actions
if [[ -n "$GITHUB_ACTIONS" ]]; then
    echo "build_name=${BUILD_NAME}" >> "$GITHUB_OUTPUT"
    echo "${BUILD_NAME}.7z" > "$FFBUILD_DESTDIR/${TARGET}-${VARIANT}.txt"
fi

log_info "${CHECK_MARK} Build finished after ${PURPLE}${elapsed}${NC}"

# Вывод статистики ccache
log_info "${CACHE_MARK} CCACHE STATISTICS:"
ccache -s

exit 0