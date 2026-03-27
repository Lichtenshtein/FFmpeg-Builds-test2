#!/bin/bash

set -e
# set -xe
shopt -s globstar
cd "$(dirname "$0")"

source util/vars.sh "${1:-$TARGET}" "${2:-$VARIANT}" \
    || { echo "ERROR: vars.sh failed in build.sh" >&2; exit 1; }

ccache -s

export PATH="/usr/local/bin:/usr/bin:/bin:/opt/ct-ng/bin:/opt/wine-stable/bin"

# быстрый дедупликатор
dedupe() {
    local input="$*"
    [[ -z "$input" ]] && return
    # Переводим в одну строку, удаляем мусор
    local clean=$(echo "$input" | tr ' ' '\n' | grep -vE "Package|not|found|error|^$")
    # Удаляем дубликаты, сохраняя ПЕРВОЕ вхождение
    echo "$clean" | awk '!x[$0]++' | xargs
}
# for ldflags
smart_dedupe() {
    local input="$*"
    local clean=$(echo "$input" | tr ' ' '\n' | grep -vE "Package|not|found|error|^$")
    if [[ "$DEDUPE_FLAGS" == "true" ]]; then
        echo "$clean" | awk '!x[$0]++' | xargs
    else
        echo "$clean" | xargs
    fi
}
# for libs
smart_libs_dedupe() {
    local raw_input="$*"
    # чистим мусор и ПУТИ, убираем -lstdc++
    local clean=$(echo "$raw_input" | tr ' ' '\n' | \
        grep -vE "Package|not|found|error|^$|^-L|^-lstdc\+\+$")
    # унифицируем pthread: заменяем -lpthread на -pthread
    clean=$(echo "$clean" | sed 's/^-lpthread$/-pthread/')
    if [[ "$DEDUPE_FLAGS" == "true" ]]; then
    # оставляет только ПОСЛЕДНЕЕ вхождение (важно для порядка линковки)
        echo "$clean" | tac | awk '!x[$0]++' | tac | tr '\n' ' ' | xargs
    else
    # Просто склеиваем в одну строку без удаления дублей
        echo "$clean" | tr '\n' ' ' | xargs
    fi
}

log_info "Loading component variables from cache..."
VARS_DIR="$FFBUILD_PREFIX/config_parts"
# Обнуляем FF_ переменные перед загрузкой, чтобы не было старых хвостов
unset FF_CONFIGURE FF_CFLAGS FF_CXXFLAGS FF_CPPFLAGS FF_LDFLAGS FF_LIBS

# Если файл пустой проблема в run_stage.sh или vars.sh во время сборки компонента.
# Если файл не пустой, но в configure пусто проблема в build.sh (в команде source или dedupe)
VARS_FILE=$(ls ${VARS_DIR}/[0-9]*-zlib.vars 2>/dev/null | head -n 1)
if [[ -f "$ZLIB_VARS_FILE" ]]; then
    log_debug "Checking if .vars (any prefix) not empty..."
    cat "$VARS_FILE"
else
    log_warn "${XCLAM_MARK} Not found with any numeric prefix for .vars"
fi

# Подгрузка .vars файлов в обратном порядке помогает линковщику, так как зависимости (10-, 20-) оказываются в конце строки LIBS.
while IFS= read -r f; do
    log_debug "Sourcing $f"
    source "$f"
done < <(find "$VARS_DIR" -name "*.vars" | sort)

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
    log_error "${CROSS_MARK} FFmpeg source not found at ffbuild/ffmpeg/configure — mount failed?"
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
find /opt/ffbuild -type d -empty -delete || true

# экспортируем флаги перед дедупликацией
export FF_CFLAGS FF_LIBS FF_CONFIGURE FF_LDFLAGS FF_CXXFLAGS FF_CPPFLAGS
# Настройка хостового компилятора (чтобы он не трогал флаги таргета)
export HOST_CFLAGS="-O2 -pipe"
export HOST_CXXFLAGS="-O2 -pipe"
export HOST_LDFLAGS=""

log_debug "--- START of DEBUG audit section ---"
log_debug "DEDUPE_FLAGS is currently set to: '$DEDUPE_FLAGS'"
log_debug "Check if variables are loaded from files:"
log_debug "Raw FF_CFLAGS: $FF_CFLAGS"
log_debug "Raw FF_LDFLAGS: $FF_LDFLAGS"
log_debug "Raw FF_LIBS: $FF_LIBS"

# Подготовка ФИНАЛЬНЫХ флагов (Dedupe + Combine)
# объединяем базовые флаги из vars.sh и накопленные из компонентов
FINAL_CONFIGURE=$(dedupe "$FF_CONFIGURE")
FINAL_CFLAGS=$(dedupe "$CFLAGS" "$FF_CFLAGS" "$CPPFLAGS" "$FF_CPPFLAGS")
FINAL_CXXFLAGS=$(dedupe "$CXXFLAGS" "$FF_CXXFLAGS" "$CPPFLAGS" "$FF_CPPFLAGS")
FINAL_LDFLAGS=$(smart_dedupe "$LDFLAGS" "$FF_LDFLAGS")
FINAL_LDEXEFLAGS=$(smart_dedupe "$LDEXEFLAGS" "$FF_LDEXEFLAGS")
FINAL_LIBS=$(smart_libs_dedupe "$LIBS" "$FF_LIBS")
# Используем группы для решения проблем циклических зависимостей (особенно для Tesseract)
FINAL_LIBS_GROUPED="-Wl,--start-group ${FINAL_LIBS} -Wl,--end-group -Wl,--allow-multiple-definition -lstdc++"

