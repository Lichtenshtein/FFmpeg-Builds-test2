#!/bin/bash

set -e
# set -xe
shopt -s globstar
cd "$(dirname "$0")"

source util/vars.sh "${1:-$TARGET}" "${2:-$VARIANT}" \
    || { echo "ERROR: vars.sh failed in build.sh" >&2; exit 1; }

# Сброс статистики для чистого лога
ccache -z > /dev/null
# размер кэша компилятора
ccache -M 2G > /dev/null
# Сбрасываем счетчик секунд в начале этапа
SECONDS=0

# Определяем функцию очистки
cleanup() {
    local exit_code=$? # Запоминаем код завершения (0 - успех, >0 - ошибка)

    log_info "Running cleanup (Exit code: $exit_code)..."

    # Удаляем временную папку сборки (pkgroot, временные логи и т.д.)
    rm -rf "$FFMPEG_PKG_ROOT" "$VARS_DIR" 2>/dev/null

    # Если сборка упала, можно оставить лог конфига в доступном месте
    if [[ $exit_code -ne 0 && -f "$FFMPEG_CONFIG_LOG" ]]; then
        cp "$FFMPEG_CONFIG_LOG" "${FFBUILD_DESTDIR}/failed_config.log" 2>/dev/null || true
    else
    # Просто копируем лог в папку для упаковки
        cp "$FFMPEG_CONFIG_LOG" "${FFBUILD_DESTDIR}/config.log" 2>/dev/null || true
    fi

    log_info "Cleanup done."

    # Вывод статистики ccache
    log_info "${CACHE_MARK} CCACHE STATISTICS:"
    ccache -s 2>&1 || echo "ccache command failed entirely with exit code $?"
}
# Устанавливаем ловушку
# EXIT сработает всегда: и при успехе, и при ошибке, и при прерывании
trap cleanup EXIT

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

# =======================================
# FFMPEG SOURCE PATCHING SECTION 1
# =======================================
log_info "Patching FFmpeg vf_libvmaf.c to use Pointer ABI..."
# Подменяем вызов в исходнике фильтра на передачу адреса структуры
sed -i 's/err = vmaf_init(\&s->vmaf, cfg);/err = vmaf_init(\&s->vmaf, \&cfg);/g' "libavfilter/vf_libvmaf.c"
if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
    # На всякий случай жестко проверяем, применился ли патч (выводим строку в лог)
    grep -n "vmaf_init" "libavfilter/vf_libvmaf.c"
fi
log_info "Patching FFmpeg ffprobe ABI bug: Changing avtext_context_open to pass options by pointer..."
# Точечно меняем сигнатуру в заголовочном файле (обратите внимание на имя переменной 'options')
sed -i 's/AVTextFormatOptions options,/const AVTextFormatOptions \*options,/g' "fftools/textformat/avtextformat.h"
# Точечно меняем объявление функции в файле реализации
sed -i 's/AVTextFormatOptions options,/const AVTextFormatOptions \*options,/g' "fftools/textformat/avtextformat.c"
# Меняем только одну строчку присвоения внутри тела avtext_context_open, 
# чтобы данные разыменовывались из указателя обратно в объект контекста:
sed -i 's/tctx->opts = options;/tctx->opts = *options;/g' "fftools/textformat/avtextformat.c"
# Добавляем амперсанд на стороне вызова в fftools/ffprobe.c
sed -i 's/tf_options, show_data_hash/\&tf_options, show_data_hash/g' "fftools/ffprobe.c"
# Патчим вызывающую сторону в fftools/graph/graphprint.c (добавляем амперсанд &)
sed -i 's/tf_options, NULL/\&tf_options, NULL/g' "fftools/graph/graphprint.c"
# Проверка успешности наката патча в логи сборщика
if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
    log_debug "Verifying patches application..."
    grep -n "avtext_context_open" "fftools/textformat/avtextformat.h"
    grep -n "avtext_context_open" "fftools/textformat/avtextformat.c" | head -n 2
    grep -n "avtext_context_open" "fftools/ffprobe.c"
    grep -n "avtext_context_open" "fftools/graph/graphprint.c"
fi

if [[ -f "${FFBUILD_PREFIX}/lib/pkgconfig/xeve.pc" ]]; then
    sed -i "s/Version:.*/Version: /" "${FFBUILD_PREFIX}/lib/pkgconfig/xeve.pc"
    sed -i "s|^Version:.*|Version: 0.5.1|" "${FFBUILD_PREFIX}/lib/pkgconfig/xeve.pc"
fi

# if [[ -f "${FFBUILD_PREFIX}/lib/pkgconfig/libdatachannel.pc" ]]; then
    # log_info "Adding -DRTC_STATIC to libdatachannel.pc..."
    # sed -i '/^Cflags:/ s/$/ -DRTC_STATIC/' "${FFBUILD_PREFIX}/lib/pkgconfig/libdatachannel.pc"
# fi

# =======================================
# FLAGS SECTION
# =======================================
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
COMPONENTS=(libtorch libopenvino libflite audiotoolbox libtensorflow libtesseract openssl amf frei0r whisper liblcevc_dec)
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
# if [[ "$HAS_LIBTORCH" == "1" ]]; then
    # ls -lh ${FFBUILD_PREFIX}/lib/libtorch_cpu.a || true
    # TORCH_LIBS="-ltorch -ltorch_cpu -lc10"
    # log_info "${TARGET_MARK} Setting up hybrid linking for LibTorch..."
    # TORCH_LIBS="-lXNNPACK -lasmjit -lc10 -lc10d -lcaffe2_detectron_ops -lcaffe2_module_test_dynamic -lclog -lcpuinfo -ldnnl -lfbgemm -lfbjni -lkineto -lmkldnn -lprotobuf-lite -lprotoc -lpthreadpool -lpytorch_jni -ltorch -ltorch_cpu "
    # for lib in ${TORCH_LIBS}; do
        # FINAL_LIBS=$(echo " ${FINAL_LIBS} " | sed "s/ ${lib} / /g")
    # done
    # DYNAMIC_LIBS_ACCUMULATOR+="${TORCH_LIBS} "
    # sed -i '/at::detail::getXPUHooks/d' libavfilter/dnn/dnn_backend_torch.cpp
    # sed -i 's/device.is_xpu()/false/g' libavfilter/dnn/dnn_backend_torch.cpp
    # sed -i 's/at::hasXPU()/false/g' libavfilter/dnn/dnn_backend_torch.cpp
