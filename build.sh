#!/bin/bash

set -e
# set -xe
shopt -s globstar
cd "$(dirname "$0")"

source util/vars.sh "${1:-$TARGET}" "${2:-$VARIANT}" \
    || { echo "ERROR: vars.sh failed in build.sh" >&2; exit 1; }

log_info "${CACHE_MARK} CCACHE STATISTICS:"
ccache -s
# Сброс статистики для чистого лога
ccache -z > /dev/null
# Сбрасываем счетчик секунд в начале этапа
SECONDS=0

# Определяем функцию очистки
cleanup() {
    # Вывод статистики ccache
    log_info "${CACHE_MARK} CCACHE STATISTICS:"
    ccache -s

    local exit_code=$? # Запоминаем код завершения (0 - успех, >0 - ошибка)

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

# if [[ "${USE_WINE:-0}" = "1" ]]; then
#     export PATH="/usr/local/bin:/usr/bin:/bin:/opt/ct-ng/bin:/opt/wine-stable/bin"
# else
#     # export PATH="/usr/local/bin:/usr/bin:/bin:/opt/ct-ng/bin"
#     export PATH="/opt/ct-ng/bin:/opt/cargo/bin:/usr/local/bin:/usr/bin:/bin"
# fi

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
# source "${VARIANTS_DIR}/${TARGET}-${VARIANT}.sh"
# for addin in ${ADDINS[*]}; do
    # source "${ADDINS_STR}/${addin}.sh"
# done
if [[ -n "$ADDINS_STR" ]]; then
    IFS='-' read -ra ADDINS_ARRAY <<< "$ADDINS_STR"
    for addin in "${ADDINS_ARRAY[@]}"; do
        [[ -z "$addin" ]] && continue
        addin_file="${ADDINS_DIR}/${addin}.sh"
        if [[ -f "$addin_file" ]]; then
            log_debug "Sourcing addin: $addin"
            source "$addin_file"
        else
            log_error "Addin file not found: $addin_file"
            exit 1
        fi
    done
fi

# Определяем целевой вариант (они могут добавить свои --enable)
VARIANT_SCRIPT="${VARIANTS_DIR}/${TARGET}-${VARIANT}.sh"
if [[ -f "$VARIANT_SCRIPT" ]]; then
    log_info "Sourcing variant script: $VARIANT_SCRIPT"
    source "$VARIANT_SCRIPT"
else
    log_error "Variant script not found: $VARIANT_SCRIPT"
    exit 1
fi

# Capture echo-style output from "variants/${TARGET}-${VARIANT}.sh"
_variant_conf=$(ffbuild_configure 2>/dev/null || true)
_variant_cflags=$(ffbuild_cflags 2>/dev/null || true)
_variant_cppflags=$(ffbuild_cppflags 2>/dev/null || true)
_variant_cxxflags=$(ffbuild_cxxflags 2>/dev/null || true)
_variant_ldflags=$(ffbuild_ldflags 2>/dev/null || true)
_variant_ldexeflags=$(ffbuild_ldexeflags 2>/dev/null || true)
_variant_libs=$(ffbuild_libs 2>/dev/null || true)
[[ -n "$_variant_conf" ]]       && VARIANT_FF_CONFIGURE="${_variant_conf}"
[[ -n "$_variant_cflags" ]]     && VARIANT_FF_CFLAGS="${_variant_cflags}"
[[ -n "$_variant_cppflags" ]]   && VARIANT_FF_CPPFLAGS="${_variant_cppflags}"
[[ -n "$_variant_cxxflags" ]]   && VARIANT_FF_CXXFLAGS="${_variant_cxxflags}"
[[ -n "$_variant_ldflags" ]]    && VARIANT_FF_LDFLAGS="${_variant_ldflags}"
[[ -n "$_variant_ldexeflags" ]] && VARIANT_FF_LDEXEFLAGS="${_variant_ldexeflags}"
[[ -n "$_variant_libs" ]]       && VARIANT_FF_LIBS="${_variant_libs}"

# Клонирование и патчинг (прямо в текущем слое Docker)
log_info "Using pre-mounted FFmpeg source..."
if [[ ! -f "$FFMPEG_SOURCE_DIR/configure" ]]; then
    log_error "FFmpeg source not found at $FFMPEG_SOURCE_DIR/configure! Check if it is mounted correctly."
    exit 1
fi

pushd "$FFMPEG_SOURCE_DIR"

# АВТО-ПАТЧИНГ
if [[ "$FFMPEG_PATCHES" == "1" ]]; then
    apply_ffmpeg_patches
fi

# Удаляем жесткий -static и -Wl,-Bstatic из базовых флагов линковщика
# LDFLAGS=$(echo " ${LDFLAGS} " | sed -e 's/ -static / /g' -e 's/ -Wl,-Bstatic / /g' | xargs)
[[ "${PREFER_SHARED}" != "1" ]] && export LDEXEFLAGS="-static -static-libgcc -static-libstdc++"

[[ "$DEDUPE_FLAGS" == "1" ]] && log_info "${BROOM_MARK} Deduplicating ALL flags..."

# Подготовка ФИНАЛЬНЫХ флагов (Dedupe + Combine)
# объединяем базовые флаги из vars.sh и накопленные из компонентов
# Конфигурация: сначала базовые, потом специфичные для варианта
FINAL_CONFIGURE=$(smart_dedupe "$TOTAL_FF_CONFIGURE" "$VARIANT_FF_CONFIGURE")
# CFLAGS: Сначала кладем CPPFLAGS, затем CFLAGS компонентов, затем варианта.
# Так как мы оставляем ПЕРВОЕ вхождение, самые важные флаги должны быть левее.
FINAL_CFLAGS=$(smart_dedupe "$CFLAGS" "$CPPFLAGS" "$TOTAL_FF_CFLAGS" "$TOTAL_FF_CPPFLAGS" "$VARIANT_FF_CFLAGS" "$VARIANT_FF_CPPFLAGS" | sed 's/-std=gnu17/-std=gnu23/g')
FINAL_CXXFLAGS=$(smart_dedupe "$CXXFLAGS" "$CPPFLAGS" "$TOTAL_FF_CXXFLAGS" "$TOTAL_FF_CPPFLAGS" "$VARIANT_FF_CXXFLAGS" "$VARIANT_FF_CPPFLAGS")
# LDFLAGS: Аналогично флагам компиляции
FINAL_LDFLAGS=$(smart_dedupe "$LDFLAGS" "$TOTAL_FF_LDFLAGS" "$VARIANT_FF_LDFLAGS")
FINAL_LDEXEFLAGS=$(smart_dedupe "$LDEXEFLAGS" "$TOTAL_FF_LDEXEFLAGS")
# LIBS: ОБРАТНАЯ логика; smart_libs_dedupe оставляет ПОСЛЕДНЕЕ вхождение, 
# базовые системные либы ($LIBS) лучше ставить в начало списка аргументов, 
# чтобы если компонент принес свою версию, она вытеснила базовую в конец (право).
FINAL_LIBS=$(smart_libs_dedupe "$LIBS" "$TOTAL_FF_LIBS" "$ADDITIONAL_LIBS" "$VARIANT_FF_LIBS")

# =======================================
# GENERATION OF COMPONENT STATE VARIABLES
# =======================================
log_debug "${SEARCH_MARK} Scanning FFmpeg configuration for enabled components..."
# Список компонентов для проверки
COMPONENTS=(libtorch libopenvino libflite audiotoolbox libtensorflow libtesseract libfdk-aac openssl amf frei0r whisper)
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

# ==================================
# ASAN PROCESSING (If enabled)
# ==================================
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

# ==================================
# OPENVINO PROCESSING (If enabled)
# ==================================
# if [[ "$HAS_LIBOPENVINO" == "1" ]]; then
    # Список библиотек OpenVINO, которые пришли из pkg-config и vars.sh
    # cut them out from the general list so that they are not affected by the global -Bstatic
    # accumulate into a dynamic group
    # log_info "${TARGET_MARK} Setting up hybrid linking for OpenVINO..."
    # OV_TARGET_LIBS="-lopenvino -lopenvino_c"
    # for lib in ${OV_TARGET_LIBS}; do
        # FINAL_LIBS=$(echo " ${FINAL_LIBS} " | sed "s/ ${lib} / /g")
    # done
    # DYNAMIC_LIBS_ACCUMULATOR+="${OV_TARGET_LIBS} "
# fi

# ==========================================
# TENSORFLOW PROCESSING
# ==========================================
# if [[ "$HAS_LIBTENSORFLOW" == "1" ]]; then
    # log_info "${TARGET_MARK} Setting up hybrid linking for TensorFlow..."
    # TF_TARGET_LIBS="-ltensorflow"
    # for lib in ${TF_TARGET_LIBS}; do
        # FINAL_LIBS=$(echo " ${FINAL_LIBS} " | sed "s/ ${lib} / /g")
    # done
    # DYNAMIC_LIBS_ACCUMULATOR+="${TF_TARGET_LIBS} "
# fi

# ==========================================
# LIBTORCH PROCESSING
# ==========================================
if [[ "$HAS_LIBTORCH" == "1" ]]; then
    # ls -lh /opt/ffbuild/lib/libtorch_cpu.a || true
    # TORCH_LIBS="-ltorch -ltorch_cpu -lc10"
    log_info "${TARGET_MARK} Setting up hybrid linking for LibTorch..."
    TORCH_LIBS="-lXNNPACK -lasmjit -lc10 -lc10d -lcaffe2_detectron_ops -lcaffe2_module_test_dynamic -lclog -lcpuinfo -ldnnl -lfbgemm -lfbjni -lkineto -lmkldnn -lprotobuf-lite -lprotoc -lpthreadpool -lpytorch_jni -ltorch -ltorch_cpu "
    for lib in ${TORCH_LIBS}; do
        FINAL_LIBS=$(echo " ${FINAL_LIBS} " | sed "s/ ${lib} / /g")
    done
    DYNAMIC_LIBS_ACCUMULATOR+="${TORCH_LIBS} "
    sed -i '/at::detail::getXPUHooks/d' libavfilter/dnn/dnn_backend_torch.cpp
    sed -i 's/device.is_xpu()/false/g' libavfilter/dnn/dnn_backend_torch.cpp
    sed -i 's/at::hasXPU()/false/g' libavfilter/dnn/dnn_backend_torch.cpp
fi

# ==========================================
# WHISPER PROCESSING
# ==========================================
# if [[ "$HAS_WHISPER" == "1" ]]; then
    # log_info "${TARGET_MARK} Setting up hybrid dynamic linking for Whisper..."
    # WHISPER_DYNAMIC_LIBS="-lwhisper -lggml"
    # for lib in ${WHISPER_DYNAMIC_LIBS}; do
        # FINAL_LIBS=$(echo " ${FINAL_LIBS} " | sed "s/ ${lib} / /g")
    # done
    # for lib in -lopenvino -lopenvino_c; do
        # FINAL_LIBS=$(echo " ${FINAL_LIBS} " | sed "s/ ${lib} / /g")
    # done
    # DYNAMIC_LIBS_ACCUMULATOR+="-Wl,-Bdynamic ${WHISPER_DYNAMIC_LIBS} -Wl,-Bstatic "
# fi

# Чистим лишние пробелы, которые мог оставить sed
# FINAL_LIBS=$(echo ${FINAL_LIBS} | xargs)

# Формируем изолированную строку для переключения контекста линкера
# -Wl,-Bdynamic переключает MinGW ld в режим импорта DLL.
# -Wl,-Bstatic возвращает линкер в режим сборки честной статики
# HYBRID_DYNAMIC_FLAGS=""
# if [[ -n "${DYNAMIC_LIBS_ACCUMULATOR}" ]]; then
    # HYBRID_DYNAMIC_FLAGS="-Wl,-Bdynamic ${DYNAMIC_LIBS_ACCUMULATOR} -Wl,-Bstatic "
# fi

# Используем группы для решения проблем циклических зависимостей
FINAL_LIBS_GROUPED="-Wl,--start-group ${HYBRID_DYNAMIC_FLAGS}${FINAL_LIBS} -Wl,--end-group -lstdc++"

if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
    log_info_line
    log_info "### ${BUILD_MARK} Start of DEBUG audit section"
    log_info_line

    # Проверка путей (PATH)
    log_debug "${DIRS_MARK} Current PATH:\n$PATH"

    check_tool() {
        local name=$1
        local cmd=$2
        local path=$(which $cmd 2>/dev/null)
        if [[ -n "$path" ]]; then
            local version=$($cmd --version 2>&1 | head -n 1)
            log_debug "${CHECK_MARK} $name: ${CYAN}$path${NC}\n(${GREY_B}$version${NC})"
        else
            log_error "$name ($cmd) NOT FOUND!"
        fi
    }

    log_debug "FFBUILD_PREFIX:\n$FFBUILD_PREFIX"
    log_debug "FFBUILD_DESTDIR:\n$FFBUILD_DESTDIR"
    log_debug "PKG_DIR:\n$PKG_DIR"
    log_debug "INSTALL_ROOT:\n$INSTALL_ROOT"

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

    # Если AS или LD показывают /usr/bin/... вместо /opt/ct-ng/... — это 100% причина ошибок и проблем со ненайденными заголовками
    # Версии кросс-инструментов должны совпадать с ct-ng (2.46.0 / 15.2.0), а не Ubuntu (2.42).
    check_tool "CC" "$CC"
    check_tool "CXX" "$CXX"
    check_tool "AS" "x86_64-w64-mingw32-as"
    check_tool "AR" "$AR"
    check_tool "NM" "$NM"
    check_tool "RANLIB" "$RANLIB"
    check_tool "LD" "$LD"
    check_tool "STRIP" "x86_64-w64-mingw32-strip"

    # Проверка ccache
    if command -v ccache &>/dev/null; then
        log_info "${CACHE_MARK} ccache found. Configuration:"
        log_debug "CCACHE_PATH: $CCACHE_PATH"
        log_debug "REAL_CC: $(ccache -p | grep compiler_check || echo 'default')"
    else
        log_warn "ccache not in use"
    fi

    # Проверка видимости библиотек ffnvcodec (твоя ошибка cuda_llvm)
    log_info "${SEARCH_MARK} Checking ffnvcodec in pkg-config:"
    if pkg-config --exists ffnvcodec; then
        log_info "${CHECK_MARK} ffnvcodec found: $(pkg-config --modversion ffnvcodec)"
        log_debug "Cflags: $(pkg-config --cflags ffnvcodec)"
    else
        log_error "ffnvcodec NOT FOUND in PKG_CONFIG_PATH ($PKG_CONFIG_PATH)"
        log_debug "Contents of /opt/ffbuild/lib/pkgconfig:"
        ls -1 /opt/ffbuild/lib/pkgconfig/*.pc 2>/dev/null | xargs -n1 basename | sed 's/^/ /'
    fi

    # Специфическая проверка для LTO (наличие плагинов)
    log_info "${BUILD_MARK} Checking LTO support in AR:"
    if $AR --help | grep -q "plugin"; then
        log_info "${CHECK_MARK} AR supports plugins (required for LTO)"
    else
        log_warn "AR may not support LTO plugins! Make sure you're using gcc-ar."
    fi

    log_debug "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
    which pkg-config

    log_info_line
    log_info "### ${BUILD_MARK} End of DEBUG audit section"
    log_info_line
fi

export HOST_LDFLAGS="${HOST_LINUX_LDFLAGS[*]}"
export HOST_CFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma -ftree-vectorize -fno-plt -pipe -g0 -ffunction-sections -fdata-sections -std=gnu23"

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

# Tip: -Wl,--allow-multiple-definition needed for KVAZAAR with cryptopp.
CONF_FLAGS=(
    --prefix="$FFBUILD_DESTPREFIX"
    "${TARGET_FLAGS_ARR[@]}"
    --host-cc="ccache gcc-14"
    --host-cflags="$HOST_CFLAGS"
    --host-ldflags="$HOST_LDFLAGS"
    --extra-cflags="${FINAL_CFLAGS}${ASAN_CFLAGS}"
    --extra-cxxflags="${FINAL_CXXFLAGS}${ASAN_CXXFLAGS}"
    --extra-ldflags="${ASAN_LDFLAGS}${FINAL_LDFLAGS} -Wl,--allow-multiple-definition"
    --extra-ldexeflags="$FINAL_LDEXEFLAGS"
    --extra-libs="${FINAL_LIBS_GROUPED}"
    "${FF_CONF_ARR[@]}"
    --enable-runtime-cpudetect
    --disable-w32threads --enable-pthreads
    --enable-opengl
    --enable-pic
    --disable-debug
    # --cc="$CC" --cxx="$CXX" --ar="$AR" --ranlib="$RANLIB" --nm="$NM" --as="$CC"
    --cc="${FFBUILD_CROSS_PREFIX}gcc" 
    --cxx="${FFBUILD_CROSS_PREFIX}g++" 
    --ar="${FFBUILD_CROSS_PREFIX}ar" 
    --ranlib="${FFBUILD_CROSS_PREFIX}ranlib" 
    --nm="${FFBUILD_CROSS_PREFIX}nm" 
    --as="${FFBUILD_CROSS_PREFIX}gcc"
)

if [[ "${PREFER_SHARED}" != "1" ]]; then
    CONF_FLAGS+=(
        --pkg-config-flags="--static --libs-only-l"
    )
else
    CONF_FLAGS+=(
        --pkg-config-flags=""
    )
fi

[[ "$HAS_AUDIOTOOLBOX" == "0" ]] && CONF_FLAGS+=( --disable-audiotoolbox --disable-videotoolbox )
[[ "$HAS_OPENSSL" == "0" ]] && CONF_FLAGS+=( --disable-securetransport )
[[ "$HAS_AMF" == "1" ]] && CONF_FLAGS+=( --enable-filter=vpp_amf --enable-filter=sr_amf )
[[ "${USE_AVX512}" != "1" ]] && CONF_FLAGS+=( --disable-avx512 --disable-avx512icl )
# flags added by ffmpeg patches, not from mainline FFmpeg
[[ "$FFMPEG_PATCHES" == "1" ]] && CONF_FLAGS+=( --h264-max-bit-depth=14 --h265-bit-depths=8,9,10,12 )
if command -v clang &>/dev/null && command -v llvm-config &>/dev/null; then
    CONF_FLAGS+=( --nvcc=clang )
fi

# Считаем физическую память и Swap (в ГБ)
MEM_PHYS=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
SWAP_TOTAL=$(awk '/SwapTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
TOTAL_VIRTUAL=$(( MEM_PHYS + SWAP_TOTAL ))
# Лимиты для LTO:
# На этапе линковки каждый поток LTO требует много RAM.
# Для 7GB RAM + 32GB Swap оптимально не превышать 4 потока, 
# иначе диск не будет успевать за подкачкой.
if [[ "$FINAL_CONFIGURE" =~ --enable-lto ]] || [[ "$USE_LTO" == "1" ]]; then
    # Если виртуальной памяти много, можно позволить 4 потока.
    # Если мало (менее 16ГБ общего), лучше оставить 2.
    if [[ $TOTAL_VIRTUAL -gt 16 ]]; then
        MAKE_JOBS=4
        log_warn "LTO & High Swap: Using 4 threads for stability."
    else
        MAKE_JOBS=2
        log_warn "LTO & Low Memory: Forcing dual-thread build to avoid OOM."
    fi
else
    # Обычная сборка (не LTO) ориентируемся на MemAvailable
    MEM_AVAIL=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo)
    # 1 поток на 1.5 ГБ доступной памяти для обычной компиляции
    MEM_JOBS=$(( MEM_AVAIL * 10 / 15 ))
    [[ $MEM_JOBS -lt 1 ]] && MEM_JOBS=1

    CPU_CORES=$(nproc)
    MAKE_JOBS=$(( CPU_CORES < MEM_JOBS ? CPU_CORES : MEM_JOBS ))
    log_info "Non-LTO build: Setting MAKE_JOBS=${MAKE_JOBS} based on availability."
fi

log_info_line
log_info "### ${CACHE_MARK} HOST INFO: MEM: ${MEM_PHYS}GB + SWAP: ${SWAP_TOTAL}GB = Total: ${TOTAL_VIRTUAL}GB; JOBS=${MAKE_JOBS}"

log_info_line
log_info "### ${START_MARK} Launching FFmpeg Configure..."
log_info_line

# Функция проверки и валидации флагов ffmpeg SAFE_CONFIGURE
check_and_fix_configure && printf "  %s\n" "${CONF_FLAGS[@]}"

# Перенаправляем stderr в config.log для полноты картины
if ! ./configure "${CONF_FLAGS[@]}" 2>"$FFMPEG_CONFIG_LOG"; then
    log_error "Configure failed!"
    log_debug "${LOGS_MARK} ▼ CONTENT OF $FFMPEG_CONFIG_LOG ▼"
    tail -n 1000 "$FFMPEG_CONFIG_LOG"
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

mkdir -p "$PKG_DIR"/{include,lib,bin/assets,doc}

export ASSETS_DIR="$PKG_DIR/bin/assets"

if ! declare -F package_variant >/dev/null; then
    log_error "package_variant not defined - variant script missing or broken"
    exit 1
fi
package_variant "$FFBUILD_DESTPREFIX" "$PKG_DIR"

# Проверяем наличие критических библиотек (для отладки в логах)
ls -lh "$PKG_DIR/bin/"

# Скачиваем модели и ассеты
log_info "${SYNC_MARK} Collecting additional assets..."

# "$UTIL_DIR"/download_assets.sh "$ASSETS_DIR" "$(pwd)" || log_warn "Assets download failed, but continuing..."
"$UTIL_DIR"/collect_assets.sh "$ASSETS_DIR" "$FFMPEG_SOURCE_DIR" || log_warn "Assets download failed, but continuing..."

# Стриппинг бинарников (удаление отладочных символов)
# --strip-all; --strip-unneeded
log_info "${BROOM_MARK} Stripping binaries..."
find "$PKG_DIR/bin" -name "*.exe" -o -name "*.dll" -exec ${FFBUILD_CROSS_PREFIX}strip --strip-unneeded {} \;

# Упаковка
log_info "${ARCH_MARK} Creating archive: ${BUILD_NAME}.7z"
# Заходим в pkgroot, чтобы внутри архива не было лишних вложенных папок
pushd "$FFMPEG_PKG_ROOT"
7z a -mx7 -mmt=on "$FFBUILD_DESTDIR/${BUILD_NAME}.7z" "./${BUILD_NAME}/*"
popd

# Генерация метаданных для GitHub Actions
if [[ -n "$GITHUB_ACTIONS" ]]; then
    echo "build_name=${BUILD_NAME}" >> "$GITHUB_OUTPUT"
    echo "${BUILD_NAME}.7z" > "$FFBUILD_DESTDIR/${TARGET}-${VARIANT}.txt"
fi

duration=$SECONDS
elapsed=$(printf '%02dh:%02dm:%02ds' $((duration/3600)) $((duration%3600/60)) $((duration%60)))

log_info "${CHECK_MARK} Build finished after ${GREY_B}${elapsed}${NC}"

exit 0