# Unset cross-compilation flags so host compiler stays clean during configure
unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS ASFLAGS LIBS

log_debug "Deduplicated FINAL_CFLAGS: $FINAL_CFLAGS"
log_debug "Deduplicated FINAL_LDFLAGS: $FINAL_LDFLAGS"
log_debug "Deduplicated FINAL_LIBS: $FINAL_LIBS"

log_debug "--- PATH and binaries injection audit ---"
log_debug "${BUILD_MARK} Running flags diagnostic..."
# If the length shows more characters than -O2 (3 chars), there's a hidden character injected by vars.sh or the Docker ENV.
log_debug "Diagnostic: CFLAGS content:"
printf 'HOST_CFLAGS bytes: '; echo -n "$HOST_CFLAGS" | xxd | head -5
printf 'HOST_CXXFLAGS bytes: '; echo -n "$HOST_CXXFLAGS" | xxd | head -5
printf 'FINAL_CFLAGS bytes: '; echo -n "$FINAL_CFLAGS" | xxd | head -5
log_debug "Diagnostic: LDFLAGS content:"
printf 'FINAL_LDFLAGS bytes: '; echo -n "$FINAL_LDFLAGS" | xxd | head -5
# какие именно as и ld видны в системе первыми
log_debug "${SEARCH_MARK} Show current 'as' priority: \n$(which -a as)\n"
log_debug "${SEARCH_MARK} Show current 'ld' priority: \n$(which -a ld)\n"
log_debug "${SEARCH_MARK} Show current 'x86_64-w64-mingw32-gcc' priority: \n$(which -a x86_64-w64-mingw32-gcc)\n"
# содержимое папок тулчейна (только имена файлов)
log_debug "${DIRS_MARK} Contents of /opt/ct-ng/bin (first 20 files):"
ls -F /opt/ct-ng/bin | head -n 20
# папки, где могут прятаться "голые" (без префикса) as/ld
# If which -a as first outputs something in /opt/ct-ng/... rather than /usr/bin/as, this is the cause of the junk at end of line error.
# If in /opt/ct-ng/bin is a file simply as 'as' (without a prefix), then crosstool-ng created symlinks during compilation that poison PATH
# If as --version writes "Target: x86_64-w64-mingw32", and it is called from gcc-14 (host), the build will fail
log_debug "${SEARCH_MARK} Search for all 'as' files in /opt/ct-ng/:"
find /opt/ct-ng -name "as" -type f || true
# что выдает ассемблер на команду версии
as --version | head -n 1
x86_64-w64-mingw32-as --version | head -n 1
log_debug "--- End of DEBUG audit section ---"

# ГЕНЕРАЦИЯ ПЕРЕМЕННЫХ СОСТОЯНИЯ КОМПОНЕНТОВ
log_info "${SEARCH_MARK} Scanning FFmpeg configuration for enabled components..."
# Список компонентов для проверки
COMPONENTS=(libtorch libopenvino libflite audiotoolbox libtensorflow libtesseract libfdk-aac openssl)
# Создаем имя переменной libtesseract -> HAS_LIBTESSERACT
for comp in "${COMPONENTS[@]}"; do
    clean_name="${comp^^}"
    clean_name="${clean_name//-/_}"
    var_name="HAS_${clean_name}"
    if [[ "$FINAL_CONFIGURE" == *"--enable-$comp"* ]]; then
        export "$var_name=1"
        log_debug "Component $comp: ENABLED (${var_name}=1)"
    else
        export "$var_name=0"
        log_debug "Component $comp: DISABLED (${var_name}=0)"
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
    --enable-filter=vpp_amf
    --enable-filter=sr_amf
    --enable-runtime-cpudetect
    --enable-pic
    --enable-static
    --disable-shared
    # flags added by ffmpeg patches, not from mainline FFmpeg
    --h264-max-bit-depth=14
    --h265-bit-depths=8,9,10,12
    --cc="$CC" --cxx="$CXX" --ar="$AR" --ranlib="$RANLIB" --nm="$NM"
)

[[ "$HAS_AUDIOTOOLBOX" == "0" ]] && CONF_FLAGS+=( --disable-audiotoolbox --disable-videotoolbox )
[[ "$HAS_OPENSSL" == "0" ]] && CONF_FLAGS+=( --disable-securetransport )

log_info "${START_MARK} Launching FFmpeg Configure..."
# Функция проверки и валидации флагов ffmpeg SAFE_CONFIGURE
printf "  %s\n" "${CONF_FLAGS[@]}" && check_and_fix_configure

