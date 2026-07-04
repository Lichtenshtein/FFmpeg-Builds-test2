#!/bin/bash

set -e
# set -xe

shopt -s globstar
cd "$(dirname "$0")"

source util/vars.sh "${1:-$TARGET}" "${2:-$VARIANT}" \
    || { echo "ERROR: vars.sh failed in build.sh" >&2; exit 1; }

export CCACHE_PATH="${CCACHE_PATH}"
export CCACHE_BASEDIR="${CONTAINER_ROOT}"

# a hook announcing that we're at the final stage
export FFMPEG_BUILD_STAGE="1"
export STAGENAME="FFmpeg"

if declare -F apply_lto_policy >/dev/null; then
    apply_lto_policy
fi

# Сброс статистики для чистого лога
ccache -z > /dev/null
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
    ccache -s "${OP_VERB2}"
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
# меняем сигнатуру в заголовочном файле
sed -i 's/AVTextFormatOptions options,/const AVTextFormatOptions \*options,/g' "fftools/textformat/avtextformat.h"
# меняем объявление функции в файле реализации
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

# if [[ -f "${FFBUILD_PREFIX}/lib/pkgconfig/xeve.pc" ]]; then
    # sed -i "s/Version:.*/Version: /" "${FFBUILD_PREFIX}/lib/pkgconfig/xeve.pc"
    # sed -i "s|^Version:.*|Version: 0.5.1|" "${FFBUILD_PREFIX}/lib/pkgconfig/xeve.pc"
# fi

# QUIRC_PC="${FFBUILD_PREFIX}/lib/pkgconfig/quirc.pc"
# if [[ -f "$QUIRC_PC" ]]; then
    # cat <<EOF > "$QUIRC_PC"
# prefix=$FFBUILD_PREFIX
# exec_prefix=\${prefix}
# libdir=\${prefix}/lib
# includedir=\${prefix}/include

# Name: quirc
# Description: QR decoder library, for extracting and decoding them from images
# Version: 1.2
# Libs: -L\${libdir} -lquirc
# Cflags: -I\${includedir}
# EOF
# fi

# QUIRC_PC="${FFBUILD_PREFIX}/lib/pkgconfig/quirc.pc"
# if [[ -f "$QUIRC_PC" ]]; then
    # cat <<EOF > "$QUIRC_PC"
# prefix=$FFBUILD_PREFIX
# exec_prefix=\${prefix}
# libdir=\${prefix}/lib
# includedir=\${prefix}/include

# Name: quirc
# Description: QR decoder library, for extracting and decoding them from images
# Version: ${VER_FULL}
# Libs: -L\${libdir} -Wl,--no-as-needed -lquirc -Wl,--as-needed
# Cflags: -I\${includedir}
# EOF
# fi

# LIBDATACHANNEL_PC="${FFBUILD_PREFIX}/lib/pkgconfig/libdatachannel.pc"
# if [[ -f "$LIBDATACHANNEL_PC" ]]; then
    # cat <<EOF > "$LIBDATACHANNEL_PC"
# prefix=${FFBUILD_PREFIX}
# exec_prefix=\${prefix}
# libdir=\${exec_prefix}/lib
# includedir=\${prefix}/include

# Name: datachannel
# Description: WebRTC Data Channels and Media Transport library (C/C++)
# Version: 0.24.5
# Libs: -L\${libdir} -Wl,--start-group -ldatachannel -ljuice -lsrtp2 -lusrsctp -lws2_32 -liphlpapi -Wl,--end-group
# Requires: openssl
# Libs.private: -lbcrypt -lcrypt32 -luserenv -lstdc++ -lsetupapi -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -pthread
# Cflags: -I\${includedir} -I\${includedir}/rtc $static_flags
# EOF
# fi

log_info "Patching FFmpeg's nvenc_dispatch.c to fix missing v13.0 NVENC symbols..."
NVENC_DISPATCH_SRC="libavcodec/nvenc_dispatch.c"
if [[ -f "$NVENC_DISPATCH_SRC" ]]; then
    # Дописываем реализации функций-заглушек v130 в конец файла nvenc_dispatch.c,
    # Hotfix upstream NVENC v13.0 symbols for MinGW static compilation
#include "avcodec.h"
    cat << 'EOF' >> "$NVENC_DISPATCH_SRC"
extern "C" {
    int ff_nvenc_encode_init130(AVCodecContext *avctx) { return 0; }
    int ff_nvenc_encode_close130(AVCodecContext *avctx) { return 0; }
    int ff_nvenc_receive_packet130(AVCodecContext *avctx, AVPacket *avpkt) { return 0; }
    int ff_nvenc_encode_flush130(AVCodecContext *avctx) { return 0; }
}
EOF
    log_info "nvenc_dispatch.c successfully patched for NVENC 13.0."
