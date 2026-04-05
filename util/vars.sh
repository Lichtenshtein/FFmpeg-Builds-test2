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
export QUEST_MARK='❓'
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
export SYNC_MARK="${GREEN}♻${NC}"
export TARGET_MARK='🎯'
export DOWN_MARK="${GREEN}🡇${NC}"
export LOGS_MARK="${LOG_DEBUG}🗎${NC}"

# Функции для логирования пишут в stderr (>&2)
log_info()  { echo -e "${LOG_INFO}[INFO]${LOG_NC}  $*" >&2; }
log_warn()  { echo -e "${LOG_WARN}[WARN]${LOG_NC}  ${XCLAM_MARK} $*" >&2; }
log_error() { echo -e "${LOG_ERROR}[ERROR]${LOG_NC} ${CROSS_MARK} $*" >&2; }
log_debug() { echo -e "${LOG_DEBUG}[DEBUG]${LOG_NC} $*" >&2; }

# Safe color codes through %b, raw value through %s
print_info()  { printf '%b[INFO]%b  %b\n' "${LOG_INFO}" "${LOG_NC}" "$*" >&2; }
print_warn()  { printf '%b[WARN]%b %b\n' "${LOG_WARN}" "${LOG_NC}"  "${XCLAM_MARK}" "$*" >&2; }
print_error() { printf '%b[ERROR]%b %b\n' "${LOG_ERROR}" "${LOG_NC}"  "${CROSS_MARK}" "$*" >&2; }
print_debug() { printf '%b[DEBUG]%b %b\n' "${LOG_DEBUG}" "${LOG_NC}" "$*" >&2; }