# Перенаправляем stderr в config.log для полноты картины
if ! ./configure "${CONF_FLAGS[@]}" 2>ffbuild/config.log; then
    log_error "${CROSS_MARK} Configure failed!"
    log_debug "${LOGS_MARK} ▼ CONTENT OF ffbuild/config.log ▼"
    tail -n 300 ffbuild/config.log
    log_debug "${LOGS_MARK} ▲ END OF ffbuild/config.log ▲"
    # Копируем лог ошибки даже если билд упал
    cp ffbuild/config.log "${FINAL_DEST}/config.log" || true
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
if [[ "$FINAL_CONFIGURE" =~ --enable-lto ]] || [[ "$USE_LTO" == "1" ]]; then
    log_warn "${XCLAM_MARK} LTO detected. Forcing single-thread build."
    MAKE_JOBS=2
else
    # Берем минимум между количеством ядер и лимитом по памяти
    MAKE_JOBS=$(( CPU_CORES < MEM_JOBS ? CPU_CORES : MEM_JOBS ))
    log_info "Memory: ${MEM_AVAILABLE}GB, Cores: ${CPU_CORES}. Setting MAKE_JOBS=${MAKE_JOBS}"
fi
# Сборка и установка
make -j"$MAKE_JOBS" ${MAKE_V:+$MAKE_V}
make install
make install-doc || log_warn "${XCLAM_MARK} install-doc failed, but proceeding."
ccache -s

popd # Выход из ffbuild/ffmpeg

# Определение версии
if [[ -f "ffbuild/ffmpeg/VERSION" ]]; then
    FFMPEG_VERSION=$(cat ffbuild/ffmpeg/VERSION)-$(date +%Y-%m-%d)
elif [[ -d "ffbuild/ffmpeg/.git" ]]; then
    FFMPEG_VERSION=$(git -C ffbuild/ffmpeg describe --tags --always)-$(date +%Y-%m-%d)
else
    FFMPEG_VERSION=$(date +%Y-%m-%d)
fi

BUILD_NAME="ffmpeg-git-${FFMPEG_VERSION}-${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}"
PKG_DIR="ffbuild/pkgroot/${BUILD_NAME}"

mkdir -p "$PKG_DIR/bin" "$PKG_DIR/doc"

if ! declare -F package_variant >/dev/null; then
    log_error "${CROSS_MARK} package_variant not defined - variant script missing or broken"
    exit 1
fi
package_variant "$FFBUILD_DESTPREFIX" "$PKG_DIR"

# Копируем лицензию ПЕРЕД упаковкой
log_info "${SYNC_MARK} Adding license and logs to package..."
[[ -n "$LICENSE_FILE" ]] && cp "ffbuild/ffmpeg/$LICENSE_FILE" "$PKG_DIR/LICENSE.txt"
cp ffbuild/ffmpeg/ffbuild/config.log "$PKG_DIR/config.log"

log_info "${SYNC_MARK} Collecting external DLLs and plugins..."
# Копируем все DLL из нашего сборочного префикса в папку с бинарниками
# Это подхватит DLL от OpenVINO, TBB, TensorFlow, LibTorch и других
# OpenVINO часто ищет файлы openvino_intel_cpu_plugin.dll в той же папке
# Если они лежат в /opt/ffbuild/bin, то всё ок. 
# Но если они в подпапках (runtime/bin/intel64/...), нужно убедиться, что они попали в $PKG_DIR/bin/
if [[ -d "/opt/ffbuild/bin" ]]; then
    find "/opt/ffbuild/bin" -name "*.dll" -exec cp -v {} "$PKG_DIR/bin/" \; || true
else
    log_warn "${XCLAM_MARK} /opt/ffbuild/bin not found, skipping DLL copy."
fi
# Проверяем наличие критических библиотек (для отладки в логах)
ls -lh "$PKG_DIR/bin/"
# Скачиваем модели для ИИ
log_info "${DOWN_MARK} Downloading Additional Assets..."
MODELS_FINAL_DIR="$PKG_DIR/models"
/builder/util/download_models.sh "$MODELS_FINAL_DIR" "$(pwd)"

# Стриппинг бинарников (удаление отладочных символов)
log_info "${BROOM_MARK} Stripping binaries..."
find "$PKG_DIR/bin" -name "*.exe" -exec ${FFBUILD_CROSS_PREFIX}strip --strip-unneeded {} \;

# Упаковка
OUTPUT_FNAME="${BUILD_NAME}.7z"
log_info "${ARCH_MARK} Creating archive: ${OUTPUT_FNAME}"
# Заходим в pkgroot, чтобы внутри архива не было лишних вложенных папок
pushd ffbuild/pkgroot
7z a -mx7 -mmt=on "${FINAL_DEST}/${OUTPUT_FNAME}" "./${BUILD_NAME}/*"
popd

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
log_info "${CHECK_MARK} Build finished. ${BROOM_MARK} Cleaning up..."
rm -rf ffbuild/pkgroot ffbuild/config_parts 2>/dev/null || true
exit 0