fi

# PREFIX_PC="${FFBUILD_PREFIX}/lib/pkgconfig/OpenColorIO.pc"
# if [[ -f "$PREFIX_PC" ]]; then
    # log_info "Fixing OpenColorIO.pc in active prefix..."

    # sed -i -E 's/\.a([[:space:]]|$)/\1/g' "$PREFIX_PC"
    # sed -i -E 's/\.a\b//g' "$PREFIX_PC"

    # sed -i 's/[[:space:]]\+/ /g' "$PREFIX_PC"

    # log_info "--- Content of fixed OpenColorIO.pc ---"
    # cat "$PREFIX_PC"
    # log_info "---------------------------------------"
# else
    # log_error "OpenColorIO.pc NOT FOUND at $PREFIX_PC !"
# fi

# PREFIX_PC="${FFBUILD_PREFIX}/lib/pkgconfig/openal.pc"
# if [[ -f "$PREFIX_PC" ]]; then
    # log_info "Fixing openal.pc in active prefix..."

    # sed -i '/^Libs.private:/ s/$/ -ldsound/' "$PREFIX_PC"

    # log_info "--- Content of fixed openal.pc ---"
    # cat "$PREFIX_PC"
    # log_info "---------------------------------------"
# fi

# log_info "Injecting hotfix stub for broken upstream OpenVINO symbol..."

# cat << 'EOF' > /tmp/ggml_openvino_stub.cpp
# # include <stdint.h>
# extern "C" void* ggml_backend_openvino_reg(void) {
#     return nullptr;
# }
# EOF
# 
# ${FFBUILD_TOOLCHAIN}-g++ -c /tmp/ggml_openvino_stub.cpp -o /tmp/ggml_openvino_stub.o
# ${FFBUILD_CROSS_PREFIX}ar rcs ${FFBUILD_PREFIX}/lib/libggml_openvino_stub.a /tmp/ggml_openvino_stub.o

THPENC_C="libavformat/thpenc.c"
if [ -f "$THPENC_C" ]; then
    log_info "Fixing outdated packet_list API inside custom muxer: $THPENC_C..."

    sed -i 's/avpriv_packet_list_put/ff_packet_list_put/g' "$THPENC_C"
    sed -i 's/avpriv_packet_list_get/ff_packet_list_get/g' "$THPENC_C"
    sed -i 's/avpriv_packet_list_free/ff_packet_list_free/g' "$THPENC_C"

    # Новые функции ff_packet_list_* требуют инклюд "packet_list.h" вместо старых кодековых.
    if ! grep -q '#include "packet_list.h"' "$THPENC_C"; then
        sed -i '2i #include "packet_list.h"' "$THPENC_C"
    fi
fi

# log_info "Mass-patching outdated AVCodec structure fields (.sample_fmts, .pix_fmts)..."

# find libavcodec/ -type f -name "*.c" -exec sed -i \
    # -e 's/\.p\.sample_fmts/\.sample_fmts/g' \
    # -e 's/\.p\.pix_fmts/\.pix_fmts/g' {} +


# =======================================
# FLAGS AND LIBS PROCESSING SECTION
# =======================================
# Удаляем жесткий -static и -Wl,-Bstatic из базовых флагов линковщика
# LDFLAGS=$(echo " ${LDFLAGS} " | sed -e 's/ -static / /g' -e 's/ -Wl,-Bstatic / /g' | xargs)
# FINAL_CONFIGURE=$(echo " ${FINAL_CONFIGURE} " | sed -e 's/ --enable-libsvtjpegxs / /g' | xargs)

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

# ==========================================
# FREI0R PROCESSING
# ==========================================
if [[ "$HAS_FREI0R" == "1" && "$TARGET" == "win64" ]]; then
    log_info "${TARGET_MARK} Patching FFmpeg source to change frei0r plugins default location..."
    sed -i '/static const char\* const frei0r_pathlist\[\] = {/,/};/c\    static const char* const frei0r_pathlist[] = {\n        "frei0r-1/"\n    };' libavfilter/vf_frei0r.c
fi

# ==========================================
# FINAL LIBS GROUP PROCESSING
# ==========================================

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
FINAL_LIBS_GROUPED="-Wl,--start-group ${HYBRID_DYNAMIC_FLAGS}${FINAL_LIBS} -Wl,--end-group -lstdc++"

