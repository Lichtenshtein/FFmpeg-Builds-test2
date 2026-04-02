#!/bin/bash

set -o pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# ANSI Color Codes
export LOG_DEBUG='\033[1;35m'  # Purple (Bold)
export LOG_INFO='\033[1;32m'   # Green (Bold)
export LOG_WARN='\033[1;33m'   # Yellow (Bold)
export LOG_ERROR='\033[1;31m'  # Red (Bold)
export LOG_NC='\033[0m'        # No Color (Reset)
export RED='\033[0;31m'        # Red
export GREEN='\033[0;32m'      # Green
export YELLOW='\033[0;33m'     # Yellow
export PURPLE='\033[0;35m'     # Purple
export NC='\033[0m'            # No Color (Reset)
export CHECK_MARK="${LOG_INFO}✔${NC}"
export CROSS_MARK='❌'
export XCLAM_MARK='⚠️'
export BROOM_MARK='🧹'
export CACHE_MARK='🗄️'
export ARCH_MARK='📥️'
export SAVE_MARK='💾'
export SEARCH_MARK='🔎'
export EXTR_MARK='📤'
export START_MARK='🚀'
export BUILD_MARK='🛠️'
export DIRS_MARK='📂'
export LOCK_MARK='🔒'
export SYNC_MARK="${LOG_INFO}♻${NC}"
export TARGET_MARK='🎯'
export DOWN_MARK="${LOG_INFO}🡇${NC}"
export LOGS_MARK="${LOG_DEBUG}🗎${NC}"

# Функции для логирования пишут в stderr (>&2)
log_info()  { echo -e "${LOG_INFO}[INFO]${LOG_NC}  $*" >&2; }
log_warn()  { echo -e "${LOG_WARN}[WARN]${LOG_NC}  ${XCLAM_MARK} $*" >&2; }
log_error() { echo -e "${LOG_ERROR}[ERROR]${LOG_NC} ${CROSS_MARK} $*" >&2; }
log_debug() { echo -e "${LOG_DEBUG}[DEBUG]${LOG_NC} $*" >&2; }

print_info()  { printf '%b[INFO]%b  %s\n' "${LOG_INFO}" "${LOG_NC}" "$*" >&2; }
print_warn()  { printf '%b[WARN]%b %s\n' "${LOG_WARN}" "${LOG_NC}"  "${XCLAM_MARK}" "$*" >&2; }
print_error() { printf '%b[ERROR]%b %s\n' "${LOG_ERROR}" "${LOG_NC}"  "${CROSS_MARK}" "$*" >&2; }
print_debug() { printf '%b[DEBUG]%b %s\n' "${LOG_DEBUG}" "${LOG_NC}" "$*" >&2; }