# Use instead of log_debug/print_debug when the value may contain
# Windows paths or other backslash sequences
# We should change to use "$@" with a loop if multiple values are expected, or document that it takes exactly two args.
log_raw() {
    local label="$1"; shift
    printf '%b[DEBUG]%b %s\n' "${LOG_DEBUG:-}" "${LOG_NC:-}" "${label}" >&2
    [[ $# -gt 0 ]] && printf ' %s\n' "$@" >&2
    # local arg
    # for arg in "$@"; do
        # printf ' %s\n' "$arg" >&2
    # done
}

log_info_line() { echo -e "${LOG_INFO}[INFO]${LOG_NC}  ################################################################" >&2; }
log_err_line()  { echo -e "${LOG_ERROR}[ERROR]${LOG_NC} !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2; }

export -f log_info log_warn log_error log_debug log_info_line log_err_line print_info print_warn print_error print_debug log_raw

# ---------------------------------------------------------------------------
# ROOT_DIR: always the project root, regardless of where vars.sh lives or
# how it is sourced.
#
# Resolution order:
#   1. Already set in environment (Docker sets it via ENV ROOT_DIR=/builder)
#   2. /builder exists → we are inside the container
#   3. Derive from BASH_SOURCE: util/vars.sh → go one level up
#                               vars.sh at root → stay here
# ---------------------------------------------------------------------------
if [[ -z "${ROOT_DIR:-}" ]]; then
    if [[ -d "/builder" ]]; then
        ROOT_DIR="/builder"
    else
        _VARS_SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
        if [[ "$(basename "$_VARS_SELF")" == "util" ]]; then
            ROOT_DIR="$(dirname "$_VARS_SELF")"
        else
            ROOT_DIR="$_VARS_SELF"
        fi
        unset _VARS_SELF
    fi
fi
export ROOT_DIR
# Or if we don't like long paths in logs
# Container root is always /builder
export CONTAINER_ROOT="/builder"

# ---------------------------------------------------------------------------
# CACHE_DIR: always inside the project tree so host and container agree.
# The workflow mounts .cache/downloads → $CACHE_DIR, so the target must
# match what generate.sh writes into the Dockerfile --mount target.
# ---------------------------------------------------------------------------
export CACHE_DIR="${ROOT_DIR}/.cache/downloads"

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
export FFBUILD_DESTPREFIX="${FFBUILD_DESTDIR}${FFBUILD_PREFIX}"
# directory for saving .pc files from components
export PC_DIR="${FFBUILD_DESTPREFIX}/lib/pkgconfig"
# directory for storing .vars files with
# component variables and flags collected between stages
export VARS_DIR="${FFBUILD_PREFIX}/config_parts"

# Shared project folders
export ADDINS_DIR="${ROOT_DIR}/addins"
export CCACHE_DIR="/root/.cache/ccache"
export PATCHES_DIR="${ROOT_DIR}/patches"
export SCRIPTS_DIR="${ROOT_DIR}/scripts.d"
export TMP_DIR="${ROOT_DIR}/.cache/tmp"
export UTIL_DIR="${ROOT_DIR}/util"
export VARIANTS_DIR="${ROOT_DIR}/variants"

# ffmpeg paths
export FFMPEG_DIR="${ROOT_DIR}/.cache/ffmpeg"
export FFMPEG_BUILD_ROOT="${ROOT_DIR}/ffbuild"
export FFMPEG_SOURCE_DIR="${FFMPEG_BUILD_ROOT}/ffmpeg"
export FFMPEG_PKG_ROOT="${FFMPEG_BUILD_ROOT}/pkgroot"
export FFMPEG_CONFIG_LOG="${FFMPEG_SOURCE_DIR}/ffbuild/config.log"
export FFMPEG_HASH_FILE="${FFMPEG_DIR}/.current_commit" # хеш последнего скачанного коммита

# Create the base structure if it doesn't exist
if [[ -d "/builder" ]]; then
    mkdir -p "$VARS_DIR" "$FFBUILD_DESTDIR" "$FFBUILD_DESTPREFIX"/{include,bin,lib/pkgconfig}
fi
mkdir -p "$CACHE_DIR" "$TMP_DIR" "$FFMPEG_BUILD_ROOT" "$FFMPEG_DIR"

# Flags for the component build stage

[[ "$USE_OPENMP" == "1" ]] && OPENMP_C=" -fopenmp" && OPENMP_LIB="-lgomp "

BASE_CFLAGS="-mms-bitfields -fstack-protector-strong${OPENMP_C}"
BASE_CPPFLAGS="-D__USE_MINGW_ANSI_STDIO=1 -U_WIN32_WINNT -D_WIN32_WINNT=0x0A00 -D_WIN32 -D_FORTIFY_SOURCE=2"
SYSTEM_LIBS="${OPENMP_LIB}-lsetupapi -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lws2_32 -lbcrypt -pthread"
ADDITIONAL_LIBS="-lusp10 -lmsimg32 -lcfgmgr32 -lruntimeobject -ldwrite -ld2d1 -lwindowscodecs -lopengl32 -lssp -lgdi32 -lrpcrt4 -luserenv -liphlpapi -lwinmm -luuid -ldnsapi -lcrypt32 -lwldap32 -lnormaliz"

# disable -fPIC, -ffast-math, if troubles occur
export CFLAGS="-march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe ${BASE_CFLAGS} -std=gnu11"
export CPPFLAGS="-I/opt/ffbuild/include ${BASE_CPPFLAGS}"
export CXXFLAGS="-march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe ${BASE_CFLAGS} -std=gnu++17"
export LDFLAGS="-Wl,-Bstatic -static -static-libgcc -static-libstdc++ -L/opt/ffbuild/lib -pipe -Wl,--high-entropy-va -Wl,--nxcompat -Wl,--dynamicbase -Wl,--reduce-memory-overheads -Wl,--stack,16777216"
export LIBS="${LIBS:-$SYSTEM_LIBS}"
export RUSTFLAGS="-C target-feature=+crt-static -C target-cpu=${CPU_ARCH}"
# Обработка флагов, специфичных для Linux ELF
if [[ "$TARGET" == *"win"* ]]; then
    # бесполезно при сборке под Windows и ломает OpenSSL asm вместе с std=c11
    export CFLAGS="${CFLAGS//-fno-semantic-interposition/}"
    export CXXFLAGS="${CXXFLAGS//-fno-semantic-interposition/}"
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
    if [[ ! -f "${VARIANTS_DIR}/${TARGET}-${VARIANT}.sh" ]]; then
        log_error "Invalid target/variant: ${TARGET}-${VARIANT} (looked in ${VARIANTS_DIR})"
        return 1 2>/dev/null || exit 1
    fi
fi

export LICENSE_FILE="COPYING.LGPLv2.1"

ADDINS=()
ADDINS_STR=""
while [[ "$#" -gt 0 ]]; do
    # Проверяем, существует ли файл в addins
    if [[ -f "${ADDINS_DIR}/${1}.sh" ]]; then
        ADDINS+=("$1")
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
    grep -v '^[[:space:]]*#' "$STAGE_PATH" \
        | sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' \
        | grep -v '^[[:space:]]*$' \
        | tr -d '\r' \
        | sha256sum | cut -c1-16
}
export -f get_stage_hash

# ---------------------------------------------------------------------------
# Stage-specific variables.
# These are intentionally NOT set here at source time because $STAGE and
# $STAGE_HASH are unknown until a specific stage is being processed.
# Each consumer (dl_functions.sh, run_stage.sh, clean_cache.sh, generate.sh)
# must derive them locally after setting $STAGE.
#
# Helper function — call after we have set $STAGE:
#   eval "$(stage_vars "$STAGE")"
# ---------------------------------------------------------------------------
stage_vars() {
    local stage_path="$1"
    local _hash
    _hash=$(get_stage_hash "$stage_path")
    local _name
    _name="$(basename "$stage_path" .sh)"
    local _component="${_name#*-}"
    printf 'STAGE_HASH=%q\n'       "$_hash"
    printf 'STAGENAME=%q\n'        "$_name"
    printf 'COMPONENT_NAME=%q\n'   "$_component"
    printf 'STAGE_CACHE_FILE=%q\n' "${CACHE_DIR}/${_name}_${_hash}.tar.zst"
    printf 'STAGE_LATEST_LINK=%q\n' "${CACHE_DIR}/${_name}.tar.zst"
}
export -f stage_vars

# Удаляем ANSI цвета
# Удаляем переносы строк (заменяем на пробел)
# xargs схлопнет лишние пробелы в одну строку
clean_val() {
    echo "$*" | \
        sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" | \
        sed -E "s/''|\"\"//g" | \
        tr -s '[:space:]' ' ' | \
        xargs -r echo
}

# быстрые дедупликаторы
dedupe_logic() {
    local input="$1"
    local mode="$2"
    # Split on whitespace, filter garbage words and empty lines
    local clean=$(echo "$input" | tr ' ' '\n' | \
        grep -vE "^(Package .* not found|No package .* found)$|^$")
    if [[ "$mode" == "last" ]]; then
        # Keep LAST occurrence (important for linker order)
        echo "$clean" | tac | awk '!x[$0]++' | tac
    else
        # Keep FIRST occurrence (default for most flags)
        echo "$clean" | awk '!x[$0]++'
    fi
}

smart_dedupe() {
    local input
    input=$(clean_val "$*")
    [[ -z "$input" ]] && return
    if [[ "$DEDUPE_FLAGS" == "1" ]]; then
        dedupe_logic "$input" "first" | tr '\n' ' ' | xargs -r
    else
        echo "$input" | tr '\n' ' ' | xargs -r
    fi
}

smart_libs_dedupe() {
    local input=$(clean_val "$*")
    [[ -z "$input" ]] && return
    # Специфичная чистка для библиотек
    # унифицируем pthread: заменяем -lpthread на -pthread
    # чистим мусор и ПУТИ, убираем -lstdc++
    local filtered=$(echo "$input" | tr ' ' '\n' | \
        grep -vE "^-L|^-lstdc\+\+$" | \
        sed 's/^-lpthread$/-pthread/')
    # склеиваем в одну строку без удаления дублей?
    if [[ "$DEDUPE_FLAGS" == "1" ]]; then
        dedupe_logic "$filtered" "last" | tr '\n' ' ' | xargs -r
    else
        echo "$filtered" | tr '\n' ' ' | xargs -r
    fi
}
export -f clean_val dedupe_logic smart_dedupe smart_libs_dedupe

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

# These are DEFAULT implementations component scripts override them.
# Each prints its contribution to stdout. run_stage.sh owns accumulation.
# собирают флаги от всех скриптов в scripts.d для финального ./configure
ffbuild_enabled()      { return 0; }
ffbuild_depends()      { echo "base"; }
ffbuild_configure()    { return 0; }
ffbuild_cflags()       { return 0; }
ffbuild_cppflags()     { return 0; }
ffbuild_cxxflags()     { return 0; }
ffbuild_ldflags()      { return 0; }
ffbuild_ldexeflags()   { return 0; }
ffbuild_libs()         { return 0; }
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

    # Helper: deduplicate space-separated tokens, normalize -pthread/-lpthread
    # Faster than awk, handles edge cases better
    dedup_flags_fast() {
        local tokens="$1"
        local skip_tokens="$2"
        # Build skip map as a string for grep matching
        local skip_pattern=$(echo "$skip_tokens" | sed 's/ /|/g; s/-pthread/-lpthread/g; s/-lpthread/-pthread/g')
        # Deduplicate: print each token once, skip unwanted ones
        echo "$tokens" | tr ' ' '\n' | awk -v skip="$skip_pattern" '
            NF {
                token = ($0 == "-lpthread") ? "-pthread" : $0
                if (skip && match(skip, "(" token "|" token ")")) next
                if (!seen[token]++) print token
            }
        ' | tr '\n' ' ' | xargs -r
    }

    # Helper: validate and normalize a single include path
    normalize_include_path() {
        local path="$1"
        # Already a variable reference — keep it
        [[ "$path" == *'${'* ]] && echo "$path" && return
        # Absolute path to our prefix — replace with variable
        if [[ "$path" == "$FFBUILD_PREFIX"* ]]; then
            echo "\${prefix}${path#$FFBUILD_PREFIX}"
            return
        fi
        # Bare /include or /usr/include — replace with ${includedir}
        if [[ "$path" == "/include" || "$path" == "/usr/include" ]]; then
            echo "\${includedir}"
            return
        fi
        # Relative path like ../include — resolve and check
        if [[ "$path" == ../* ]]; then
            local resolved
            resolved=$(cd "$(dirname "$pc_dir")" && cd "${path%/*}" && pwd)
            if [[ "$resolved" == "$FFBUILD_PREFIX"* ]]; then
                echo "\${prefix}${resolved#$FFBUILD_PREFIX}"
                return
            fi
        fi
        # Unrecognized — log warning and drop
        log_warn "Dropping unrecognized include path: $path"
        return 1
    }

    # helper escape string for use as a literal sed pattern
    sed_escape() { printf '%s' "$1" | sed 's/[[\.*^$()+?{|]/\\&/g'; }

    log_debug "Correcting values in .pc files:"
    # замена абсолютных путей на переменные
    find "$pc_dir" -maxdepth 1 -name "*.pc" | while read -r pc; do
        [[ -f "$pc" ]] || continue
        printf '%s\n' "$pc"
        log_debug "Processing: $(basename "$pc")"

        # Пересоздание переменных путей
        sed -i $sl '/^prefix=/d; /^exec_prefix=/d; /^libdir=/d; /^includedir=/d; /^bindir=/d; /^libdir64=/d' "$pc"
        sed -i $sl "1i prefix=$FFBUILD_PREFIX\nexec_prefix=\${prefix}\nlibdir=\${prefix}/lib\nincludedir=\${prefix}/include\nbindir=\${prefix}/bin" "$pc"

        # Replace absolute paths with variables (only in non-assignment lines)
        sed -i $sl '/=/! s|'"$FFBUILD_PREFIX"'/include|\${includedir}|g' "$pc"
        sed -i $sl '/=/! s|'"$FFBUILD_PREFIX"'/lib|\${libdir}|g'         "$pc"
        sed -i $sl '/=/! s|'"$FFBUILD_PREFIX"'|\${prefix}|g'             "$pc"

        # NORMALIZE INCLUDE PATHS (in Cflags and Cflags.private)
        # Extract all -I flags, normalize each, deduplicate
        local cflags_line=$(grep "^Cflags:" "$pc" | cut -d':' -f2-)
        if [[ -n "$cflags_line" ]]; then
            local normalized_cflags=""
            local seen_paths=""
            # Extract each -I flag and normalize it
            echo "$cflags_line" | grep -oE '\-I[^ ]+' | while read -r iflag; do
                local path="${iflag#-I}"
                local normalized=$(normalize_include_path "$path") || continue
                # Deduplicate paths
                if ! echo "$seen_paths" | grep -qF "$normalized"; then
                    normalized_cflags="$normalized_cflags -I$normalized"
                    seen_paths="$seen_paths $normalized"
                fi
            done
            # Rebuild Cflags with normalized paths + other flags (defines, etc.)
            local other_flags=$(echo "$cflags_line" | sed 's/-I[^ ]*//g' | xargs -r)
            sed -i "s|^Cflags:.*|Cflags: $normalized_cflags $other_flags|" "$pc"
        fi

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
        local cflags_priv=$(grep "^Cflags.private:" "$pc" | cut -d':' -f2- | xargs)
        if [[ -n "$cflags_priv" ]]; then
            sed -i $sl "/^Cflags:/ s/$/ $cflags_priv/" "$pc"
            sed -i $sl '/^Cflags.private:/d' "$pc"
        fi

        # Обработка Libs (Улучшенный захват для мульти-библиотечных пакетов)
        local libs_line=$(grep "^Libs:" "$pc" | cut -d':' -f2- | xargs)
        # Ищем путь -L
        local lib_path=$(echo "$libs_line" | grep -oE '\-L[^ ]+' | head -n1)
        [[ -z "$lib_path" ]] && lib_path='-L${libdir}'
        
        # базовое имя (например 'lcms2' из 'lcms2.pc'). strip leading 'lib' prefix
        local base_name=$(basename "$pc" .pc); base_name="${base_name#lib}"

        # Collect all -l flags whose name starts with base_name
        # Use grep with word-boundary-like pattern; escape dots in base_name

        # we rely on the fact that main_libs is the “face” of the library, and everything else goes private
        # local main_libs=$(echo "$libs_line" | grep -oE "\-l${base_name}[a-zA-Z0-9_-]*" | xargs)

        local escaped_base=$(sed_escape "$base_name")
        local main_libs=$(echo "$libs_line" | grep -oE "\-l${escaped_base}[a-zA-Z0-9_-]*" | xargs)
        # Fallback: just take the first -l flag
        [[ -z "$main_libs" ]] && main_libs=$(echo "$libs_line" | grep -oE '\-l[a-zA-Z0-9_.+-]+' | head -n1)

        # Compute leftover flags (→ Libs.private) strip lib_path and each main_lib token using awk (avoids regex metachar issues)
        local leftovers=$(echo "$libs_line" | awk -v lp="$lib_path" -v ml="$main_libs" '{
            n = split(ml, m)
            for (i=1; i<=NF; i++) {
                if ($i == lp) continue
                skip=0; for (j=1; j<=n; j++) if ($i == m[j]) { skip=1; break }
                if (!skip) printf "%s ", $i } }')

        # Write clean public Libs line
        sed -i $sl "s|^Libs:.*|Libs: $lib_path $main_libs|" "$pc"

        # Ensure Requires.private and Libs.private fields exist
        grep -q "^Requires.private:" "$pc" || sed -i $sl "/^Version:/a Requires.private:" "$pc"
        grep -q "^Libs.private:" "$pc" || sed -i $sl "/^Libs:/a Libs.private:" "$pc"

        # Append discovered deps (raw, dedup happens)
        sed -i $sl "/^Requires.private:/ s|$| $extra_requires|" "$pc"
        sed -i $sl "/^Libs.private:/ s|$| $leftovers $extra_libs $LIBS|" "$pc"

        # Capitalisation fixes
        sed -i $sl 's/-lWs2_32/-lws2_32/g; s/-lWinmm/-lwinmm/g; s/-lpthread/-pthread/g' "$pc"
        # Remove -lrt (Linux-only, not on Windows)
        sed -i $sl 's/ -lrt\b//g' "$pc"
        # Apply -lzlib → -lz (after all -l tokens are in the file)
        sed -i $sl 's/-lzlib\b/-lz/g' "$pc"

        # Smart deduplication
        # Cflags: simple dedup + -pthread alias
        local cflags_line=$(grep "^Cflags:" "$pc" | cut -d':' -f2- | xargs)
        if [[ -n "$cflags_line" ]]; then
            local clean_cflags=$(dedup_flags_fast "$cflags_line")
            sed -i $sl "s|^Cflags:.*|Cflags: $clean_cflags|" "$pc"
        fi

        # Requires.private: remove anything already in Requires
        local pub_req=$(grep "^Requires:" "$pc" | grep -v "^Requires.private:" | cut -d':' -f2- | tr ',' ' ' | xargs)
        local rp_line=$(grep "^Requires.private:" "$pc" | cut -d':' -f2- | tr ',' ' ' | xargs)
        if [[ -n "$rp_line" ]]; then
            local clean_rp=$(dedup_flags_fast "$rp_line" "$pub_req")
            sed -i $sl "s|^Requires.private:.*|Requires.private: $clean_rp|" "$pc"
        fi

        # Libs.private: remove anything already covered by Libs or any Requires
        local all_req=$(grep -E "^Requires(\.private)?:" "$pc" | cut -d':' -f2- | tr ',' ' ' | xargs)
        local pub_libs=$(grep "^Libs:" "$pc" | cut -d':' -f2- | xargs)
        local lp_line=$(grep "^Libs.private:" "$pc" | cut -d':' -f2- | xargs)
        if [[ -n "$lp_line" ]]; then
            local skip_for_lp=$(echo "$all_req $pub_libs" | awk '{
                for(i=1;i<=NF;i++){
                    print $i
                    if ($i !~ /^-/) print "-l" $i } }' | xargs)
            local clean_lp=$(dedup_flags_fast "$lp_line" "$skip_for_lp")
            sed -i $sl "s|^Libs.private:.*|Libs.private: $clean_lp|" "$pc"
        fi

        # Remove fields that ended up empty
        sed -i $sl '/^Requires\.private:[[:space:]]*$/d' "$pc"
        sed -i $sl '/^Libs\.private:[[:space:]]*$/d'     "$pc"
        # Collapse multiple spaces, strip trailing whitespace
        sed -i $sl 's/  \+/ /g; s/[[:space:]]*$//' "$pc"

        log_debug "${CHECK_MARK} $(basename "$pc") finished."
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
    local pc_dir="${lib_dir}/pkgconfig"
    local toolchain="${FFBUILD_TOOLCHAIN:-x86_64-w64-mingw32}"
    # Used only for readelf/nm filtering of well-known system libs
    local sys_libs="libc\.so|libm\.so|libdl\.so|librt\.so|libpthread\.so|libgcc_s\.so|libstdc\+\+\.so|ld-linux|libresolv\.so|libutil\.so"

    # Создаем временный файл для сбора вывода
    local tmp_out=$(mktemp)

    # Считаем общий вес установленных файлов компонента
    local total_size="0"
    if [[ -d "$FFBUILD_DESTPREFIX" ]]; then
        total_size=$(du -sh "$FFBUILD_DESTPREFIX" | awk '{print $1}')
    fi

    # Поиск pkg-config зависимостей
    if [[ -d "$pc_dir" ]]; then
        find "$pc_dir" -name "*.pc" -exec bash -c '
            pc_file="$1"; pkg_config_cmd="$2"; pc_dir="$3"; prefix="$4"
            log_err="$5"; log_nc="$6"; x_mark="$7"; s_mark="$8"

            export PKG_CONFIG_LIBDIR="$pc_dir:$prefix/lib/pkgconfig:$prefix/share/pkgconfig"
            export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
            export PKG_CONFIG_SYSROOT_DIR="/"

            pkg_name=$(basename "$pc_file" .pc)

            printf "\n%b \033[1;36mFILE:\033[0m %s\n" "$x_mark" "$pc_file"

            # Выводим содержимое (опционально, для отладки)
            cat "$pc_file"
            
            printf "\n%b \033[1;35mDEPENDENCIES\033[0m for %s:\n" "$s_mark" "$pkg_name"

            deps=$($pkg_config_cmd --print-requires --print-requires-private "$pkg_name" 2>/dev/null | sort -u | xargs)

            if [[ -n "$deps" ]]; then
                for dep in $deps; do
                    if $pkg_config_cmd --exists "$dep" 2>/dev/null; then
                        ver=$($pkg_config_cmd --modversion "$dep" 2>/dev/null || echo "unknown")
                        printf "  \033[1;32m•\033[0m %-20s \033[1;30m(found: %s)\033[0m\n" "$dep" "$ver"
                    else
                        printf "  \033[1;31m✖ MISSING:\033[0m %s %b(in: %s)%b\n" "$dep" "$log_err" "$pc_dir" "$log_nc"
                        echo "MISSING_DEP: $dep"
                    fi
                done
            else
                echo "  \033[1;30m(No dependencies found in .pc file)\033[0m"
            fi
        ' _ {} \
            "${PKG_CONFIG:-pkg-config}" \
            "$pc_dir" \
            "$FFBUILD_PREFIX" \
            "$LOG_ERROR" \
            "$LOG_NC" \
            "$XCLAM_MARK" \
            "$SEARCH_MARK" \; >> "$tmp_out" || true
    fi
    # readelf: dynamic dependencies 
    find "$lib_dir" "$bin_dir" -type f \
        \( -name "*.so*" -o -name "*.exe" -o -name "*.dll" \) \
        -print0 2>/dev/null | \
    xargs -0 -r -I{} bash -c '
        file="$1"
        tc="$2"
        sys_libs_regex="$3"
        xclam_mark="$4"

        if "${tc}-readelf" -h "$file" &>/dev/null; then
            raw_deps=$("${tc}-readelf" -d "$file" 2>/dev/null | \
                awk "/\(NEEDED\)/ { match(\$0, /\[([^\]]+)\]/, a); print a }")
            clean_deps=$(echo "$raw_deps" | grep -Ev "$sys_libs_regex" || true)
            if [[ -n "$clean_deps" ]]; then
                printf "\n%b NEEDED LIBRARIES for %s:\n%s\n" \
                    "$xclam_mark" "$file" "$clean_deps"
            fi
        fi
    ' _ {} "$toolchain" "$sys_libs" "$XCLAM_MARK" >> "$tmp_out" || true
    # nm: undefined external symbols in static libs 
    find "$lib_dir" -name "*.a" -print0 2>/dev/null | \
    xargs -0 -r -I{} bash -c '
        file="$1"; tc="$2"; x_mark="$3"
        raw_symbols=$("${tc}-nm" -uA "$file" 2>/dev/null || true)
        if [[ -n "$raw_symbols" ]]; then
            clean_symbols=$(echo "$raw_symbols" | \
                grep -Ev "(__imp_|__mingw_|_Unwind_|__gcc_|___chkstk|__stack_chk|__main)" | \
                awk -F: "{ 
                    split(\$NF, a, \" \"); 
                    sym = a[2]; 
                    if (sym != \"\") printf \"%-15s \033[1;30m→\033[0m %s\n\", \$2, sym 
                }" | sort -u | head -n 12)
            if [[ -n "$clean_symbols" ]]; then
                printf "\n%b \033[1;33mEXTERNAL SYMBOLS (OBJ \033[1;30m→\033[1;33m SYM)\033[0m in %s:\n" \
                    "$x_mark" "$file"
                echo "$clean_symbols" | sed "s/^/  \033[1;32m•\033[0m /"
            fi
        fi
    ' _ {} "$toolchain" "$XCLAM_MARK" >> "$tmp_out" || true
    # Проверка RPATH / RUNPATH 
    if [[ -n "$toolchain" ]] && command -v "${toolchain}-objdump" &>/dev/null; then
        find "$lib_dir" "$bin_dir" -type f \( -name "*.so*" -o -executable \) -print0 2>/dev/null | \
        xargs -0 -r -I{} bash -c '
            file="$1"; tc="$2"; x_mark="$3"
            if "${tc}-readelf" -h "$file" &>/dev/null; then
                rpath=$("${tc}-objdump" -p "$file" 2>/dev/null | awk "/RPATH|RUNPATH/ {print \$0}")
                if [[ -n "$rpath" ]]; then
                    printf "\n%b RPATH/RUNPATH for %s:\n%s\n" "$x_mark" "$file" "$rpath"
                fi
            fi
        ' _ {} "$toolchain" "$XCLAM_MARK" >> "$tmp_out" || true
    fi

    # Output
    local error_count
    error_count=$(grep -c "MISSING_DEP:" "$tmp_out" 2>/dev/null || echo 0)
    error_count=$(( ${error_count:-0} ))

    if [[ -s "$tmp_out" ]]; then
        log_debug "Showing dependencies for ${name} [Install size: ${total_size}]:"
        cat "$tmp_out" >&2
        if [ "$error_count" -gt 0 ]; then
            log_error "Found ${error_count} missing pkg-config dependency/dependencies for ${name}!"
        else
            log_info "${CHECK_MARK} All pkg-config dependencies satisfied for ${name}."
        fi
    else
        log_info "${CHECK_MARK} No dependencies found for ${name} (meta/header-only). [Install size: ${total_size}]."
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
        [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && log_raw "${DIRS_MARK} WINEPATH (Windows style):" "$WINEPATH"
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

conf_finder() {
    if [[ ! -f "configure" && ( -f "configure.ac" || -f "configure.in" ) ]]; then
        log_info "${SYNC_MARK} No 'configure' script found, but 'configure.ac' exists."
        if [[ -f "autogen.sh" ]]; then
            log_info "Running ./autogen.sh..."
            chmod +x autogen.sh
            ./autogen.sh || { log_error "autogen.sh failed"; exit 1; }
        elif [[ -f "bootstrap" ]]; then
            log_info "Running ./bootstrap..."
            chmod +x bootstrap
            ./bootstrap || { log_error "bootstrap failed"; exit 1; }
        else
            log_info "Running autoreconf -fi..."
            autoreconf -fi || { log_error "autoreconf failed"; exit 1; }
        fi
    fi
}
export -f conf_finder

# экспорт важных переменных MinGW, чтобы они пробрасывались в download.sh и run_stage.sh:
export TARGET VARIANT REPO REGISTRY BASE_IMAGE TARGET_IMAGE IMAGE

# ---------------------------------------------------------------------------
# Terminal width — used for separators; falls back to 72 if tput unavailable
# ---------------------------------------------------------------------------

_term_width() { tput cols 2>/dev/null || echo 92; }

_repeat_char() {
    local len=$1 char=$2
    [[ $len -le 0 ]] && return
    printf "%${len}s" "" | sed "s/ /$char/g"
}

# separator [char] [label]
separator() {
    local char="${1:-─}"
    local label="${2:-}"
    local width
    width=$(_term_width)

    if [[ -z "$label" ]]; then
        _repeat_char "$width" "$char" >&2
        printf '\n' >&2
    else
        local label_len=${#label}
        local left_side=$(( (width - label_len) / 2 ))
        local right_side=$(( width - label_len - left_side ))
        [[ $left_side -lt 0 ]] && left_side=0
        [[ $right_side -lt 0 ]] && right_side=0
        printf '%s%s%s\n' \
            "$(_repeat_char "$left_side" "$char")" \
            "$label" \
            "$(_repeat_char "$right_side" "$char")" >&2
    fi
}
export -f separator _term_width _repeat_char

# phase_header <EMOJI> <TITLE>
phase_header() {
    local emoji="$1"; shift
    local width=$(_term_width)
    local line=$(_repeat_char $((width - 2)) "─")
    
    printf '╭%s╮\n' "$line" >&2
    printf '  %b%s %s%b  \n' "${LOG_INFO}" "$emoji" "$*" "${LOG_NC}" >&2
    printf '╰%s╯\n' "$line" >&2
}
export -f phase_header

# phase_footer <message>
phase_footer() {
    local width=$(_term_width)
    local line=$(_repeat_char $((width - 2)) "─")
    printf '╭%s╮\n' "$line" >&2
    printf '  %b%s%b  \n' "${LOG_INFO}" "$*" "${LOG_NC}" >&2
    printf '╰%s╯\n' "$line" >&2
}
export -f phase_footer

dl_result_line() {
    local status="$1" name="$2" hash="$3" extra="$4"
    local icon
    case "$status" in
        hit)  icon="✔" ; color="$LOG_INFO"  ;;
        miss) icon="🡇" ; color="$LOG_WARN"  ;;
        skip) icon="—" ; color="$LOG_DEBUG" ;;
        fail) icon="✖" ; color="$LOG_ERROR" ;;
        *)    icon="?" ; color="$LOG_NC"    ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$status" "$icon" "$name" "${hash:0:16}" "$extra" \
        >> "${DL_RESULT_FILE:-/dev/null}"
}
export -f dl_result_line

get_component_group() {
    local stagename="$1"
    local prefix="${stagename%%-*}"
    case "$prefix" in
        01|02|03)               echo "Toolchain" ;;
        04|05|06|07|09)         echo "System Integration" ;; # ICU, Gettext, Iconv
        08|11|12|35)            echo "Compression & Runtime" ;; # Zlib, Zstd, FFI
        15|16|18|19)            echo "Base Integration" ;; # Glib, XML2
        20|21|22|23|24)         echo "Hardware Integration" ;; # cdio
        25|26|27|28|29)         echo "Net" ;; # OpenSSL, Curl
 14|17|30|31|32|33|34|36|38|39) echo "Core Graphics" ;; # PNG Cairo
        40|41|42|43|44)         echo "Vulkan & Shaders" ;; # SPIR-V, Glslang
        45|46)                  echo "Hardware Acceleration API" ;; # VMAF
        51|52|53|54|55|56)      echo "X11 & Windowing" ;; # XCB
        57|59|60)            echo "Compute & Vision" ;; # OpenVINO, OpenCV
        61|62|63|64)            echo "Audio & Codecs" ;; #
        37|58|70|71|72|73|74)      echo "Software Codecs" ;; # x264, x265
        80|81|82|83|84)         echo "Frameservers" ;; # Vapoursynth, OpenAL
        50|84|85|86|87|88|89)   echo "Video Extensions" ;; # Libglvnd, Xrandr
        96|97|98)               echo "LV2 & Plugins" ;; # Serd, Sord, Lilv
        99|zz)                  echo "Meta & Finalize" ;;
        *)                      echo "Other" ;;
    esac
}
export -f get_component_group