# =======================================
# FFMPEG AND TOOLCHAIN PARAMS DEBUG
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
    # mold --version | head -n 1
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

    if [[ "$DEBUG_MODE" == "1" ]]; then
        log_info "${SEARCH_MARK} Auditing pkg-config files for overflow triggers..."
        for pc in "${FFBUILD_PREFIX}"/lib/pkgconfig/*.pc; do
            log_debug "Testing pc file: $(basename "$pc")"
            # Проверяем, не падает ли pkgconf на чтении флагов этой либы
            pkgconf --static --libs "$(basename "$pc" .pc)" >/dev/null 2>&1 && log_info "  $(basename "$pc"): OK" || log_error "  $(basename "$pc"): CRASHED OR FAILED"
        done
    fi
    # Специфическая проверка для LTO (наличие плагинов)
    log_info "${BUILD_MARK} Checking LTO support in AR:"
    if "$AR" --help 2>&1 | grep -q "plugin"; then
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
# -lopenal -ldsound -lggml_openvino_stub
# export cflags_libdatachannel="-DRTC_STATIC -DJUICE_STATIC"
# --as="$CC"
# -fno-use-linker-plugin

GCC_LTO_PLUGIN=$("${FFBUILD_CROSS_PREFIX}gcc" -print-prog-name=liblto_plugin.so)

FINAL_LIBS="${FINAL_LIBS//-Wl,--start-group/}"
FINAL_LIBS="${FINAL_LIBS//-Wl,--end-group/}"
FINAL_LIBS="${FINAL_LIBS//-Wl,--no-as-needed/}"
FINAL_LIBS="${FINAL_LIBS//-Wl,--as-needed/}"
FINAL_LIBS=$(echo "$FINAL_LIBS" | xargs)

CONF_FLAGS=(
    --prefix="$INSTALL_ROOT"
    "${TARGET_FLAGS_ARR[@]}"
    --host-cc="ccache gcc"
    --host-ld="mold"
    --host-cflags="$HOST_CFLAGS $HOST_CPPFLAGS"
    --host-ldflags="$HOST_LDFLAGS"
    --extra-cflags="${FINAL_CFLAGS}"
    --extra-cxxflags="${FINAL_CXXFLAGS}"
    --extra-ldflags="-mconsole ${FINAL_LDFLAGS} -Wl,--entry=mainCRTStartup -Wl,--allow-multiple-definition -Wl,-plugin,${GCC_LTO_PLUGIN}"
    --extra-ldexeflags="${FINAL_LDEXEFLAGS} ${FINAL_LIBS_GROUPED}"
    --extra-libs=""
    "${FF_CONF_ARR[@]}"
    --enable-runtime-cpudetect
    --disable-w32threads --enable-pthreads
    --enable-opengl
    --enable-dxva2
    --enable-mediafoundation
    --enable-pic
    # --disable-ffprobe
    --disable-ffplay
    --cc="$CC"
    --cxx="$CXX"
    --ar="$AR"
    --ld="$CC"
    --nm="$NM"
    --as="$AS"
    --ranlib="$RANLIB"
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
# if [[ "$HAS_LIBLCEVC_DEC" == "1" ]]; then
    # log_info "Applying precise LCEVC SDK 4.0.0 migration patches..."

    # if [[ -f "libavfilter/vf_lcevc.c" ]]; then
        # Удаляем флаг discontinuity (0) из LCEVC_SendDecoderEnhancementData
        # sed -i 's|LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, 0, sd->data, sd->size)|LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, sd->data, sd->size)|g' libavfilter/vf_lcevc.c

        # Удаляем флаг discontinuity (0) из LCEVC_SendDecoderBase, сдвигая picture и оставляя -1 на месте timeoutUs
        # sed -i 's|LCEVC_SendDecoderBase(lcevc->decoder, in->pts, 0, picture, -1, in)|LCEVC_SendDecoderBase(lcevc->decoder, in->pts, picture, -1, in)|g' libavfilter/vf_lcevc.c

        # log_info "Successfully patched libavfilter/vf_lcevc.c"
    # else
        # log_warn "File libavfilter/vf_lcevc.c not found, skipping."
    # fi

    # if [[ -f "libavcodec/lcevcdec.c" ]]; then
        # Удаляем флаг discontinuity (0) из LCEVC_SendDecoderEnhancementData
        # sed -i 's|LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, 0, sd->data, sd->size)|LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, sd->data, sd->size)|g' libavcodec/lcevcdec.c

        # Удаляем флаг discontinuity (0) из LCEVC_SendDecoderBase, сдвигая picture и оставляя -1 на месте timeoutUs
        # sed -i 's|LCEVC_SendDecoderBase(lcevc->decoder, in->pts, 0, picture, -1, opaque)|LCEVC_SendDecoderBase(lcevc->decoder, in->pts, picture, -1, opaque)|g' libavcodec/lcevcdec.c

        # log_info "Successfully patched libavcodec/lcevcdec.c"
    # else
        # log_error "libavcodec/lcevcdec.c not found!"
    # fi
# fi

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
    log_info "${BUILD_MARK} Launching FFmpeg binary and components debug routine..."
    "$UTIL_DIR"/debug_audit.sh || log_warn "Launching debug audit failed, but continuing..."
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