# fi

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
# DYNAMIC_LIBS_ACCUMULATOR+=""
# HYBRID_DYNAMIC_FLAGS=""
# if [[ -n "${DYNAMIC_LIBS_ACCUMULATOR}" ]]; then
    # HYBRID_DYNAMIC_FLAGS="-Wl,-Bdynamic ${DYNAMIC_LIBS_ACCUMULATOR} -Wl,-Bstatic "
# fi

# Используем группы для решения проблем циклических зависимостей
# прокидываем библиотеку обработки исключений LTO за пределы основной группы
FINAL_LIBS_GROUPED="-Wl,--start-group ${HYBRID_DYNAMIC_FLAGS}${FINAL_LIBS} -lntdll -Wl,--end-group -lstdc++"

# =======================================
# FFMPEG SOURCE PATCHING SECTION 1
# =======================================
if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
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

    log_debug "FFBUILD_PREFIX:\n${FFBUILD_PREFIX}"
    log_debug "FFBUILD_DESTDIR:\n${FFBUILD_DESTDIR}"
    log_debug "PKG_DIR:\n${PKG_DIR}"
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
    gcc --version | head -n 1
    x86_64-w64-mingw32-as --version | head -n 1
    ccache --version | head -n 1

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
    if "${PKG_CONFIG}" --exists ffnvcodec; then
        log_info "${CHECK_MARK} ffnvcodec found: $("${PKG_CONFIG}" --modversion ffnvcodec)"
        log_debug "Cflags: $("${PKG_CONFIG}" --cflags ffnvcodec)"
    else
        log_error "ffnvcodec NOT FOUND in PKG_CONFIG_PATH ($PKG_CONFIG_PATH)"
        log_debug "Contents of ${FFBUILD_PREFIX}/lib/pkgconfig:"
        ls -1 "${FFBUILD_PREFIX}"/lib/pkgconfig/*.pc 2>/dev/null | xargs -r -n1 basename | sed 's/^/ /'
    fi

    log_info "${SEARCH_MARK} Auditing pkg-config files for overflow triggers..."
    for pc in "${FFBUILD_PREFIX}"/lib/pkgconfig/*.pc; do
        log_debug "Testing pc file: $(basename "$pc")"
        # Проверяем, не падает ли pkgconf на чтении флагов этой либы
        pkgconf --static --libs "$(basename "$pc" .pc)" >/dev/null 2>&1 && log_info "  $(basename "$pc"): OK" || log_error "  $(basename "$pc"): CRASHED OR FAILED"
    done

    # Специфическая проверка для LTO (наличие плагинов)
    log_info "${BUILD_MARK} Checking LTO support in AR:"
    if $AR --help | grep -q "plugin"; then
        log_info "${CHECK_MARK} AR supports plugins (required for LTO)"
    else
        log_warn "AR may not support LTO plugins! Make sure you're using gcc-ar."
    fi

    log_debug "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
    which "${PKG_CONFIG}"

    log_info_line
    log_info "### ${BUILD_MARK} End of DEBUG audit section"
    log_info_line
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

chmod +x configure

# Tip: -Wl,--allow-multiple-definition needed for KVAZAAR/cryptopp & OpenSSL/quiche.
# --extra-cflags="-DCOBJMACROS"
# --extra-ldflags="${FINAL_LDFLAGS} -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma"
# -march=x86-64-v3 -mtune=generic
CONF_FLAGS=(
    --prefix="$INSTALL_ROOT"
    "${TARGET_FLAGS_ARR[@]}"
    --host-cc="ccache gcc-15"
    --host-cflags="$HOST_CFLAGS"
    --host-ldflags="$HOST_LDFLAGS"
    --extra-cflags="${FINAL_CFLAGS}"
    --extra-cxxflags="${FINAL_CXXFLAGS}"
    --extra-ldflags="${FINAL_LDFLAGS} -Wl,--allow-multiple-definition"
    --extra-ldexeflags="${FINAL_LDEXEFLAGS}"
    --extra-libs="${FINAL_LIBS_GROUPED}"
    "${FF_CONF_ARR[@]}"
    --enable-runtime-cpudetect
    --disable-w32threads --enable-pthreads
    --enable-opengl
    --enable-dxva2
    --enable-mediafoundation
    --enable-pic
    # --disable-ffprobe
    --disable-ffplay
    --cc="$CC" --cxx="$CXX" --ar="$AR" --ranlib="$RANLIB" --nm="$NM" --as="$CC"
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

[[ "$HAS_AUDIOTOOLBOX" == "0" ]] && \
    CONF_FLAGS+=( --disable-audiotoolbox --disable-videotoolbox )
[[ "$HAS_OPENSSL" == "0" ]] && \
    CONF_FLAGS+=( --disable-securetransport )
[[ "$HAS_AMF" == "1" ]] && \
    CONF_FLAGS+=( --enable-filter=vpp_amf --enable-filter=sr_amf )
[[ "${USE_AVX512}" != "1" ]] && \
    CONF_FLAGS+=( --disable-avx512 --disable-avx512icl )
[[ "$DEBUG_MODE" == "1" ]] && \
    CONF_FLAGS+=( --disable-stripping --enable-debug=3 --disable-optimizations ) || \
    CONF_FLAGS+=( --disable-debug )
if command -v clang &>/dev/null && command -v llvm-config &>/dev/null; then
    CONF_FLAGS+=( --nvcc=clang )
fi
# flags added by ffmpeg patches, not from mainline FFmpeg
[[ "$FFMPEG_PATCHES" == "1" ]] && \
    CONF_FLAGS+=( --h264-max-bit-depth=14 --h265-bit-depths=8,9,10,12 )

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
    tail -n ${LOG_FF_SIZES} "$FFMPEG_CONFIG_LOG"
    log_debug "${LOGS_MARK} ▲ END OF $FFMPEG_CONFIG_LOG ▲"
    exit 1
fi

# =======================================
# FFMPEG SOURCE PATCHING SECTION 2
# =======================================
if [[ "$HAS_LIBLCEVC_DEC" == "1" ]]; then
    log_info "Applying precise LCEVC SDK 4.0.0 migration patches..."

    if [[ -f "libavfilter/vf_lcevc.c" ]]; then
        # Удаляем флаг discontinuity (0) из LCEVC_SendDecoderEnhancementData
        sed -i 's|LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, 0, sd->data, sd->size)|LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, sd->data, sd->size)|g' libavfilter/vf_lcevc.c

        # Удаляем флаг discontinuity (0) из LCEVC_SendDecoderBase, сдвигая picture и оставляя -1 на месте timeoutUs
        sed -i 's|LCEVC_SendDecoderBase(lcevc->decoder, in->pts, 0, picture, -1, in)|LCEVC_SendDecoderBase(lcevc->decoder, in->pts, picture, -1, in)|g' libavfilter/vf_lcevc.c

        log_info "Successfully patched libavfilter/vf_lcevc.c"
    else
        log_warn "File libavfilter/vf_lcevc.c not found, skipping."
    fi

    if [[ -f "libavcodec/lcevcdec.c" ]]; then
        # Удаляем флаг discontinuity (0) из LCEVC_SendDecoderEnhancementData
        sed -i 's|LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, 0, sd->data, sd->size)|LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, sd->data, sd->size)|g' libavcodec/lcevcdec.c

        # Удаляем флаг discontinuity (0) из LCEVC_SendDecoderBase, сдвигая picture и оставляя -1 на месте timeoutUs
        sed -i 's|LCEVC_SendDecoderBase(lcevc->decoder, in->pts, 0, picture, -1, opaque)|LCEVC_SendDecoderBase(lcevc->decoder, in->pts, picture, -1, opaque)|g' libavcodec/lcevcdec.c

        log_info "Successfully patched libavcodec/lcevcdec.c"
    else
        log_error "libavcodec/lcevcdec.c not found!"
    fi
fi

if [[ "$TARGET" == "win64" ]]; then
    log_info "Adjusting the generated config.h: forcibly disabling HAVE_FCNTL for Windows..."

    log_info "Searching for and patching all generated config.h files..."

    # Находим все файлы config.h в текущем дереве сборки
    CONFIG_FILES=$(find . -type f -name "config.h")
    
    if [[ -n "$CONFIG_FILES" ]]; then
        for cfg in $CONFIG_FILES; do
            log_debug "Patching file: $cfg"
            # Заменяем "#define HAVE_FCNTL 1" на "#define HAVE_FCNTL 0"
            sed -i 's/#define HAVE_FCNTL 1/#define HAVE_FCNTL 0/g' "$cfg"
            # На всякий случай, если он записан как "#undef HAVE_FCNTL", 
            # но мы хотим жестко гарантировать ноль:
            if ! grep -q "HAVE_FCNTL" "$cfg"; then
                echo "#define HAVE_FCNTL 0" >> "$cfg"
            fi
        done
        log_info "All config.h files have been successfully adjusted!"
    else
        log_error "No config.h files found! Please check if ./configure was successful."

        log_info "Applying 3 patches to remove fcntl from FFmpeg files..."

        # Патчим libavformat/file.c
        if [[ -f "libavformat/file.c" ]]; then
            sed -i 's/#if HAVE_FCNTL/#if HAVE_FCNTL \&\& !defined(_WIN32)/g' libavformat/file.c
            log_info "Patch 1/3 (file.c) applied successfully."
        else
            log_warn "The file libavformat/file.c could not be found in this path."
        fi

        # Патчим libavformat/network.c
        if [[ -f "libavformat/network.c" ]]; then
            sed -i 's/#if HAVE_FCNTL/#if HAVE_FCNTL \&\& !defined(_WIN32)/g' libavformat/network.c
            log_info "Patch 2/3 (network.c) applied successfully."
        else
            log_warn "The file libavformat/network.c could not be found in this path."
        fi

        # Патчим libavutil/file_open.c
        if [[ -f "libavutil/file_open.c" ]]; then
            sed -i 's/#if HAVE_FCNTL/#if HAVE_FCNTL \&\& !defined(_WIN32)/g' libavutil/file_open.c
            log_info "Patch 3/3 (file_open.c) applied successfully."
        else
            log_warn "The file libavutil/file_open.c could not be found in this path."
        fi

    fi
fi

# Очистка хедера ffmpeg
if [ -f "config.h" ]; then

    if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
        log_info "${LOGS_MARK} >>> [BEFORE] config.h target line:"
        grep "#define FFMPEG_CONFIGURATION" config.h || echo "Line not found"
    fi

    # Извлекаем только контент внутри кавычек макроса
    RAW_CONFIG=$(sed -n 's/^#define FFMPEG_CONFIGURATION "\(.*\)"/\1/p' config.h)

    if [ -n "$RAW_CONFIG" ]; then
        # парсим строку в настоящий массив. 
        # Оболочка сама разберется с вложенными кавычками типа '--extra-cflags=...'
        eval "FINAL_ARGS=($RAW_CONFIG)"

        CLEANED_ARGS=()

        # Фильтруем аргументы, исключая все тяжелые флаги и пути к компиляторам
        for arg in "${FINAL_ARGS[@]}"; do
            case "$arg" in
                --host-cflags=*|--host-ldflags=*|--extra-cflags=*|--extra-cxxflags=*|--extra-ldflags=*|--extra-ldexeflags=*|--extra-libs=*)
                    # Пропускаем флаги компиляции и линковки
                    continue
                    ;;
                --pkg-config-flags=*|--cc=*|--cxx=*|--ar=*|--ranlib=*|--nm=*|--as=*)
                    # Пропускаем пути к тулчейну
                    continue
                    ;;
                *)
                    # Сохраняем только эстетичные и полезные опции (--enable-...)
                    # Если аргумент содержит пробелы, мы вернем ему одинарные кавычки для красоты
                    if [[ "$arg" == *" "* ]]; then
                        CLEANED_ARGS+=("'$arg'")
                    else
                        CLEANED_ARGS+=("$arg")
                    fi
                    ;;
            esac
        done

        # Собираем элементы обратно в красивую строку через один пробел
        CLEANED_CONFIG="${CLEANED_ARGS[*]}"

        # Жестко перезаписываем строку в файле, гарантируя идеальный пробел перед кавычкой (ISO C99)
        sed -i "s|^#define FFMPEG_CONFIGURATION.*|#define FFMPEG_CONFIGURATION \"${CLEANED_CONFIG}\"|" config.h
    else
        log_warn "Failed to parse FFMPEG_CONFIGURATION content for cleaning."
    fi

    if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
        log_info "${LOGS_MARK} <<< [AFTER] config.h target line:"
        grep "#define FFMPEG_CONFIGURATION" config.h
    fi
fi

# =======================================
# FFMPEG MAKE & INSTALL
# =======================================
# Сборка и установка ffmpeg
make -j"$MAKE_JOBS" ${MAKE_V:+$MAKE_V}
make install
make install-doc || log_warn "install-doc failed, but proceeding."

log_info "${DIRS_MARK} Leaving FFmpeg folder..."
popd # Выход из ffbuild/ffmpeg

log_info "${BROOM_MARK} Cleaning up potential prefix pollution..."
# Удаляем пустые папки или старые логи, если они остались
find "${FFBUILD_PREFIX}" -type d -empty -delete || true

# Определение версии
# Проверяем наличие официального скрипта определения версии
if [[ -f "$FFMPEG_SOURCE_DIR/ffbuild/version.sh" ]]; then
    log_info "Detecting FFmpeg version using official ffbuild/version.sh..."
    # Запускаем скрипт, передав ему путь к корню исходников FFmpeg
    FFMPEG_VERSION=$(bash "$FFMPEG_SOURCE_DIR/ffbuild/version.sh" "$FFMPEG_SOURCE_DIR")
else
    log_warn "ffbuild/version.sh not found, falling back to basic date-string."
    FFMPEG_VERSION=$(date +%Y-%m-%d)
fi
# Убираем возможные пробелы или спецсимволы переноса строки из переменной
FFMPEG_VERSION=$(echo "$FFMPEG_VERSION" | xargs)

BUILD_NAME="ffmpeg-${FFMPEG_VERSION}-${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}"

export PKG_DIR="$FFMPEG_PKG_ROOT/${BUILD_NAME}"
mkdir -p "${PKG_DIR}"/{bin,doc,share}
export ASSETS_DIR="${PKG_DIR}/share"

if ! declare -F package_variant >/dev/null; then
    log_error "package_variant not defined - variant script missing or broken"
    exit 1
fi
package_variant "$INSTALL_ROOT" "${PKG_DIR}"

# =======================================
# FFMPEG ASSETS & PLUGINS COLLECTION
# =======================================
# Скачиваем модели и ассеты
log_info "${SYNC_MARK} Collecting additional assets..."
"$UTIL_DIR"/collect_assets.sh "${ASSETS_DIR}" "$FFMPEG_SOURCE_DIR" || log_warn "Assets download failed, but continuing..."

# =======================================
# FFMPEG DEBUGGING SECTION
# =======================================
if [[ "$DEBUG_MODE" == "1" ]]; then

    # 1. AVX-512 Leakage Scan
    # If zmm registers (these are AVX-512 registers) or evex prefixes appear in the assembler output, it means that some library is still pushing this code.
    if [[ "$USE_AVX512" != "1" ]]; then
        log_info "${SEARCH_MARK} Scanning final binaries for accidental AVX-512 leak..."
        while IFS= read -r file; do
            log_debug "Analyzing $(basename "$file")..."
            set +o pipefail 2>/dev/null || true
            LEAKED_INSTR=$("${FFBUILD_CROSS_PREFIX}objdump" -d -j .text "$file" 2>/dev/null | \
                grep -Ei '\bzmm[0-9]|\b[xy]mm(1[6-9]|2[0-9]|3[0-1])\b|\bk[0-7]\b|evex' | head -n 20)
            set -o pipefail 2>/dev/null || true

            if [[ -n "$LEAKED_INSTR" ]]; then
                log_warn "AVX-512 instructions detected in $(basename "$file")!"
                if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
                    echo -e "${LOG_WARN}--- First 20 leaked lines: ---${NC}"
                    echo "$LEAKED_INSTR"
                    echo -e "${LOG_WARN}------------------------------${NC}"
                fi
            else
                log_info "${CHECK_MARK} $(basename "$file") is clean of AVX-512 code."
            fi
        done < <(find "${PKG_DIR}/bin" -type f \( -name "*.exe" -o -name "*.dll" \))
    fi

    # 2. Component Mapping & Dynamic Symbol Verification
    # Map ffmpeg enable flags to their corresponding codec names and symbol prefixes
    # Format: 'enable_flag:codec_name:media
    declare -A COMPONENT_TEST_MAP=(
        ["enable-libx264"]="libx264:v:ff_libx264"
        ["enable-libx265"]="libx265:v:ff_libx265"
        ["enable-libsvtav1"]="libsvtav1:v:ff_libsvtav1"
        ["enable-libaom"]="libaom:v:ff_libaom_av1"
        ["enable-libvpx"]="libvpx:v:ff_libvpx_vp9"
        ["enable-libsvtvp9"]="libsvtvp9:v:ff_libsvt_vp9"
        ["enable-libopenh264"]="libopenh264:v:ff_libopenh264"
        ["enable-libvvdec"]="libvvdec:v:ff_libvvdec"
        ["enable-libvvenc"]="libvvenc:v:ff_libvvenc"
        ["enable-libxevd"]="libxevd:v:ff_libxevd"
        ["enable-liblcevc_dec"]="liblcevc_dec:v:ff_lcevc"
        ["enable-libmp3lame"]="libmp3lame:a:ff_libmp3lame"
        ["enable-libopus"]="libopus:a:ff_libopus_encoder"
        ["enable-libvorbis"]="libvorbis:a:ff_libvorbis"
        ["enable-libfdk-aac"]="libfdk_aac:a:ff_libfdk_aac_encoder"
        ["enable-libsvtjpegxs"]="libsvtjpegxs:v:ff_libsvtjpegxs"
        ["enable-libopenjpeg"]="libopenjpeg:v:ff_libopenjpeg"
        ["enable-libwebp"]="libwebp:v:ff_libwebp_encoder"
        ["enable-libgme"]="libgme:a:ff_libgme"
        ["enable-libmodplug"]="libmodplug:a:ff_libmodplug"
        ["enable-libopenmpt"]="libopenmpt:a:ff_libopenmpt"
        ["enable-libass"]="libass:v:ff_ass"
        ["enable-libvmaf"]="libvmaf:v:ff_vf_libvmaf"
        ["enable-libpulse"]="libpulse:a:ff_pulse_audio"
        ["enable-libsoxr"]="libsoxr:a:ff_sox"
        ["enable-librubberband"]="librubberband:a:ff_af_rubberband"
        ["enable-libopenvino"]="libopenvino:v:ff_dnn_backend_openvino"
        ["enable-libtensorflow"]="libtensorflow:v:ff_dnn_backend_tf"
        ["enable-libtorch"]="libtorch:v:ff_dnn_backend_torch"
        ["enable-libglslang"]="libglslang:v:ff_vk_glslang"
        ["enable-libshaderc"]="libshaderc:v:ff_vk_shaderc"
        ["enable-libvpl"]="libvpl:v:ff_vpl"
        ["enable-libcodec2"]="libcodec2:v:ff_libcodec2_encoder"
        ["enable-libmad"]="libmad:a:ff_libmad"
        ["enable-libmpeghdec"]="libmpeghdec:v:ff_libmpeghdec"
        ["enable-libshine"]="libshine:v:ff_libshine"
        ["enable-ia_mpegh"]="ia_mpegh:v:ff_ia_mpegh"
        ["enable-libopencore-amrnb"]="libopencore_amrnb:a:ff_libopencore_amrnb_encoder"
        ["enable-libtwolame"]="libtwolame:a:ff_libtwolame"
        ["enable-libvo-amrwbenc"]="libvo_amrwbenc:a:ff_libvo_amrwbenc"
        ["enable-libtheora"]="libtheora:v:ff_libtheora"
        ["enable-libsvthevc"]="libsvthevc:v:ff_libsvt_hevc"
        ["enable-libxvid"]="libxvid:v:ff_libxvid"
    )

    # Function to verify symbols for ALL enabled components dynamically
    verify_all_symbols() {
        local config_source="${FINAL_CONFIGURE:-$(cat ${FFMPEG_CONFIG_LOG:-/dev/null} 2>/dev/null)}"
        local MISSING_SYMBOLS=0
        local VERIFIED_COUNT=0
        local STRINGS_CMD="${FFBUILD_CROSS_PREFIX}strings"
        command -v "$STRINGS_CMD" &>/dev/null || STRINGS_CMD="strings"
        local TEST_EXE="${PKG_DIR}/bin/ffmpeg.exe"
        [[ ! -f "$TEST_EXE" ]] && TEST_EXE="/opt/ffdest/opt/ffbuild/bin/ffmpeg.exe"

        log_debug "${SEARCH_MARK} Verifying static symbols for ALL enabled components..."

        for flag in "${!COMPONENT_TEST_MAP[@]}"; do
            # Check if this feature is enabled
            if [[ "$config_source" == *"$flag"* ]]; then
                local codec_spec="${COMPONENT_TEST_MAP[$flag]}"
                local codec_name="${codec_spec%%:*}"
                local media_type="${codec_spec#*:}"
                local symbol_prefix="${codec_spec##*:}"

                # Check for symbol presence
                local has_strings=0
                local has_nm=0

                if "$STRINGS_CMD" "$TEST_EXE" 2>/dev/null | grep -q "$symbol_prefix"; then
                    has_strings=1
                fi

                # Use nm if available, fall back to strings only
                if command -v nm &>/dev/null; then
                    if nm "$TEST_EXE" 2>/dev/null | grep -q "$symbol_prefix"; then
                        has_nm=1
                    fi
                fi

                if [[ $has_strings -eq 0 && $has_nm -eq 0 ]]; then
                    log_error "Symbol '$symbol_prefix' NOT found in binary for $codec_name! Linking failure detected."
                    MISSING_SYMBOLS=1
                else
                    log_debug "   ${CHECK_MARK} Verified: $codec_name ($media_type) - Symbol: $symbol_prefix"
                    VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
                fi
            fi
        done

        if [[ $MISSING_SYMBOLS -eq 1 ]]; then
            log_error "Static linking verification FAILED: $VERIFIED_COUNT verified, but some symbols missing."
            # return 1
        else
            log_info "${CHECK_MARK} Static symbols verified for $VERIFIED_COUNT components."
            return 0
        fi
    }

    # 3. Generate Dynamic Component Tests
    generate_component_tests() {
        local enabled_components=()
        local tests=()
        local config_source="${FINAL_CONFIGURE:-$(cat ${FFMPEG_CONFIG_LOG:-/dev/null} 2>/dev/null)}"

        log_debug "${SEARCH_MARK} Generating specific tests for enabled components..."

        for flag in "${!COMPONENT_TEST_MAP[@]}"; do
            if [[ "$config_source" == *"$flag"* ]]; then
                local codec_spec="${COMPONENT_TEST_MAP[$flag]}"
                local codec_name="${codec_spec%%:*}"
                local media_type="${codec_spec#*:}"
                
                enabled_components+=("$codec_name ($media_type)")

                # Build specific test based on media type
                if [[ "$media_type" == "v" ]]; then
                    # Video tests: Add 10-bit test for x265 and x264 if enabled
                    if [[ "$codec_name" == "libx265" || "$codec_name" == "libx264" ]]; then
                        # Test 10-bit encoding
                        tests+=("-loglevel warning -f lavfi -i testsrc2=s=1920x1080:r=30:d=2 -c:v $codec_name -pix_fmt yuv420p10le -b:v 500k -f null -")
                        # Test standard 8-bit
                        tests+=("-loglevel warning -f lavfi -i testsrc2=s=1280x720:r=30:d=1 -c:v $codec_name -pix_fmt yuv420p -b:v 500k -f null -")
                    elif [[ "$codec_name" == "libaom" || "$codec_name" == "libsvtav1" ]]; then
                        # AV1 specific tests (often memory heavy)
                        tests+=("-loglevel warning -f lavfi -i testsrc2=s=1280x720:r=30:d=2 -c:v $codec_name -crf 30 -f null -")
                    else
                        # Standard video test
                        tests+=("-loglevel warning -f lavfi -i testsrc2=s=1280x720:r=30:d=2 -c:v $codec_name -b:v 500k -f null -")
                    fi
                else
                    # Audio tests
                    if [[ "$codec_name" == "libopus" || "$codec_name" == "libvorbis" ]]; then
                        # Test resampling (common audio bug)
                        tests+=("-loglevel warning -f lavfi -i sine=f=1000:d=2 -ar 48000 -c:a $codec_name -b:a 128k -f null -")
                    else
                        tests+=("-loglevel warning -f lavfi -i sine=f=1000:d=2 -c:a $codec_name -b:a 128k -f null -")
                    fi
                fi
            fi
        done

        # Add a complex filter chain test if video codecs are present
        if [[ ${#enabled_components[@]} -gt 0 ]] && [[ "$config_source" == *"--enable-libx264"* || "$config_source" == *"--enable-libx265"* ]]; then
            tests+=("-loglevel warning -f lavfi -i color=c=red:s=1280x720:d=2 -vf scale=640x360,format=yuv444p10le -c:v libx264 -pix_fmt yuv444p10le -b:v 1M -f null -")
        fi

        if [[ ${#enabled_components[@]} -eq 0 ]]; then
            log_warn "No heavy external components detected for specific testing."
            # Add a minimal fallback
            tests+=("-loglevel warning -f lavfi -i testsrc2=d=1 -c:v wrapped_avframe -f null -")
        else
            log_info "Discovered ${#enabled_components[@]} components for deep audit:"
            for comp in "${enabled_components[@]}"; do
                log_debug "   - $comp"
            done
        fi

        COMPREHENSIVE_TESTS=("${tests[@]}")
    }

    # 4. Main Audit Runner
    run_deep_component_audit() {
        log_info "${START_MARK} Launching automated Wine+GDB crash audit..."

        local TEST_EXE="${PKG_DIR}/bin/ffmpeg.exe"
        [[ ! -f "$TEST_EXE" ]] && TEST_EXE="/opt/ffdest/opt/ffbuild/bin/ffmpeg.exe"

        if ! command -v wine64 &> /dev/null && ! command -v wine &> /dev/null; then
            log_warn "Wine is not installed. Skipping audit."
            return 0
        fi

        export WINEDEBUG="-all,err,seh,bad,fixme:all"
        export WINEARCH=win64
        export DISPLAY=:99

        [[ -z "$TMP_DIR" ]] && TMP_DIR="/tmp"
        local AUDIT_LOG="${TMP_DIR}/ffmpeg_deep_audit.log"
        local CRASH_LOG="${TMP_DIR}/ffmpeg_crash_details.log"
        local CRASH_AUDIT_LOG="${TMP_DIR}/ffmpeg_crash_audit.log"
        mkdir -p "$TMP_DIR"
        rm -f "$CRASH_AUDIT_LOG" "$AUDIT_LOG" "$CRASH_LOG"

        log_debug "${LOG_DEBUG}=======================================================${NC}"
        log_debug "🚨 WINE SMOKE TEST ANALYSIS (DEBUG_MODE=1)"
        log_debug "${LOG_DEBUG}=======================================================${NC}"

        log_info "${START_MARK} Launching Deep Component & Stability Audit..."

        # --- PHASE 1: Dynamic Symbol Verification ---
        if ! verify_all_symbols; then
            log_error "Static linking verification FAILED. Build may be broken."
            # Don't exit 1 immediately, let the rest run to gather more info, but mark failure
            MISSING_SYMBOLS=1
        fi

        # --- PHASE 2: Basic Smoke Tests ---
        # Basic info + a filter chain
        local TEST_SUITE=(
            "-codecs -formats -filters -protocols -pix_fmts"
            "-v debug -f lavfi -i testsrc=size=1280x720:rate=60:duration=2 -f lavfi -i sine=frequency=1000:duration=2 -vf scale=640x360,format=yuv420p -c:v wrapped_avframe -c:a pcm_s16le -f null -"
        )

        log_info "Running deep component crash audit via hybrid winedbg..."
        CRASH_FOUND=0
        CRASH2_FOUND=0
        TEST_INDEX=0 # Счётчик для генерации уникальных имён файлов

        for TEST_ARGS in "${TEST_SUITE[@]}"; do
            ((++TEST_INDEX))
            # Создаем изолированный лог для конкретного подтеста первого этапа
            local PHASE1_LOG="${TMP_DIR}/audit_p1_${TEST_INDEX}.log"
            rm -f "$PHASE1_LOG"

            log_debug "Executing test: ${GREY_B}${TEST_ARGS:0:60}...${NC}"

            # Use --auto mode: robust, fast, and avoids interactive debugger pitfalls
            # It returns 0 on success, non-zero on crash
            if winedbg --auto "$TEST_EXE" $TEST_ARGS >> "$PHASE1_LOG" 2>&1; then
                # Double check: did ffmpeg itself exit with 0?
                # Sometimes winedbg exits 0 even if ffmpeg crashes if the crash is handled.
                # But usually, if winedbg --auto succeeds, the app ran.
                log_debug "Test completed (winedbg exit 0)."
            else
                # winedbg --auto failed -> likely a crash
                log_error "Test failed (winedbg exit non-zero). Checking for crash details..."
                # Extract crash info if available
                if grep -q 'Exception c0000005\|Access Violation\|Segmentation fault' "$PHASE1_LOG"; then
                    log_error "Crash detected!"
                    CRASH_FOUND=1
                    cat "$PHASE1_LOG" >> "$CRASH_AUDIT_LOG"
                    break
                else
                    # It might be a non-critical error (e.g., missing codec)
                    log_warn "Non-zero exit, but no critical crash exception found. Continuing..."
                fi
            fi
            # Переносим данные в общий лог для истории
            cat "$PHASE1_LOG" >> "$CRASH_AUDIT_LOG"
            rm -f "$PHASE1_LOG"
        done

        # Сбрасываем счётчик для второго этапа
        TEST_INDEX=0

        # Сбор бэктрейсов (winedbg --command)
        if [[ $CRASH_FOUND -eq 0 ]]; then
            for TEST_ARGS in "${TEST_SUITE[@]}"; do
                ((++TEST_INDEX))
                PHASE2_LOG="${TMP_DIR}/audit_p2_${TEST_INDEX}.log"
                rm -f "$PHASE2_LOG"

                log_debug "Executing sub-test: ${GREY_B}${TEST_ARGS:0:60}...${NC}"

                # Если ffmpeg падает, cont прерывается, bt печатает стек, kill и quit чисто выходят.
                winedbg --command "cont; bt; kill; quit" "$TEST_EXE" $TEST_ARGS >> "$PHASE2_LOG" 2>&1
                # WINE_EXIT=$?

                # Проверяем лог на наличие критических аппаратных исключений и ошибок памяти
                if grep -Eiq "Access Violation|0xc0000005|0xc0000409|0xc000001d|Segmentation fault|Illegal instruction|Unhandled exception|stack smashing|buffer overflow|stack_chk_fail|stack-buffer-overflow|global-buffer-overflow|access violation|SIGSEGV|illegal instruction" "$PHASE2_LOG"; then
                    log_error "CRITICAL FAULT DETECTED during sub-test: ${TEST_ARGS:0:60}..."
                    CRASH2_FOUND=1
                    cat "$PHASE2_LOG" >> "$CRASH_AUDIT_LOG"
                    break
                fi
                cat "$PHASE2_LOG" >> "$CRASH_AUDIT_LOG"
                rm -f "$PHASE2_LOG"
            done
        fi

        if [[ -f "$CRASH_AUDIT_LOG" && -s "$CRASH_AUDIT_LOG" ]]; then
            if [[ $CRASH_FOUND -eq 1 ]]; then
                log_error "CRASH DETECTED."
                cat "$CRASH_AUDIT_LOG" >&2
            elif [[ $CRASH2_FOUND -eq 1 ]]; then
                log_debug "Relevant Crash Backtrace:"
                sed -n '/Backtrace:/,$p' "$CRASH_AUDIT_LOG" >&2 || cat "$CRASH_AUDIT_LOG" >&2
            else
                log_debug "No critical errors found in log."
            fi
        fi

        # --- PHASE 3: Generate Component Tests ---
        generate_component_tests

        # Add a generic "stability" test if no specific components found or as a baseline
        if [[ ${#COMPREHENSIVE_TESTS[@]} -eq 0 ]]; then
            COMPREHENSIVE_TESTS+=("-loglevel warning -f lavfi -i testsrc2=d=1 -c:v wrapped_avframe -f null -")
        fi

        local TOTAL_TESTS=${#COMPREHENSIVE_TESTS[@]}
        local FAILED_TESTS=0
        TEST_INDEX=0

        # --- PHASE 4: Execute Component Tests ---
        for i in "${!COMPREHENSIVE_TESTS[@]}"; do
            local TEST_ARGS="${COMPREHENSIVE_TESTS[$i]}"
            local TEST_NUM=$((i + 1))
            # Extract codec name for logging (heuristic)
            local CODEC_NAME=$(echo "$TEST_ARGS" | grep -oE "lib[a-z0-9]+|svt[a-z0-9]+" | head -1)
            [[ -z "$CODEC_NAME" ]] && CODEC_NAME="Generic"

            log_debug "Running Test ${TEST_NUM}/${TOTAL_TESTS}: ${CYAN}${CODEC_NAME}${NC}..."
            local PHASE_LOG="${TMP_DIR}/audit_phase_${TEST_NUM}.log"

            # Run with timeout and winedbg --auto
            # Timeout prevents hanging on deadlocks
            if timeout 60s winedbg --auto "$TEST_EXE" $TEST_ARGS >> "$PHASE_LOG" 2>&1; then
                log_debug "   -> Passed (Exit 0)"
            else
                local EXIT_CODE=$?
                if [[ $EXIT_CODE -eq 124 ]]; then
                    log_error "   -> FAILED: TIMEOUT (Hang detected in ${CODEC_NAME})"
                    FAILED_TESTS=$((FAILED_TESTS + 1))
                    cat "$PHASE_LOG" >> "$AUDIT_LOG"
                    continue
                fi

                # Check for crash signatures in the log
                if grep -qE "Exception c0000005|Access Violation|Segmentation fault|0xc000001d|Illegal instruction" "$PHASE_LOG"; then
                    log_error "   -> FAILED: CRASH detected in ${CODEC_NAME}"
                    FAILED_TESTS=$((FAILED_TESTS + 1))

                    echo "=== CRASH REPORT: ${CODEC_NAME} ===" > "$CRASH_LOG"
                    echo "Command: ffmpeg $TEST_ARGS" >> "$CRASH_LOG"
                    echo "Exit Code: $EXIT_CODE" >> "$CRASH_LOG"
                    echo "Timestamp: $(date)" >> "$CRASH_LOG"
                    echo "--- Log Snippet ---" >> "$CRASH_LOG"
                    grep -A 5 -B 5 "Exception\|Access Violation" "$PHASE_LOG" >> "$CRASH_LOG"
                    cat "$CRASH_LOG" >&2
                    cat "$PHASE_LOG" >> "$AUDIT_LOG"
                else
                    log_warn "   -> Non-zero exit ($EXIT_CODE) but no crash signature."
                    cat "$PHASE_LOG" >> "$AUDIT_LOG"
                fi
            fi
            rm -f "$PHASE_LOG"
        done

        # --- PHASE 5: Final Report ---
        log_debug "${LOG_DEBUG}=======================================================${NC}"

        if [[ $CRASH_FOUND -eq 1 || $CRASH2_FOUND -eq 1 ]]; then
            log_error "HARDWARE FAULT, ILLEGAL INSTRUCTION OR ACCESS VIOLATION DETECTED!"
            log_error "Please review the Backtrace (bt) output printed above."
            # return 1 # Явно валим функцию, если бинарник дефектный
        elif [[ $FAILED_TESTS -gt 0 ]]; then
            log_error "AUDIT FAILED: ${FAILED_TESTS}/${TOTAL_TESTS} tests failed."
            # return 1 # Явно валим функцию, если тесты не прошли
        elif [[ $MISSING_SYMBOLS -eq 1 ]]; then
            log_error "AUDIT FAILED: Missing static symbols detected."
            # return 1
        else
            log_info "${CHECK_MARK} Wine runtime smoke test passed successfully. Binary structure is solid."
            log_info "${CHECK_MARK} Deep Component Audit PASSED. All critical paths stable."
            [[ -f "$AUDIT_LOG" ]] && mv "$AUDIT_LOG" "${TMP_DIR}/last_deep_audit.log" 2>/dev/null
            [[ -f "$CRASH_AUDIT_LOG" ]] && mv "$CRASH_AUDIT_LOG" "${TMP_DIR}/last_audit_run.log" 2>/dev/null
            return 0
        fi
    }

    # run Deep Audit
    run_deep_component_audit
fi

# =======================================
# FFMPEG FINAL STAGE
# =======================================
# Стриппинг бинарников (удаление отладочных символов)
# --strip-all; --strip-unneeded
if [[ "$SKIP_POST_STRIP" != "1" ]]; then
    if declare -F strip_files >/dev/null; then
        strip_files "${PKG_DIR}/bin" "ffmpeg"
    else
        log_warn "strip_files function not found, falling back to basic strip"
        find "${PKG_DIR}/bin" -type f \( -name "*.exe" -o -name "*.dll" \) -exec "${FFBUILD_CROSS_PREFIX}strip" --strip-unneeded {} \;
    fi
fi

# Заходим в pkgroot, чтобы внутри архива не было лишних вложенных папок
pushd "$FFMPEG_PKG_ROOT"

# Упаковка
log_info "${ARCH_MARK} Creating archive: ${BUILD_NAME}.7z"
if [[ "$DEBUG_MODE" == "1" ]]; then
    log_info "${SAVE_MARK} Gathering all generated debug files..."
    # Находим все .debug файлы в девелоперском префиксе и копируем их в структуру релиза к исполняемым файлам
    find "${FFBUILD_PREFIX}" -type f -name "*.debug" -exec cp {} "./${BUILD_NAME}/bin/" \; 2>/dev/null || true
    log_info "${SAVE_MARK} Packaging external debug symbols separately..."
    # Находим все созданные .debug файлы и пакуем их отдельно
    7z a -mx7 -mmt=on -r "${FFBUILD_DESTDIR}/${BUILD_NAME}-debug-symbols.7z" "./${BUILD_NAME}/*.debug"
    # Исключаем файлы .debug из основного пользовательского архива
    7z a -mx7 -mmt=on "${FFBUILD_DESTDIR}/${BUILD_NAME}.7z" "./${BUILD_NAME}/*" -xr!"*.debug"
else
    # Обычная сборка без дебаг-файлов
    7z a -mx7 -mmt=on "${FFBUILD_DESTDIR}/${BUILD_NAME}.7z" "./${BUILD_NAME}/*"
fi

popd

# Генерация метаданных для GitHub Actions
if [[ -n "$GITHUB_ACTIONS" ]]; then
    echo "build_name=${BUILD_NAME}" >> "$GITHUB_OUTPUT"
    echo "${BUILD_NAME}.7z" > "${FFBUILD_DESTDIR}/${TARGET}-${VARIANT}.txt"
fi

duration=$SECONDS
elapsed=$(printf '%02dh:%02dm:%02ds' $((duration/3600)) $((duration%3600/60)) $((duration%60)))

log_info "${CHECK_MARK} Build finished after ${GREY_B}${elapsed}${NC}"

exit 0