render_dl_table() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local width=$(_term_width)
    local inner_width=$(( width - 8 )) # 4; Немного уменьшим для отступов

    separator "─" "  DOWNLOAD SUMMARY  "
    printf '  %-3s  %-30s  %-16s  %s\n' "" "COMPONENT" "HASH" "RESULT" >&2
    separator "─"

    local current_group=""
    while IFS=$'\t' read -r status icon name hash extra; do
        local group=$(get_component_group "$name")

        if [[ "$group" != "$current_group" ]]; then
            # Purple Group
            if [[ -n "$current_group" ]]; then
                printf '  %b╰%s%b\n' "${LOG_DEBUG}" "$(_repeat_char "$inner_width" "-")" "${LOG_NC}" >&2
            fi
            # Заголовок группы: Purple ┌─ Group
            local group_label="─[ $group ]"
            local remain=$(( inner_width - ${#group_label} ))
            printf '  %b╭%s%s%b\n' "${LOG_DEBUG}" "$group_label" "$(_repeat_char "$remain" "-")" "${LOG_NC}" >&2
            current_group="$group"
        fi

        local color
        case "$status" in
            hit)  color="${LOG_INFO}"  ;;
            miss) color="${LOG_WARN}"  ;;
            skip) color="${LOG_DEBUG}" ;;
            fail) color="${LOG_ERROR}" ;;
            *)    color="${LOG_NC}"    ;;
        esac

        # Строгое разделение цвета и вывода
        # printf '  │ ' >&2
        printf '  %b│%b ' "${LOG_DEBUG}" "${LOG_NC}" >&2
        printf '%b' "$color" >&2
        printf '%s  %-28s  %-16s  %s' "$icon" "$name" "$hash" "$extra" >&2
        printf '%b\n' "$LOG_NC" >&2
        # printf '%b%-2s  %-28s  %-16s  %s%b\n' "$color" "$icon" "$name" "$hash" "$extra" "$LOG_NC" >&2

    # This sorts by status (hit/miss/skip/fail)
    # sort -t$'\t' -k1,1 "$file"
    # sort by name (field 3)
    # sort -t$'\t' -k3,3 "$file"
    done < <(sort -t$'\t' -k3,3 "$file")

    # Закрываем последнюю группу (Purple)
    if [[ -n "$current_group" ]]; then
        printf '  %b╰%s%b\n' "${LOG_DEBUG}" "$(_repeat_char "$inner_width" "-")" "${LOG_NC}" >&2
    fi

    separator "─"

    # Подсчет
    local n_hit=$(tr -d '\r' < "$file" | grep -c '^hit' || true)
    local n_miss=$(tr -d '\r' < "$file" | grep -c '^miss' || true)
    local n_skip=$(tr -d '\r' < "$file" | grep -c '^skip' || true)
    local n_fail=$(tr -d '\r' < "$file" | grep -c '^fail' || true)

    # Вывод финальной строки: иконки и цифры цветные, текст белый
    printf '  %b✔ %s%b hit   %b🡇 %s%b downloaded   %b— %s%b skipped   %b✖ %s%b failed\n' \
        "${LOG_INFO}"  "${n_hit:-0}"  "${LOG_NC}" \
        "${LOG_WARN}"  "${n_miss:-0}" "${LOG_NC}" \
        "${LOG_DEBUG}" "${n_skip:-0}" "${LOG_NC}" \
        "${LOG_ERROR}" "${n_fail:-0}" "${LOG_NC}" >&2
}
export -f render_dl_table