log_info_line() { echo -e "${LOG_INFO}[INFO]${LOG_NC}  ################################################################" >&2; }
log_err_line()  { echo -e "${LOG_ERROR}[ERROR]${LOG_NC} !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2; }

export -f log_info log_warn log_error log_debug log_info_line log_err_line print_info print_warn print_error print_debug

# Creation and Unification of paths and path variables
# Define the project root (ROOT_DIR)
# If we're in Docker, the root is /builder; if on the HOST, the root is the script folder.
if [[ -d "/builder" ]]; then
    export ROOT_DIR="/builder"
    export CACHE_DIR="/root/.cache/downloads"
else
    # Находим корень, где бы ни лежал vars.sh (в корне или в util/)
    export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    export CACHE_DIR="$ROOT_DIR/.cache/downloads"
fi

# Build variables (inside the container)
# Prefer positional args, fall back to ENV
export TARGET="${1:-$TARGET}"
export VARIANT="${2:-$VARIANT}"
# pkg-config variables
export PKG_CONFIG_PATH="" # don't touch
export PKG_CONFIG_FLAGS="--static"
export PKG_CONFIG_LIBDIR="/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig:/opt/ffbuild/lib64/pkgconfig"
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=0
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=0
# use env vars with broadwell fallback
export CPU_ARCH="${CPU_ARCH:-broadwell}"
export CPU_TUNE="${CPU_TUNE:-broadwell}"
# Build variables (inside the container)
# just duplicate from Dockerfile for convenience
export TOOLCHAIN_BIN="/opt/ct-ng/bin"
export FFBUILD_RUST_TARGET="x86_64-pc-windows-gnu"
export FFBUILD_TOOLCHAIN="x86_64-w64-mingw32"
export FFBUILD_CROSS_PREFIX="x86_64-w64-mingw32-"
export FFBUILD_PREFIX="/opt/ffbuild" # Куда ставим зависимости
export FFBUILD_DESTDIR="/opt/ffdest" # Куда кладем финальный архив ffmpeg (.7z)
export FFBUILD_DESTPREFIX="$FFBUILD_DESTDIR$FFBUILD_PREFIX"
# directory for saving .pc files from components
export PC_DIR="$FFBUILD_DESTPREFIX/lib/pkgconfig"
# directory for storing .vars files with
# component variables and flags collected between stages
export VARS_DIR="$FFBUILD_PREFIX/config_parts"

# Shared project folders
export ADDINS_DIR="$ROOT_DIR/addins"
export PATCHES_DIR="$ROOT_DIR/patches"
export SCRIPTS_DIR="$ROOT_DIR/scripts.d"
export TMP_DIR="$ROOT_DIR/.cache/tmp"
export UTIL_DIR="$ROOT_DIR/util"
export VARIANTS_DIR="$ROOT_DIR/variants"

# ffmpeg paths inside the build's working directory (/builder/ffbuild)
export FFMPEG_DIR="$ROOT_DIR/.cache/ffmpeg"
export FFMPEG_BUILD_ROOT="$ROOT_DIR/ffbuild"
export FFMPEG_SOURCE_DIR="$FFMPEG_BUILD_ROOT/ffmpeg"
export FFMPEG_PKG_ROOT="$FFMPEG_BUILD_ROOT/pkgroot"
export FFMPEG_CONFIG_LOG="$FFMPEG_SOURCE_DIR/ffbuild/config.log"
export FFMPEG_HASH_FILE="$FFMPEG_DIR/.current_commit" # хеш последнего скачанного коммита

# Create the base structure if it doesn't exist
if [[ -d "/builder" ]]; then
    mkdir -p "$VARS_DIR" "$FFBUILD_DESTDIR" "$FFBUILD_DESTPREFIX"/{include,bin,lib/pkgconfig}
fi
mkdir -p "$CACHE_DIR" "$TMP_DIR" "$FFMPEG_BUILD_ROOT" "$FFMPEG_DIR"

# export STAGENAME="$(basename "$STAGE" .sh)"
# Extract the component name (e.g., from 50-libmp3lame we get libmp3lame)
# Use sed to trim everything up to and including the first hyphen
# export COMPONENT_NAME=$(echo "$STAGENAME" | sed 's/^[0-9]*-//')

# Dynamic variables. I'm not sure if this will work
export STAGENAME="$(basename "$STAGE" .sh)"
export COMPONENT_NAME="${STAGENAME#*-}"
export STAGE_CACHE_FILE="${CACHE_DIR}/${STAGENAME}_${STAGE_HASH}.tar.zst"
export STAGE_LATEST_LINK="${CACHE_DIR}/${STAGENAME}.tar.zst"

# Flags for the component build stage

[[ "$USE_OPENMP" == "1" ]] && OPENMP_C=" -fopenmp" && OPENMP_LIB="-lgomp "

BASE_CFLAGS="-mms-bitfields -fstack-protector-strong${OPENMP_C}"
BASE_CPPFLAGS="-D__USE_MINGW_ANSI_STDIO=1 -U_WIN32_WINNT -D_WIN32_WINNT=0x0A00 -D_WIN32 -D_FORTIFY_SOURCE=2"
SYSTEM_LIBS="${OPENMP_LIB}-lsetupapi -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lws2_32 -lbcrypt -pthread"
ADDITIONAL_LIBS="-lusp10 -lmsimg32 -lcfgmgr32 -lruntimeobject -ldwrite -ld2d1 -lwindowscodecs -lopengl32 -lssp -lgdi32 -lrpcrt4 -luserenv -liphlpapi -lwinmm -luuid -ldnsapi -lcrypt32 -lwldap32 -lnormaliz"

# disable -fPIC, -ffast-math, if troubles occur
export CFLAGS="-march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe $BASE_CFLAGS -std=gnu11"
export CPPFLAGS="-I/opt/ffbuild/include $BASE_CPPFLAGS"
export CXXFLAGS="-march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe $BASE_CFLAGS -std=gnu++17"
export LDFLAGS="-Wl,-Bstatic -static -static-libgcc -static-libstdc++ -L/opt/ffbuild/lib -pipe -Wl,--high-entropy-va -Wl,--nxcompat -Wl,--dynamicbase -Wl,--reduce-memory-overheads -Wl,--stack,16777216"
export LIBS="${LIBS:-$SYSTEM_LIBS}"
export RUSTFLAGS="-C target-feature=+crt-static -C target-cpu=${CPU_ARCH}"
# Обработка флагов, специфичных для Linux ELF
if [[ "$TARGET" == *"win"* ]]; then
    # бесполезно при сборке под Windows и ломает OpenSSL asm вместе с std=c11
    export CFLAGS="${CFLAGS//-fno-semantic-interposition/}"
    export CXXFLAGS="${CXXFLAGS//-fno-semantic-interposition/}"
    # На всякий случай проверяем и пустую переменную, если она была задана в Docker
    [[ "$CFLAGS" == *"-fno-semantic-interposition"* ]] && log_debug "${BROOM_MARK} Stripped ELF-specific flags for Windows target."
    export CFLAGS="${CFLAGS//-std=c11/-std=gnu11}"
    export CXXFLAGS="${CXXFLAGS//-std=c++17/-std=gnu++17}"
else
    export STAGE_CFLAGS="-fno-semantic-interposition" 
    export STAGE_CXXFLAGS="-fno-semantic-interposition"
    export LIBS="${LIBS:-$SYSTEM_LIBS} -lrt -ld"
fi

# Validate TARGET and VARIANT only enforce when called directly OR when
# arguments were explicitly passed (sourced scripts may not pass args)
if [[ "${BASH_SOURCE}" == "${0}" ]] || [[ $# -ge 2 ]]; then
    if [[ -z "$TARGET" || -z "$VARIANT" ]]; then
        log_error "Missing TARGET or VARIANT. Usage: source vars.sh [target] [variant]"
        return 1 2>/dev/null || exit 1
    fi
fi

# Shift positional args only if they were passed
if [[ $# -ge 2 ]]; then shift 2; fi

# Validate variant file exists (only if TARGET and VARIANT are known)
if [[ -n "$TARGET" && -n "$VARIANT" ]]; then
    if ! [[ -f "variants/${TARGET}-${VARIANT}.sh" ]]; then
        log_error "Invalid target/variant: ${TARGET}-${VARIANT}"
        return 1 2>/dev/null || exit 1
    fi
fi

export LICENSE_FILE="COPYING.LGPLv2.1"

ADDINS=()
ADDINS_STR=""
while [[ "$#" -gt 0 ]]; do
    # Проверяем, существует ли файл в addins
    if [[ -f "addins/${1}.sh" ]]; then
        ADDINS+=( "$1" )
        ADDINS_STR="${ADDINS_STR}${ADDINS_STR:+-}$1"
    else
        # Если файла нет, просто пропускаем (это может быть lto или skip_ffmpeg)
        log_warn "Note: Argument '$1' is not a valid addin, ignoring."
    fi
    shift
done

REPO="${GITHUB_REPOSITORY:-lichtenshtein/ffmpeg-build}"
REPO="${REPO,,}"
REGISTRY="${REGISTRY_OVERRIDE:-ghcr.io}"
BASE_IMAGE="${REGISTRY}/${REPO}/base:latest"
TARGET_IMAGE="${REGISTRY}/${REPO}/base-${TARGET}:latest"
IMAGE="${REGISTRY}/${REPO}/${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}:latest"

# 1 для подробных логов, в 0 для кратких
# export FFBUILD_VERBOSE=${FFBUILD_VERBOSE:-1}
# Значение FFBUILD_VERBOSE уже пришло из Docker ENV
if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
    export MAKE_V="V=1"
    export NINJA_V="-v"
    export CARGO_V="-v"
else
    export MAKE_V=""
    export NINJA_V=""
    export CARGO_V=""
fi

get_stage_hash() {
    local STAGE_PATH="$1"
    # Берем весь контент файла
    # Удаляем \r (защита от Windows-переносов)
    # Удаляем пустые строки и комментарии (чтобы пробелы не ломали кэш)
    # Считаем хеш от всего остального
    grep -v '^[[:space:]]*#' "$STAGE_PATH" | sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' | grep -v '^[[:space:]]*$' | tr -d '\r' | sha256sum | cut -c1-16
}
export -f get_stage_hash

# Удаляем ANSI цвета
# Удаляем переносы строк (заменяем на пробел)
# xargs схлопнет лишние пробелы в одну строку
clean_val() {
    echo "$*" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" | tr '\n' ' ' | xargs -r -d ' '
}
# быстрые дедупликаторы
dedupe() {
    # Сначала очистим от цвета и лишних пробелов
    local input=$(clean_val "$*")
    [[ -z "$input" ]] && return
    # Переводим в одну строку, удаляем мусор
    local clean=$(echo "$input" | tr ' ' '\n' | grep -vE "Package|not|found|error|^$")
    # Удаляем дубликаты, сохраняя ПЕРВОЕ вхождение
    echo "$clean" | awk '!x[$0]++' | xargs -r -d '\n' | tr '\n' ' '
}
# for ldflags
smart_dedupe() {
    # Сначала очистим от цвета и лишних пробелов
    local input=$(clean_val "$*")
    local clean=$(echo "$input" | tr ' ' '\n' | grep -vE "Package|not|found|error|^$")
    if [[ "$DEDUPE_FLAGS" == "1" ]]; then
        echo "$clean" | awk '!x[$0]++' | xargs -r -d '\n' | tr '\n' ' '
    else
        echo "$clean" | xargs -r -d '\n' | tr '\n' ' '
    fi
}
# for libs
smart_libs_dedupe() {
    # Сначала очистим от цвета и лишних пробелов
    local raw_input=$(clean_val "$*")
    # чистим мусор и ПУТИ, убираем -lstdc++
    local clean=$(echo "$raw_input" | tr ' ' '\n' | \
        grep -vE "Package|not|found|error|^$|^-L|^-lstdc\+\+$")
    # унифицируем pthread: заменяем -lpthread на -pthread
    clean=$(echo "$clean" | sed 's/^-lpthread$/-pthread/')
    if [[ "$DEDUPE_FLAGS" == "1" ]]; then
    # оставляет только ПОСЛЕДНЕЕ вхождение (важно для порядка линковки)
        echo "$clean" | tac | awk '!x[$0]++' | tac | tr '\n' ' ' | xargs -r -d '\n' | tr '\n' ' '
    else
    # Просто склеиваем в одну строку без удаления дублей
        echo "$clean" | tr '\n' ' ' | xargs -r -d '\n' | tr '\n' ' '
    fi
}
export -f clean_val dedupe smart_dedupe smart_libs_dedupe

# Docker stage helpers
ffbuild_dockerstage() {
    if [[ -n "$SELFCACHE" ]]; then
        to_df "RUN --mount=src=${SELF},dst=/stage.sh --mount=src=${SELFCACHE},dst=/cache.tar.zst run_stage /stage.sh"
    else
        to_df "RUN --mount=src=${SELF},dst=/stage.sh run_stage /stage.sh"
    fi
}

ffbuild_dockerlayer() {
    to_df "COPY --link --from=${SELFLAYER} \$FFBUILD_DESTPREFIX/. \$FFBUILD_PREFIX"
}

ffbuild_dockerfinal() {
    to_df "COPY --link --from=${PREVLAYER} \$FFBUILD_PREFIX/. \$FFBUILD_PREFIX"
}

ffbuild_dockerdl() {
    [[ -n "$SCRIPT_REPO" ]] && default_dl .
}

# Конфигурация (собирают флаги от всех скриптов в scripts.d для финального ./configure)
ffbuild_enabled()      { return 0; }
ffbuild_depends()      { echo base; }
# чистим мусор и дедуплицируем, оставляя ПЕРВОЕ вхождение)
ffbuild_configure()    { [[ -n "$*" ]] && export FF_CONFIGURE=$(dedupe "$FF_CONFIGURE $*"); }
ffbuild_cflags()       { [[ -n "$*" ]] && export FF_CFLAGS=$(dedupe "$FF_CFLAGS $*"); }
ffbuild_cppflags()     { [[ -n "$*" ]] && export FF_CPPFLAGS=$(dedupe "$FF_CPPFLAGS $*"); }
ffbuild_cxxflags()     { [[ -n "$*" ]] && export FF_CXXFLAGS=$(dedupe "$FF_CXXFLAGS $*"); }
# Флаги линковщика (используем smart_dedupe - он учитывает переменную DEDUPE_FLAGS)
ffbuild_ldflags()      { [[ -n "$*" ]] && export FF_LDFLAGS=$(smart_dedupe "$FF_LDFLAGS $*"); }
ffbuild_ldexeflags()   { [[ -n "$*" ]] && export FF_LDEXEFLAGS=$(smart_dedupe "$FF_LDEXEFLAGS $*"); }
# Библиотеки (используем smart_libs_dedupe, сохраняем ПОСЛЕДНЕЕ вхождение для линковки)
ffbuild_libs()         { [[ -n "$*" ]] && export FF_LIBS=$(smart_libs_dedupe "$FF_LIBS $*"); }
ffbuild_uncflags()     { return 0; }
ffbuild_unconfigure()  { return 0; }
ffbuild_uncxxflags()   { return 0; }
ffbuild_unldexeflags() { return 0; }
ffbuild_unldflags()    { return 0; }
ffbuild_unlibs()       { return 0; }

# Экспортируем функции, чтобы они были доступны внутри run_stage и других подпроцессов
export -f ffbuild_enabled ffbuild_depends ffbuild_configure ffbuild_cflags ffbuild_cppflags ffbuild_cxxflags ffbuild_ldflags ffbuild_ldexeflags ffbuild_libs ffbuild_unconfigure ffbuild_uncflags ffbuild_uncxxflags ffbuild_unldexeflags ffbuild_unldflags ffbuild_unlibs

patch_pc_files() {
    log_info "${TARGET_MARK} Patching $STAGENAME .pc files..."
    local pc_dir="$PC_DIR"
    local sl="--follow-symlinks"
    [[ -d "$pc_dir" ]] || return 0

    # Locate build-system root (for dependency scanning)
    local src_root="."
    for candidate in ".." "../.."; do
        for f in configure.ac meson.build CMakeLists.txt; do
            [[ -f "$candidate/$f" ]] && { src_root="$candidate"; break 2; }
        done
    done

    # base candidates whose presence we scan for in build configs
    local scan_candidates=(
        zstd lzma bz2 webp openjp2 jpeg tiff png zlib
        libbrotlidec libbrotlienc libbrotlicommon
        iconv lcms2 jbig freetype2 libxml-2.0 libffi intl
    )

    # deduplicate space-separated tokens, normalise -pthread/-lpthread
    # Usage: dedup_flags "token token ..." ["skip_tokens"]
    dedup_flags() {
        echo "$1" | awk -v skip="$2" '
        BEGIN {
            n = split(skip, s)
            for (j=1; j<=n; j++) {
                skip_map[s[j]] = 1
                if (s[j] == "-pthread")  skip_map["-lpthread"] = 1
                if (s[j] == "-lpthread") skip_map["-pthread"]  = 1
            }
        }
        {
            for (i=1; i<=NF; i++) {
                v = $i
                key = (v == "-lpthread") ? "-pthread" : v
                if (!skip_map[key] && !skip_map[v] && !seen[key]++) printf "%s ", v
            }
        }'
    }

    # helper escape string for use as a literal sed pattern
    sed_escape() { printf '%s' "$1" | sed 's/[[\.*^$()+?{|]/\\&/g'; }

    # замена абсолютных путей на переменные
    find "$pc_dir" -maxdepth 1 -name "*.pc" | while read -r pc; do
        [[ -f "$pc" ]] || continue
        log_debug "Correcting values in .pc files:\n$pc"

        # Capitalisation fixes
        sed -i $sl 's/-lWs2_32/-lws2_32/g; s/-lWinmm/-lwinmm/g; s/-lpthread/-pthread/g' "$pc"
        # Remove -lrt (Linux-only, not on Windows)
        sed -i $sl 's/ -lrt\b//g' "$pc"

        # Пересоздание переменных путей
        sed -i $sl '/^prefix=/d; /^exec_prefix=/d; /^libdir=/d; /^includedir=/d; /^bindir=/d' "$pc"
        sed -i $sl "1i prefix=$FFBUILD_PREFIX\nexec_prefix=\${prefix}\nlibdir=\${prefix}/lib\nincludedir=\${prefix}/include\nbindir=\${prefix}/bin" "$pc"

        # Replace absolute paths with variables (only in non-assignment lines)
        sed -i $sl '/=/! s|'"$FFBUILD_PREFIX"'/include|\${includedir}|g' "$pc"
        sed -i $sl '/=/! s|'"$FFBUILD_PREFIX"'/lib|\${libdir}|g'         "$pc"
        sed -i $sl '/=/! s|'"$FFBUILD_PREFIX"'|\${prefix}|g'             "$pc"

        # Обработка Libs (Улучшенный захват для мульти-библиотечных пакетов)
        local current_libs=$(grep "^Libs:" "$pc" | cut -d':' -f2- | xargs)

        # Ищем путь -L
        local lib_path=$(echo "$current_libs" | grep -oE '\-L[^ ]+' | head -n1)
        [[ -z "$lib_path" ]] && lib_path='-L${libdir}'
        
        # Определяем базовое имя (например 'lcms2' из 'lcms2.pc')
        local base_name=$(basename "$pc" .pc)
        # strip leading 'lib' prefix
        base_name="${base_name#lib}"

        # Collect all -l flags whose name starts with base_name
        # Use grep with word-boundary-like pattern; escape dots in base_name
        local escaped_base=$(sed_escape "$base_name")
        local main_libs=$(echo "$current_libs" | grep -oE "\-l${escaped_base}[a-zA-Z0-9_-]*" | xargs)
        # Fallback: just take the first -l flag
        [[ -z "$main_libs" ]] && main_libs=$(echo "$current_libs" | grep -oE '\-l[a-zA-Z0-9_.+-]+' | head -n1)

        # Compute leftover flags (→ Libs.private) strip lib_path and each main_lib token using awk (avoids regex metachar issues)
        local leftovers
        leftovers=$(echo "$current_libs" | awk -v lp="$lib_path" -v ml="$main_libs" '{
            n = split(ml, m)
            for (i=1; i<=NF; i++) {
                if ($i == lp) continue
                skip=0; for (j=1; j<=n; j++) if ($i == m[j]) { skip=1; break }
                if (!skip) printf "%s ", $i } }')

        # Write clean public Libs line
        sed -i $sl "s|^Libs:.*|Libs: $lib_path $main_libs|" "$pc"

        # Dependency scanner (Autotools, CMake, Meson)
        local extra_libs=""
        local extra_requires=""
        for lib in "${scan_candidates[@]}"; do
            local pc_found=0
            for dir in \
                "$FFBUILD_PREFIX/lib/pkgconfig" \
                "$FFBUILD_PREFIX/share/pkgconfig" \
                "$FFBUILD_PREFIX/lib64/pkgconfig"
            do
                [[ -f "$dir/${lib}.pc" || -f "$dir/lib${lib}.pc" ]] && { pc_found=1; break; }
            done
            (( pc_found )) || continue
            local search_term="$lib"
            [[ "$lib" == libbrotli* ]] && search_term="brotli"
            grep -rqiE \
                "(have_lib|#define.*HAVE_LIB|found|find_package.*)[[:space:]]*[(_]?${search_term}" \
                "$src_root" \
                --include="config.*" --include="*.ac" \
                --include="*.cmake" --include="CMakeLists.txt" \
                --include="meson.build" --include="*.meson" \
                -m1 2>/dev/null || continue
            case "$lib" in
                iconv|bz2|zlib|jpeg)
                    extra_libs+=" -l${lib#lib}" ;;
                *)
                    extra_requires+=" $lib" ;;
            esac
        done

        # Add -lstdc++ if the project has any C++ sources
        find "$src_root" -maxdepth 2 \( -name "*.cpp" -o -name "*.cc" \) 2>/dev/null | grep -q . && extra_libs+=" -lstdc++"

        # Merge Cflags.private → Cflags
        local cflags_priv
        cflags_priv=$(grep "^Cflags.private:" "$pc" | cut -d':' -f2- | xargs)
        if [[ -n "$cflags_priv" ]]; then
            sed -i $sl "/^Cflags:/ s/$/ $cflags_priv/" "$pc"
            sed -i $sl '/^Cflags.private:/d' "$pc"
        fi

        # Ensure Requires.private and Libs.private fields exist
        if ! grep -q "^Requires.private:" "$pc"; then
            local insert_ref="Version"
            grep -q "^Version:" "$pc" || insert_ref="Name"
            sed -i $sl "/^${insert_ref}:/ a Requires.private:" "$pc"
        fi
        if ! grep -q "^Libs.private:" "$pc"; then
            sed -i $sl "/^Libs:/ a Libs.private:" "$pc"
        fi

        # Append discovered deps (raw, dedup happens)
        sed -i $sl "/^Requires.private:/ s|$| $extra_requires|" "$pc"
        sed -i $sl "/^Libs.private:/ s|$| $leftovers $extra_libs $LIBS|" "$pc"

        # Apply -lzlib → -lz (after all -l tokens are in the file)
        sed -i $sl 's/-lzlib\b/-lz/g' "$pc"

        # Smart deduplication
        # Cflags: simple dedup + -pthread alias
        local cflags_line
        cflags_line=$(grep "^Cflags:" "$pc" | cut -d':' -f2- | xargs)
        if [[ -n "$cflags_line" ]]; then
            local clean_cflags
            clean_cflags=$(dedup_flags "$cflags_line")
            sed -i $sl "s|^Cflags:.*|Cflags: $clean_cflags|" "$pc"
        fi

        # Requires.private: remove anything already in Requires
        local pub_req
        pub_req=$(grep "^Requires:" "$pc" | grep -v "^Requires.private:" | cut -d':' -f2- | tr ',' ' ' | xargs)
        local rp_line
        rp_line=$(grep "^Requires.private:" "$pc" | cut -d':' -f2- | tr ',' ' ' | xargs)
        if [[ -n "$rp_line" ]]; then
            local clean_rp
            clean_rp=$(dedup_flags "$rp_line" "$pub_req")
            sed -i $sl "s|^Requires.private:.*|Requires.private: $clean_rp|" "$pc"
        fi

        # Libs.private: remove anything already covered by Libs or any Requires
        local all_req
        all_req=$(grep -E "^Requires(\.private)?:" "$pc" | cut -d':' -f2- | tr ',' ' ' | xargs)
        local pub_libs
        pub_libs=$(grep "^Libs:" "$pc" | cut -d':' -f2- | xargs)
        local lp_line
        lp_line=$(grep "^Libs.private:" "$pc" | cut -d':' -f2- | xargs)
        if [[ -n "$lp_line" ]]; then
            local skip_for_lp
            skip_for_lp=$(echo "$all_req $pub_libs" | awk '{
                for(i=1;i<=NF;i++){
                    print $i
                    if ($i !~ /^-/) print "-l" $i } }' | xargs)
            local clean_lp
            clean_lp=$(dedup_flags "$lp_line" "$skip_for_lp")
            sed -i $sl "s|^Libs.private:.*|Libs.private: $clean_lp|" "$pc"
        fi

        # Remove fields that ended up empty
        sed -i $sl '/^Requires\.private:[[:space:]]*$/d' "$pc"
        sed -i $sl '/^Libs\.private:[[:space:]]*$/d'     "$pc"
        # Collapse multiple spaces, strip trailing whitespace
        sed -i $sl 's/  \+/ /g; s/[[:space:]]*$//' "$pc"
        # sed -i $sl '/^$/d' "$pc"
    done
}
export -f patch_pc_files

get_deps_list() {
    set +o pipefail 
    if [[ "${FFBUILD_VERBOSE:-0}" -lt 1 ]]; then
        return 0
    fi
    local name="${STAGENAME:-${0##*/}}"
    local lib_dir="$FFBUILD_DESTPREFIX/lib"
    local bin_dir="$FFBUILD_DESTPREFIX/bin"
    local sys_libs="libc\.so|libm\.so|libdl\.so|librt\.so|libpthread\.so|libgcc_s\.so|libstdc\+\+\.so|ld-linux|libresolv\.so|libutil\.so"

    # Создаем временный файл для сбора вывода
    local tmp_out=$(mktemp)

    # Поиск pkg-config
    if [[ -d "$lib_dir/pkgconfig" ]]; then
        find "$lib_dir/pkgconfig" -name "*.pc" -exec bash -c '
            pc_file="$1"; pkg_config_cmd="$2"; xclam_mark="$3"; search_mark="$4"; current_pc_dir="$5"; red_color="$6"; reset_color="$7"
            export PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR:$current_pc_dir"
            export PKG_CONFIG_SYSROOT_DIR="/"

            printf "\n%b %s\n" "$xclam_mark" "$pc_file"
            cat "$pc_file"
            printf "\n%b DEPS for %s:\n" "$search_mark" "${pc_file##*/}"

            deps=$($pkg_config_cmd --print-requires --print-requires-private "$pc_file" 2>/dev/null || true)
            if [[ -n "$deps" ]]; then
                echo "$deps"
                while IFS= read -r pkg_line; do
                    pkg_name=$(echo "$pkg_line" | awk "{print \$1}")
                    [[ -z "$pkg_name" || "$pkg_name" =~ ^[0-9] ]] && continue
                    if ! $pkg_config_cmd --exists "$pkg_name" 2>/dev/null; then
                        echo -e "${red_color}MISSING DEPENDENCY (ERR_MARK): $pkg_name (Searched in: $PKG_CONFIG_LIBDIR)${reset_color}"
                    fi
                done <<< "$deps"
            else
                echo "No pkg-config dependencies listed."
            fi
        ' _ {} "${PKG_CONFIG:-pkg-config}" "$XCLAM_MARK" "$SEARCH_MARK" "$lib_dir/pkgconfig" "$LOG_ERROR" "$LOG_NC" \; >> "$tmp_out" || true
    fi
    # Поиск динамических библиотек (readelf)
    find "$lib_dir" "$bin_dir" -type f \( -name "*.so*" -o -name "*.exe" -o -name "*.dll" \) -print0 2>/dev/null | \
    xargs -0 -r -I{} bash -c '
        file="$1"; toolchain_prefix="$2"; sys_libs_regex="$3"; xclam_mark="$4"
        if "${toolchain_prefix}-readelf" -h "$file" &>/dev/null; then
            raw_deps=$("${toolchain_prefix}-readelf" -d "$file" 2>/dev/null | awk "/NEEDED/ { gsub(/.*\[|\]/, \"\"); print }")
            clean_deps=$(echo "$raw_deps" | awk "!/$sys_libs_regex/")
            if [[ -n "$clean_deps" ]]; then
                printf "\n%b NEEDED LIBRARIES for %s:\n%s\n" "$xclam_mark" "$file" "$clean_deps"
            fi
        fi
    ' _ {} "$FFBUILD_TOOLCHAIN" "$sys_libs" "$XCLAM_MARK" >> "$tmp_out" || true
    # Поиск внешних символов в статике (nm) с фильтрацией системных вызовов
    find "$lib_dir" -name "*.a" -print0 2>/dev/null | \
    xargs -0 -r -I{} bash -c '
        file="$1"; toolchain_prefix="$2"; xclam_mark="$3"; sys_libs_regex="$4"
        raw_symbols=$("${toolchain_prefix}-nm" -u "$file" 2>/dev/null)
        if [[ -n "$raw_symbols" ]]; then
            clean_symbols=$(echo "$raw_symbols" | \
                awk "!/^[[:space:]]*$/ && !/@@/ && !/__imp_/" | \
                grep -Ev "($sys_libs_regex)" | \
                sort -u | head -n 10)
            if [[ -n "$clean_symbols" ]]; then
                printf "\n%b EXTERNAL SYMBOLS (TOP 10) in %s:\n%s\n" "$xclam_mark" "$file" "$clean_symbols"
            fi
        fi
    ' _ {} "$FFBUILD_TOOLCHAIN" "$XCLAM_MARK" "$sys_libs" >> "$tmp_out" || true
    # Проверка RPATH
    find "$lib_dir" "$bin_dir" -type f \( -name "*.so*" -o -executable \) -print0 2>/dev/null | \
    xargs -0 -r -I{} bash -c '
        file="$1"; toolchain_prefix="$2"; xclam_mark="$3"
        if "${FFBUILD_TOOLCHAIN}-readelf" -h "$file" &>/dev/null; then
            rpath=$("${FFBUILD_TOOLCHAIN}-objdump" -p "$file" 2>/dev/null | awk "/RPATH|RUNPATH/ {print}")
            if [[ -n "$rpath" ]]; then
                printf "\n%b RPATH/RUNPATH for %s:\n%s\n" "$xclam_mark" "$file" "$rpath"
            fi
        fi
    ' _ {} "$FFBUILD_TOOLCHAIN" "$XCLAM_MARK" >> "$tmp_out" || true

    # Финальное условие вывода
    if [[ -s "$tmp_out" ]]; then
        log_debug "Showing dependencies for ${name}:"
        cat "$tmp_out" | sed 's/(ERR_MARK)//g' # Убираем техническую метку при выводе
        local error_count=$(grep -c "ERR_MARK" "$tmp_out" || true)
        if [[ "$error_count" -gt 0 ]]; then
            log_error "Found $error_count missing dependencies for $name!"
        else
            log_info "${CHECK_MARK} All pkg-config dependencies are satisfied."
        fi
    else
        log_info "${CHECK_MARK} No dependencies found for $name (meta/header-only component)."
    fi

    rm -f "$tmp_out"
}
export -f get_deps_list

clean_la_files() {
    local target_dir="$FFBUILD_DESTPREFIX"
    [[ ! -d "$target_dir" ]] && return 0
    log_info "${BROOM_MARK} Cleaning up libtool archives (.la) in $target_dir"
    local la_files=$(find "$target_dir" -name "*.la" \( -type f -o -type l \) 2>/dev/null)
    if [[ -n "$la_files" ]]; then
        local count=$(echo "$la_files" | wc -l)
        echo "$la_files" | xargs rm -f 2>/dev/null
        log_info "${CHECK_MARK} Removed $count .la files (including symlinks) from prefix."
    else
        log_info "${CHECK_MARK} No .la files found to clean."
    fi
}
export -f clean_la_files

# 1. Standard
# 2. Binary (for CRLF issues)
# 3. Ignore Whitespace
# 4. Max Fuzz (fuzz=3)
apply_patches() {
    local PATCH_DIR="$PATCHES_DIR/$COMPONENT_NAME"

    if [[ -d "$PATCH_DIR" ]]; then
        # Ensure there are actually .patch files to avoid loop errors
        shopt -s nullglob
        for patch in "$PATCH_DIR"/*.patch; do
            log_info "${TARGET_MARK} APPLYING PATCH: $(basename "$patch")"
            local strategies=(
                "-p1 -N -r -"
                "-p1 -N -r - --binary"
                "-p1 -N -r - -l"
                "-p1 -N -r - -l --fuzz=3"
            )

            local success=false
            for opts in "${strategies[@]}"; do
                log_debug "Trying: patch $opts"
                if patch $opts < "$patch" >/dev/null 2>&1; then
                    log_info "${CHECK_MARK} SUCCESS: Applied with [$opts]"
                    success=true
                    break
                fi
            done

            if [ "$success" = false ]; then
                log_error "FAILED: All attempts to apply $(basename "$patch") failed."
                # return 1 # не прерывать сборку при ошибках
            fi
        done
        shopt -u nullglob
    else
        log_info "${CHECK_MARK} No patches found for $COMPONENT_NAME"
    fi
}
export -f apply_patches

# checking flags validity for final FFmpeg build; if found we just drop them and continue
# tip: check logs after applying \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z |\[?(0|1)?(m|;)?(3.m|) regex to them! search: REGEX replace: empty
check_and_fix_configure() {
    if [[ "$SAFE_CONFIGURE" != "1" ]]; then
        return 0
    fi

    log_info "SAFE_CONFIGURE=1: Checking flags for validity..."

    local new_flags=()
    local dropped=()
    local fixed=()

    # Кэшируем список поддерживаемых опций один раз
    # Включаем и внешние либы (EXTERNAL_LIBRARY_LIST) и общие опции
    local help_output=$(./configure --help)

    for flag in "${CONF_FLAGS[@]}"; do
        # Если флаг содержит '=', пропускаем проверку (это фильтры, энкодеры и т.д.)
        if [[ "$flag" == *=* ]]; then
            new_flags+=("$flag")
            continue
        fi

        # Обрабатываем только --enable-* и --disable-*
        if [[ "$flag" =~ ^--enable- ]] || [[ "$flag" =~ ^--disable- ]]; then
            local action=$(echo "$flag" | cut -d'-' -f3)
            local opt_name=$(echo "$flag" | sed -E 's/--enable-|--disable-//')
            local current_flag="$flag"

            # Блок автозамены (Aliasing)
            case "$opt_name" in
                zstd)          opt_name="libzstd" ;;
                pcre2)         opt_name="libpcre2" ;;
                pcre)          opt_name="libpcre" ;;
                fontconfig)    opt_name="libfontconfig" ;;
                openjpeg)      opt_name="libopenjpeg" ;;
                curl)          opt_name="libcurl" ;; 
                # Можно добавить другие частые ошибки здесь
            esac

            # Формируем потенциально исправленный флаг
            current_flag="--${action}-${opt_name}"

            # Валидация
            # Проверяем наличие опции в выводе help
            if echo "$help_output" | grep -qE "(--(en|dis)able-${opt_name})($|[[:space:]|=])"; then
                if [[ "$current_flag" != "$flag" ]]; then
                    fixed+=("$flag -> $current_flag")
                fi
                new_flags+=("$current_flag")
            else
                dropped+=("$flag")
            fi
        else
            # Все остальные флаги (--prefix, --extra-*) добавляем без изменений
            new_flags+=("$flag")
        fi
    done

    # Вывод отчета
    [ ${#fixed[@]} -ne 0 ] && log_info "${CHECK_MARK} FIXED flags (auto-alias): ${fixed[*]}"
    [ ${#dropped[@]} -ne 0 ] && log_warn "DROPPED invalid flags: ${dropped[*]}"

    # Перезаписываем глобальный массив с сохранением порядка
    CONF_FLAGS=("${new_flags[@]}")
}
export -f check_and_fix_configure

# .la files, dependancies and .pc files auditing
# add ffbuild_dockerbuild() { export SKIP_POST_PATCH=1 } to disable
export SKIP_PRE_PATCH=0
export SKIP_POST_PATCH=0
export SKIP_POST_CLEAN=0
export SKIP_POST_AUDIT=0

# Динамическое определение путей для wine
if [ -d "/opt/ct-ng" ]; then
    MINGW_BIN_PATH="/opt/ct-ng/x86_64-w64-mingw32/x86_64-w64-mingw32/bin"
    if [[ ! -d "$MINGW_BIN_PATH" ]]; then
        # Фолбэк на быстрый поиск, если путь другой
        MINGW_BIN_PATH=$(find /opt/ct-ng -type d -path "*/x86_64-w64-mingw32/bin" -print -quit)
    fi
    # Если WINEPATH уже задан (например, в предыдущем слое или вызове), пропускаем тяжелые вычисления
    if [[ -z "$WINEPATH" ]]; then
        MINGW_BIN_PATH=$(find /opt/ct-ng -maxdepth 5 -type d -name "bin" | grep "x86_64-w64-mingw32/bin" | head -n 1)

        if command -v winepath &>/dev/null; then
            # Выполняем трансляцию путей только один раз
            _p_bin=$(winepath -w "${FFBUILD_PREFIX}/bin" 2>/dev/null | tr -d '\r\n')
            _p_lib=$(winepath -w "${FFBUILD_PREFIX}/lib" 2>/dev/null | tr -d '\r\n')
            _m_bin=$(winepath -w "${MINGW_BIN_PATH}" 2>/dev/null | tr -d '\r\n')

            if [[ -n "$_p_bin" && -n "$_p_lib" ]]; then
                export WINEPATH="${_p_bin};${_p_lib};${_m_bin}"
            else
                # Fallback для окружений без запущенного Wine (например, генерация на хосте)
                export WINEPATH="winepath -w ${FFBUILD_PREFIX}/bin:${FFBUILD_PREFIX}/lib:${MINGW_BIN_PATH}"
            fi
        else
            export WINEPATH="winepath -w ${FFBUILD_PREFIX}/bin:${FFBUILD_PREFIX}/lib:${MINGW_BIN_PATH}"
        fi
        # Выводим инфо о WINEPATH только при его создании
        # [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && printf '%b WINEPATH (Windows style): %s\n' "${LOG_DEBUG}[DEBUG]${LOG_NC} ${DIRS_MARK}" "$WINEPATH"
        [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && print_debug "${DIRS_MARK} WINEPATH (Windows style):\n$WINEPATH"
    fi
fi

# Определяем режим работы Wine (берем из ENV или ставим auto по умолчанию)
USE_WINE="${USE_WINE:-1}"
setup_wine_env() {
    # Сохраняем текущее состояние set -e
    local errexit_state=$([[ $- =~ e ]] && echo "set -e" || echo "set +e")
    set +e # Временно отключаем остановку при ошибках
    # Если Wine принудительно выключен выходим сразу
    if [[ "$USE_WINE" == "0" ]]; then
        eval "$errexit_state"; return 0
    fi

    if [[ "$USE_WINE" == "1" ]]; then
    if [[ -z "$STAGE" || ! -f "$STAGE" ]]; then
         return 0
    fi
        # Ищем только специфичные команды:
        # 1. meson test / ctest / make check - запуск встроенных тестов
        # 2. wine [пробел] - явный запуск через wine
        # 3. ./[что-то].exe - прямой запуск виндового бинарника
        if ! grep -qE "meson test|ctest|make check|make test|wine |\.\/.*\.exe" "$STAGE"; then
            log_debug "Wine: skipped (no execution patterns in $STAGENAME)"
            eval "$errexit_state"; return 0
        fi
    fi

    # Запускаем виртуальный дисплей в фоне, если его еще нет
    if ! pgrep -x "Xvfb" > /dev/null; then
        log_info "${START_MARK} Initializing background Xvfb for Wine tests..."
        # Запуск на дисплее 99 без xvfb-run (меньше оверхед)
        ( Xvfb :99 -screen 0 1024x768x16 >/dev/null 2>&1 & )
        local retry=0
        while [ $retry -lt 15 ]; do
            if DISPLAY=:99 xset -q >/dev/null 2>&1; then break; fi
            sleep 0.2
            ((retry++))
        done
    fi
    export DISPLAY=:99
    # Быстрый "прогрев" сервера Wine, чтобы последующие вызовы не ждали инициализации (чтобы первый вызов в скрипте не тормозил)
    ( wineboot -u >/dev/null 2>&1 & )
    eval "$errexit_state"
}
export -f setup_wine_env

# экспорт важных переменных MinGW, чтобы они пробрасывались в download.sh и run_stage.sh:
export TARGET VARIANT REPO REGISTRY BASE_IMAGE TARGET_IMAGE IMAGE
