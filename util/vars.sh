#!/bin/bash

set -o pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# ANSI Color Codes
export LOG_DEBUG='\x1b[1;35m'   # Purple (Bold)
export LOG_INFO='\x1b[1;32m'    # Green (Bold)
export LOG_WARN='\x1b[1;33m'    # Yellow (Bold)
export LOG_ERROR='\x1b[1;31m'   # Red (Bold)
export CYAN_B='\x1b[1;36m'      # Cyan (Bold)
export GREY_B='\x1b[1;30m'      # Grey (Bold)
export BLUE_B='\x1b[1;34m'      # Blue (Bold)
export NC='\x1b[0m'             # No Color (Reset)
export RED='\x1b[0;31m'         # Red
export GREEN='\x1b[0;32m'       # Green
export YELLOW='\x1b[0;33m'      # Yellow
export BLUE='\x1b[0;34m'        # Blue
export PURPLE='\x1b[0;35m'      # Purple
export CYAN='\x1b[0;36m'        # Cyan

# Marks
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
export BUILD_MARK='🔧️'
export DIRS_MARK='📂'
export LOCK_MARK='🔒'
export SYNC_MARK="${GREEN}♻${NC}"
export TARGET_MARK='🎯'
export DOWN_MARK="${GREEN}🡇${NC}"
export LOGS_MARK="${LOG_DEBUG}🗎${NC}"

# Функции для логирования пишут в stderr (>&2)
log_info()  { echo -e "${LOG_INFO}[INFO]${NC}  $*" >&2; }
log_warn()  { echo -e "${LOG_WARN}[WARN]${NC}  ${XCLAM_MARK} $*" >&2; }
log_error() { echo -e "${LOG_ERROR}[ERROR]${NC} ${CROSS_MARK} $*" >&2; }
log_debug() { echo -e "${LOG_DEBUG}[DEBUG]${NC} $*" >&2; }

# Safe color codes through %b, raw value through %s
print_info()  { printf '%b[INFO]%b  %b\n' "${LOG_INFO}" "${NC}" "$*" >&2; }
print_warn()  { printf '%b[WARN]%b %b\n' "${LOG_WARN}" "${NC}"  "${XCLAM_MARK}" "$*" >&2; }
print_error() { printf '%b[ERROR]%b %b\n' "${LOG_ERROR}" "${NC}"  "${CROSS_MARK}" "$*" >&2; }
print_debug() { printf '%b[DEBUG]%b %b\n' "${LOG_DEBUG}" "${NC}" "$*" >&2; }

# Use instead of log_debug/print_debug when the value may contain
# Windows paths or other backslash sequences
# We should change to use "$@" with a loop if multiple values are expected, or document that it takes exactly two args.
log_raw() {
    local label="$1"; shift
    printf '%b[DEBUG]%b %s\n' "${LOG_DEBUG:-}" "${NC:-}" "${label}" >&2
    [[ $# -gt 0 ]] && printf ' %s\n' "$@" >&2
    # local arg
    # for arg in "$@"; do
        # printf ' %s\n' "$arg" >&2
    # done
}

log_info_line() { echo -e "${LOG_INFO}[INFO]${NC}  ################################################################" >&2; }
log_err_line()  { echo -e "${LOG_ERROR}[ERROR]${NC} !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2; }

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
# use env vars with broadwell fallback
if [[ "$TARGET" == *"linux"* ]]; then
    export CPU_ARCH="${CPU_ARCH:-haswell}"
    export CPU_TUNE="${CPU_TUNE:-haswell}"
else
    export CPU_ARCH="${CPU_ARCH:-broadwell}"
    export CPU_TUNE="${CPU_TUNE:-broadwell}"
fi
# Build variables (inside the container)
# just duplicate from Dockerfile for convenience
export TOOLCHAIN_BIN="/opt/ct-ng/bin"
export FFBUILD_RUST_TARGET="x86_64-pc-windows-gnu"
export FFBUILD_TOOLCHAIN="x86_64-w64-mingw32"
export FFBUILD_CROSS_PREFIX="x86_64-w64-mingw32-"
export AS="${FFBUILD_TOOLCHAIN}-as"
export CC="ccache ${FFBUILD_TOOLCHAIN}-gcc"
export CXX="ccache ${FFBUILD_TOOLCHAIN}-g++"
export FFBUILD_PREFIX="/opt/ffbuild" # persistent installed compoents storage
export FFBUILD_DESTDIR="/opt/ffdest"
export FFBUILD_DESTPREFIX="${FFBUILD_DESTDIR}${FFBUILD_PREFIX}"
export INSTALL_ROOT="$FFBUILD_DESTPREFIX" # single less confusing source of truth
# directory for saving .pc files from components
export PC_DIR="${INSTALL_ROOT}/lib/pkgconfig"
# directory for storing .vars files with
# component variables and flags collected between stages
export VARS_DIR="${FFBUILD_PREFIX}/config_vars"
# pkg-config variables
export PKG_CONFIG="pkgconf"
export PKG_CONFIG_PATH="" # don't touch
export PKG_CONFIG_LIBDIR="${FFBUILD_PREFIX}/lib/pkgconfig:${FFBUILD_PREFIX}/share/pkgconfig:${FFBUILD_PREFIX}/lib64/pkgconfig"
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=0
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=0
export PKG_CONFIG_ALLOW_CROSS=1
# pkg-config libs collector options for final ffmpeg
# * --libs                                   — only -l and -L paths
# * --libs-only-l                            — only -l (-lSdl2) WITHOUT -L paths
# * --libs-only-other                        — only flags WITHOUT -l (-pthread)
# * --static --libs                          — -L/opt/lib -lfftw3
# * --static --libs-only-l                   — only -l from Libs + Libs.private
# * --static --libs-only-other               — any~ flags WITHOUT -L paths
# * --cflags                                 — any~ flags WITH -I paths
# * --cflags-only-other                      — only flags WITHOUT -I paths
# without --static the Libs.private field will be ignored
if [[ "$PREFER_SHARED" == "1" ]]; then
    export PKG_CONFIG_ALL_DYNAMIC=1
    export PKG_CONFIG_CFLAGS="--cflags-only-other"
    export PKG_CONFIG_LIBS="--libs"
else
    export PKG_CONFIG_ALL_STATIC=1
    export PKG_CONFIG_FLAGS="--static"
    export PKG_CONFIG_CFLAGS="--cflags-only-other"
    export PKG_CONFIG_LIBS="--static --libs-only-l"
    export PKG_CONFIG_ALL_LIBS="--static --libs-only-l --libs-only-other"
fi
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

# Helper hooks to skip .la files, dependancies and .pc files auditing
# add ffbuild_dockerbuild() { export SKIP_POST_PATCH=1 } to disable
# add SKIP_PRE_PATCH=1 to the top of the script
# add USE_CONF_FINDER=1 for crooked autogen scripts
export SKIP_PRE_PATCH=0
export SKIP_POST_PATCH=0
export SKIP_POST_CLEAN=0
export SKIP_POST_AUDIT=0
export SKIP_POST_STRIP=0
export USE_CONF_FINDER=0

mkdir -p "$CACHE_DIR" "$TMP_DIR" "$FFMPEG_BUILD_ROOT" "$FFMPEG_DIR"

# Очистка базовых флагов перед объявлением
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS RUSTFLAGS LIBS

# Flags for the component build stage

# Tip: disable -fPIC, -ffast-math, if troubles occur
# Tip: don't use cflags -ffunction-sections, -fdata-sections, linker flag -Wl,--gc-sections with non-static and non GCC builds
# Tip: don't use -fno-plt flag other than Linux host
# Tip: use -Wa,-mbig-obj for c(xx)flags if see 'too many sections' and 'file too big'
# Tip: add -Wl,--whole-archive $LIBS -Wl,--no-whole-archive $OTHER_LIBS in 'Libs:' section in .pc file to incapsulate more libs (voices or other) when using LTO for static builds

# LTO in ffmpeg is bugged when compiled with gcc-(13-14-15) in mingw. You will meet 'lto1: internal compiler error: in choose_baseaddr, at config/i386/i386.cc:7447' or similar at linking time; compiler will crash.
# You can 1) disable LTO for ffmpeg only, but enable LTO for ffmpeg components. 
# Tip: -ffat-lto-objects is needed for ffmpeg linker to understand LTO code if LTO disabled for ffmpeg only bun enabled for components. You can also add -fno-use-linker-plugin to --extra-ldflags to avoud the use of LTO code by ffmpeg itself. But you must be sure to NOT use cmake-specific flags that enable LTO (IPO) because they forcefully add -fno-fat-lto-objects that is unacceptable in our case.
# Option 2) add -mstackrealign to ffmpeg c(xx)flags. With this flag the compiler does not crash. -mpreferred-stack-boundary=4 should not be used.

# these flags appear to conflict with pthread and other threading implementations and cannot be used simultaneously. They should only be used selectively where supported by the libraries themselves
[[ "$USE_OPENMP" == "1" ]] && export OPENMP_C="-fopenmp " && export OPENMP_LIB="-lgomp "

if [[ "$USE_LTO" == "1" ]]; then
# Tip: rust has -C linker-plugin-lto LLVM Bitcode or LLVM MinGW
    export RUSTLTO=" -C lto=fat"
    export USELTO="-flto=auto"
    export USELTO_C=" -ffat-lto-objects -flto-compression-level=16"
    export NOLTO="-fno-lto"
    export AR="${FFBUILD_TOOLCHAIN}-gcc-ar"
    export NM="${FFBUILD_TOOLCHAIN}-gcc-nm"
    export RANLIB="${FFBUILD_TOOLCHAIN}-gcc-ranlib"
fi

# Общие настройки Rust; codegen-units = 16 (default)
COMMON_RUST_OPTS="-C target-cpu=${CPU_ARCH} -C strip=debuginfo -C codegen-units=1 -C opt-level=3 ${RUSTLTO}"

# Общие и дополнительные либы
SYSTEM_LIBS="-lsetupapi -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lws2_32 -lbcrypt -pthread"
ADDITIONAL_LIBS="-lusp10 -lmsimg32 -lcfgmgr32 -lruntimeobject -ldwrite -ld2d1 -lwindowscodecs -lopengl32 -lssp -lgdi32 -lrpcrt4 -luserenv -liphlpapi -lwinmm -luuid -ldnsapi -lcrypt32 -lwldap32 -lnormaliz -lgomp"

# Функция для сборки строки RUSTFLAGS из массива
# Принимает префикс (например "-C link-arg=") и имя массива
to_rust_flags() {
    local prefix="$1"; shift
    printf " ${prefix}%s" "$@"
}

# Флаги для ХОСТА (Linux), которые всегда нужны для нативных сборок
# * -Wl,--hash-style=gnu: Создает более быстрые таблицы символов (GNU-style), что ускоряет запуск программы (актуально для инструментов, которые вызываются тысячи раз за сборку).
# * -Wl,--strip-all (или просто -s): Удаляет отладочные символы, значительно уменьшая размер бинарника.
# * -Wl,--gc-sections: Удаляет неиспользуемый код из бинарника. Работает в паре с -ffunction-sections -fdata-sections в CFLAGS. Полезно, чтобы нативный инструмент был компактным.
# * -Wl,-O1: Включает оптимизации самого линковщика (например, сокращение таблиц хешей).
# * -Wl,--as-needed: Игнорирует библиотеки, которые были указаны в командной строке, но фактически не используются кодом. Это предотвращает лишние зависимости.
# * -Wl,-z,relro -Wl,-z,now: Это «Full RELRO». Аналог --dynamicbase. Делает таблицу функций (GOT) только для чтения, что предотвращает многие эксплойты.
# * -Wl,-z,noexecstack: Прямой аналог --nxcompat. Запрещает выполнение кода в стеке.
HOST_LINUX_LDFLAGS=(
    "-pipe"
    "-Wl,-z,relro"
    "-Wl,-z,now"
    "-Wl,-z,noexecstack"
    "-Wl,--hash-style=gnu"
    "-Wl,-O1"
    "-Wl,--as-needed"
)
[[ "$PREFER_SHARED" != "1" ]] && HOST_LINUX_LDFLAGS+=( "-Wl,--gc-sections" )

# Настраиваем HOST_RUSTFLAGS (всегда Linux ELF)
export HOST_RUSTFLAGS="${COMMON_RUST_OPTS} $(to_rust_flags "-C link-arg=" "${HOST_LINUX_LDFLAGS[@]}") -C embed-bitcode=yes"
export HOST_LDFLAGS="${HOST_LINUX_LDFLAGS[*]} ${USELTO}"
export HOST_CFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma -ftree-vectorize -fno-plt -pipe -g0 -ffunction-sections -fdata-sections -std=gnu23 ${USELTO}${USELTO_C}"
export HOST_CXXFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma -ftree-vectorize -fno-plt -pipe -g0 -ffunction-sections -fdata-sections -std=gnu++20 ${USELTO}${USELTO_C}"
export HOST_CPPFLAGS="-D_FORTIFY_SOURCE=2"

# Ветвление по TARGET
if [[ "$TARGET" == "win64" ]]; then
    export BASE_CFLAGS="-mms-bitfields -fstack-protector-strong"
    export BASE_CPPFLAGS="-D__USE_MINGW_ANSI_STDIO=1 -U_WIN32_WINNT -D_WIN32_WINNT=0x0A00 -D_WIN32 -D_FORTIFY_SOURCE=2"

    BASE_LD_FLAGS=(
        "-pipe"
        "-Wl,--high-entropy-va"
        "-Wl,--nxcompat"
        "-Wl,--dynamicbase"
        "-Wl,--reduce-memory-overheads"
        "-Wl,--stack,16777216"
        "-Wl,--as-needed"
    )

    [[ "$PREFER_SHARED" != "1" ]] && BASE_LD_FLAGS+=( "-Wl,--gc-sections" )

    MAIN_LDFLAGS=("${BASE_LD_FLAGS[@]}")
    MAIN_LDFLAGS+=("-L${FFBUILD_PREFIX}/lib")

    if [[ "$PREFER_SHARED" == "1" ]]; then
        export CFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma -ftree-vectorize -pipe -g0 ${BASE_CFLAGS} -fPIC -std=gnu17"
        export CXXFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma -ftree-vectorize -pipe -g0 ${BASE_CFLAGS} -fPIC -std=gnu++20"
        RUST_STATIC_CFG=""
        export LDFLAGS="${MAIN_LDFLAGS[*]}"
        export FFBUILD_CMAKE_TOOLCHAIN=/toolchain_shared.cmake
        [[ "${USE_WINE}" == "1" ]] && \
        export FFBUILD_MESON_CROSS=/cross_wine_shared.meson || \
        export FFBUILD_MESON_CROSS=/cross_shared.meson
    else
        export CFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma -ftree-vectorize -pipe -g0 ${BASE_CFLAGS} -ffunction-sections -fdata-sections -std=gnu17"
        export CXXFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma -ftree-vectorize -pipe -g0 ${BASE_CFLAGS} -ffunction-sections -fdata-sections -std=gnu++20"
        MAIN_LDFLAGS=("-Wl,-Bstatic" "-static" "-static-libgcc" "-static-libstdc++" "${MAIN_LDFLAGS[@]}")
        RUST_STATIC_CFG="-C target-feature=+crt-static -C embed-bitcode=yes"
        export LDFLAGS="${MAIN_LDFLAGS[*]}"
        export FFBUILD_CMAKE_TOOLCHAIN=/toolchain.cmake
        [[ "${USE_WINE}" == "1" ]] && \
        export FFBUILD_MESON_CROSS=/cross_wine.meson || \
        export FFBUILD_MESON_CROSS=/cross.meson
    fi

    export RUSTFLAGS="${RUST_STATIC_CFG} ${COMMON_RUST_OPTS} $(to_rust_flags "-C link-arg=" "${MAIN_LDFLAGS[@]}")"
    export LIBS="${LIBS:-$SYSTEM_LIBS}"
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="${FFBUILD_CROSS_PREFIX}gcc"

elif [[ "$TARGET" == "linux64" ]]; then
    export BASE_CFLAGS="-fstack-protector-strong"
    export BASE_CPPFLAGS="-D_FORTIFY_SOURCE=2"

    # Используем Linux-специфичные LDFLAGS
    MAIN_LDFLAGS=("${HOST_LINUX_LDFLAGS[@]}")
    MAIN_LDFLAGS+=("-L${FFBUILD_PREFIX}/lib")

    if [[ "$PREFER_SHARED" == "1" ]]; then
        export CFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma -ftree-vectorize -pipe -g0 ${BASE_CFLAGS} -fPIC -std=gnu17"
        export CXXFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma -ftree-vectorize -pipe -g0 ${BASE_CFLAGS} -fPIC -std=gnu++20"
        export STAGE_CFLAGS="-fno-semantic-interposition"
        export STAGE_CXXFLAGS="-fno-semantic-interposition"
        RUST_STATIC_CFG=""
        export LDFLAGS="${MAIN_LDFLAGS[*]}"
        export FFBUILD_CMAKE_TOOLCHAIN=/toolchain_shared.cmake
        [[ "${USE_WINE}" == "1" ]] && \
        export FFBUILD_MESON_CROSS=/cross_wine_shared.meson || \
        export FFBUILD_MESON_CROSS=/cross_shared.meson
    else
        export CFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma -ftree-vectorize -pipe -g0 ${BASE_CFLAGS} -ffunction-sections -fdata-sections -std=gnu17"
        export CXXFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma -ftree-vectorize -pipe -g0 ${BASE_CFLAGS} -ffunction-sections -fdata-sections -std=gnu++20"
        # Для Linux статика — это -static и исключение динамических путей
        MAIN_LDFLAGS=("-static" "-static-libgcc" "-static-libstdc++" "${MAIN_LDFLAGS[@]}")
        RUST_STATIC_CFG="-C target-feature=+crt-static -C embed-bitcode=yes"
        export LDFLAGS="${MAIN_LDFLAGS[*]}"
        export FFBUILD_CMAKE_TOOLCHAIN=/toolchain.cmake
        [[ "${USE_WINE}" == "1" ]] && \
        export FFBUILD_MESON_CROSS=/cross_wine.meson || \
        export FFBUILD_MESON_CROSS=/cross.meson
    fi

    export RUSTFLAGS="${RUST_STATIC_CFG} ${COMMON_RUST_OPTS} $(to_rust_flags "-C link-arg=" "${MAIN_LDFLAGS[@]}")"
    export LIBS="${LIBS} -ldl -lrt"
    export CUDA_PATH=/usr/lib/nvidia-cuda-toolkit
    export PATH="${PATH}:/usr/local/cuda/bin"

fi

export CPPFLAGS="-I${FFBUILD_PREFIX}/include ${BASE_CPPFLAGS}"

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
        log_error "Invalid target/variant: ${TARGET}-${VARIANT} (looked in ${VARIANTS_DIR}). TIP: 'linux64-gpl' or 'win64-nonfree'."
        return 1 2>/dev/null || exit 1
    fi
fi

export LICENSE_FILE="COPYING.LGPLv2.1"

export ADDINS_STR="${ADDINS_STR:-}"

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
    to_df "COPY --link --from=${SELFLAYER} \$INSTALL_ROOT/. \$FFBUILD_PREFIX"
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
    log_info "${TARGET_MARK} Correcting $STAGENAME .pc files..."
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
        [[ "$path" == *'${'* ]] && echo "$path" && return 0

        # Если путь совпадает с префиксом или вложен в него
        if [[ "$path" == "$FFBUILD_PREFIX"* ]]; then
            # Если путь — это просто корень инклудов
            if [[ "$path" == "$FFBUILD_PREFIX/include" ]]; then
                echo "\${includedir}"
            else
                # Если путь глубже (например /include/openjpeg-2.5), 
                # сохраняем относительный путь от ${includedir}
                echo "\${includedir}${path#$FFBUILD_PREFIX/include}"
            fi
            return 0
        fi

        # Bare /include or /usr/include — replace with ${includedir}
        if [[ "$path" == "/include" || "$path" == "/usr/include" ]]; then
            echo "\${includedir}"
            return 0
        fi

        # Relative path like ../include — resolve and check
        if [[ "$path" == ../* ]]; then
            local resolved
            resolved=$(cd "$(dirname "$pc_dir")" && cd "${path%/*}" && pwd 2>/dev/null)
            if [[ -n "$resolved" && "$resolved" == "$FFBUILD_PREFIX"* ]]; then
                echo "\${prefix}${resolved#$FFBUILD_PREFIX}${path##*/}"
                return 0
            fi
        fi

        # Если путь не распознан, возвращаем его оригинал
        echo "$path"
        return 0
    }

    # helper escape string for use as a literal sed pattern
    sed_escape() { printf '%s' "$1" | sed 's/[[\.*^$()+?{|]/\\&/g'; }

    # Собираем все .pc файлы в массив и выводим список найденных файлов
    log_debug "Correcting values in .pc files:"
    mapfile -t PC_FILES < <(find "$pc_dir" -maxdepth 1 -name "*.pc")
    [[ ${#PC_FILES[@]} -eq 0 ]] && return 0
    for pc in "${PC_FILES[@]}"; do
        echo "$pc" >&2
    done

    find "$pc_dir" -maxdepth 2 -name "*.pc" | while read -r pc; do
        [[ -f "$pc" ]] || continue
        log_debug "Processing: $(basename "$pc")"

        # Проверяем, не содержит ли исходный файл уже специфичный путь
        local original_inc=$(grep "^includedir=" "$pc" | cut -d'=' -f2-)

        # Пересоздание переменных путей
        sed -i $sl '/^prefix=/d; /^exec_prefix=/d; /^libdir=/d; /^includedir=/d; /^bindir=/d; /^libdir64=/d' "$pc"

        # Если оригинальный путь был глубже базового, восстанавливаем его
        local target_inc="\${prefix}/include"
        if [[ "$original_inc" == *"/openjpeg-"* || "$original_inc" == *"/freetype2"* ]]; then
             target_inc="\${prefix}/include$(echo "$original_inc" | sed "s|.*include||")"
        fi

        sed -i $sl "1i prefix=$FFBUILD_PREFIX\nexec_prefix=\${prefix}\nlibdir=\${prefix}/lib\nincludedir=$target_inc\nbindir=\${prefix}/bin" "$pc"

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
            for flag in $cflags_line; do
                if [[ "$flag" == -I* ]]; then
                    local path="${flag#-I}"
                    # Пытаемся нормализовать. Если функция вернула 1 или пусто, 
                    # оставляем оригинальный путь, чтобы не потерять его.
                    local normalized
                    normalized=$(normalize_include_path "$path") || normalized="$path"
                    if ! echo "$seen_paths" | grep -qF "x$normalized"; then
                        normalized_cflags="$normalized_cflags -I$normalized"
                        seen_paths="$seen_paths x$normalized"
                    fi
                else
                    # Сохраняем макросы (-D) и прочие флаги
                    normalized_cflags="$normalized_cflags $flag"
                fi
            done
            # Гарантируем наличие основного пути, если его вдруг не было
            if [[ ! "$normalized_cflags" == *"\${includedir}"* ]]; then
                 normalized_cflags="-I\${includedir} $normalized_cflags"
            fi
            # Чистим пробелы и записываем
            normalized_cflags=$(echo "$normalized_cflags" | xargs)
            sed -i "s|^Cflags:.*|Cflags: $normalized_cflags|" "$pc"
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

        local escaped_base=$(sed_escape "$base_name")
        local main_libs=$(echo "$libs_line" | grep -oE "\-l${escaped_base}[a-zA-Z0-9._+-]*" | xargs)
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

        # Case normalization for variations (Libs.Private, REQUIRES.PRIVATE)
        sed -i $sl -E 's/^[Ll]ibs\.[Pp]rivate:/Libs.private:/g' "$pc"
        sed -i $sl -E 's/^[Rr]equires\.[Pp]rivate:/Requires.private:/g' "$pc"

        # Ensure Requires.private and Libs.private fields exist
        grep -q "^Requires.private:" "$pc" || sed -i $sl "/^Version:/a Requires.private:" "$pc"
        grep -q "^Libs.private:" "$pc" || sed -i $sl "/^Libs:/a Libs.private:" "$pc"

        # Append discovered deps (raw, dedup happens)
        sed -i $sl "/^Requires.private:/ s|$| $extra_requires|" "$pc"
        sed -i $sl "/^Libs.private:/ s|$| $leftovers $extra_libs $LIBS|" "$pc"

        # Capitalisation fixes
        sed -i $sl 's/-lWs2_32/-lws2_32/g; s/-lWinmm/-lwinmm/g; s/-lpthread/-pthread/g' "$pc"
        # Remove -lrt (Linux-only, not on Windows)
        [[ "$TARGET" != "linux64" ]] && sed -i $sl 's/ -lrt\b//g' "$pc"
        # Apply -lzlib → -lz (after all -l tokens are in the file)
        sed -i $sl 's/-lzlib\b/-lz/g' "$pc"
        # Исправляем дублирование префиксов lib
        sed -i $sl 's/ -l-l/ -l/g' "$pc"

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
    local lib_dir="$INSTALL_ROOT/lib"
    local bin_dir="$INSTALL_ROOT/bin"
    local pc_dir="${lib_dir}/pkgconfig"
    local toolchain="${FFBUILD_TOOLCHAIN:-x86_64-w64-mingw32}"
    local lddtree_cmd="lddtree"
    if ! command -v "$lddtree_cmd" &>/dev/null; then
        lddtree_cmd=""
    fi

    # Used only for readelf/nm filtering of well-known system libs
    local sys_libs="libc\.so|libm\.so|libdl\.so|librt\.so|libpthread\.so|libgcc_s\.so|libstdc\+\+\.so|ld-linux|libresolv\.so|libutil\.so"

    # Создаем временный файл для сбора вывода
    local tmp_out=$(mktemp)

    # Считаем общий вес установленных файлов компонента
    local total_size="0"
    if [[ -d "$INSTALL_ROOT" ]]; then
        total_size=$(du -sh "$INSTALL_ROOT" | awk '{print $1}')
    fi

    # Поиск pkg-config зависимостей
    if [[ -d "$pc_dir" ]]; then
        find "$pc_dir" -name "*.pc" -exec bash -c '
            pc_file="$1"; pkg_config_cmd="$2"; pc_dir="$3"; prefix="$4"

            export PKG_CONFIG_LIBDIR="$pc_dir:$prefix"
            export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
            export PKG_CONFIG_SYSROOT_DIR="/"

            pkg_name=$(basename "$pc_file" .pc)

            printf "\n%b %bFILE:%b %s\n" "$7" "$PURPLE" "$NC" "$pc_file"
            cat "$pc_file"

            printf "\n%b %bDEPENDENCIES%b for %s:\n" "$8" "$PURPLE" "$NC" "$pkg_name"

            deps=$($pkg_config_cmd --print-requires --print-requires-private "$pkg_name" 2>/dev/null | awk "{print \$1}" | sort -u)

            if [[ -n "$deps" ]]; then
                while read -r dep; do
                    [[ -z "$dep" ]] && continue
                    if $pkg_config_cmd --exists "$dep" 2>/dev/null; then
                        ver=$($pkg_config_cmd --modversion "$dep" 2>/dev/null || echo "unknown")
                        printf " %b•%b %-20s %b(found: %s)%b\n" "$LOG_INFO" "$NC" "$dep" "$GREY" "$ver" "$NC"
                    else
                        printf " %b• MISSING:%b %s %b(in: %s)%b\n" "$LOG_ERROR" "$NC" "$dep" "$LOG_ERROR" "$pc_dir" "$NC"
                    fi
                done <<< "$deps"
            else
                printf "%b No dependencies found in .pc file\n" "$CHECK_MARK"
            fi
        ' _ {} \
            "${PKG_CONFIG:-pkg-config}" \
            "$pc_dir" \
            "$PKG_CONFIG_LIBDIR" \
            "$LOG_ERROR" \
            "$NC" \
            "$XCLAM_MARK" \
            "$SEARCH_MARK" \; >> "$tmp_out" || true
    fi
    if [[ "$PREFER_SHARED" == "1" ]]; then
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
        # lddtree: Full dependency tree with missing libs check
        if [[ -n "$lddtree_cmd" ]]; then
            find "$lib_dir" "$bin_dir" -type f \
                \( -name "*.so*" -o -name "*.exe" -o -name "*.dll" \) \
                -print0 2>/dev/null | \
            xargs -0 -r -I{} bash -c '
                file="$1"; cmd="$2"; sys_regex="$3"; x_mark="$4"; err_mark="$5"; nc="$6"

                if head -c 4 "$file" | grep -q "ELF"; then
                    # Получаем дерево, отсеиваем системный шум
                    tree_out=$("$cmd" -n -p "$file" 2>/dev/null | grep -Ev "$sys_regex" || true)

                    if [[ -n "$tree_out" ]]; then
                        # Проверяем наличие строк "not found" в выводе lddtree
                        if echo "$tree_out" | grep -q "not found"; then
                            # Подсвечиваем отсутствующие библиотеки красным
                            tree_out=$(echo "$tree_out" | sed "s|not found|${err_mark} NOT FOUND${nc}|g")
                            printf "\n%b %bCRITICAL: MISSING DEPENDENCIES%b for %s:\n%s\n" \
                                "$err_mark" "${LOG_ERROR}" "$nc" "$file" "$tree_out"
                        else
                            printf "\n%b FULL DEP TREE for %s:\n%s\n" \
                                "$x_mark" "$file" "$tree_out"
                        fi
                    fi
                fi
            ' _ {} "$lddtree_cmd" "$sys_libs" "$SEARCH_MARK" "$CROSS_MARK" "$NC" >> "$tmp_out" || true
        fi
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
    else
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
                        if (sym != \"\") printf \"%-15s %s→%s %s\n\", \$2, \"$GREY_B\", \"$NC\", sym 
                    }" | sort -u | head -n 12)

                if [[ -n "$clean_symbols" ]]; then
                    printf "\n%b %bEXTERNAL SYMBOLS (OBJ %b→%b %bSYM)%b in %s:\n" \
                        "$x_mark" "$YELLOW" "$GREY_B" "$YELLOW" "$YELLOW" "$NC" "$file"
                    echo "$clean_symbols" | sed "s|^| ${LOG_INFO}•${NC} |"

                    # добавляем принудительный перенос строки
                    # printf "\n"
                fi
            fi
        ' _ {} "$toolchain" "$XCLAM_MARK" >> "$tmp_out" || true
    fi

    # Output
    local error_count=0
    if [[ -f "$tmp_out" ]]; then
        # Считаем и MISSING (из pkg-config) и NOT FOUND (из lddtree)
        error_count=$(grep -cE "MISSING:|NOT FOUND" "$tmp_out" || true)
    fi
    error_count=$(( 10#${error_count:-0} ))

    if [[ -s "$tmp_out" ]]; then
        if [ "$error_count" -gt 0 ]; then
            log_warn "Found ${error_count} missing dependency/dependencies for ${name}! [Install size: ${GREY_B}${total_size}${NC}]"
        else
            log_debug "${CHECK_MARK} All pkg-config dependencies satisfied for ${name}. [Install size: ${GREY_B}${total_size}${NC}]"
        fi
        log_debug "Showing dependencies for ${name}:"
        cat "$tmp_out" >&2
    else
        log_info "${CHECK_MARK} No dependencies found for ${name} (meta/header-only). [Install size: ${GREY_B}${total_size}${NC}]."
    fi

    rm -f "$tmp_out"
}
export -f get_deps_list

# Function for cleaning files with logging
# Arguments: 1 - description (for the log), 2 - search conditions (find expression)
clean_unwanted_libs() {
    local label="$1"
    local find_expr="$2"
    local DELETED_FILES

    # Выполняем удаление и захватываем список
    DELETED_FILES=$(eval "find \"$INSTALL_ROOT\" -type f $find_expr -print -delete 2>/dev/null" | sed "s|$FFBUILD_DESTDIR||g")

    if [[ -n "$DELETED_FILES" ]]; then
        log_debug "${BROOM_MARK} Removing $label for ${STAGENAME}:\n$DELETED_FILES"
    else
        log_info "${CHECK_MARK} No unwanted $label found."
    fi
}
export -f clean_unwanted_libs

# Generates .a files from .dll files for dynamic libraries we want to link.
# Typically called for components in DLL_PRESERVE_LIST
generate_implibs() {
    local target_dir="${1:-$INSTALL_ROOT}"
    [[ ! -d "$target_dir" ]] && return 0

    log_info "${TARGET_MARK} Generating clean import libraries for DLLs..."

    find "$target_dir" -name "*.dll" -type f | while read -r dll_file; do
        local dll_name=$(basename "$dll_file")
        local base_name="${dll_name%.dll}"
        local lib_name="lib${base_name}.a"
        local dll_dir=$(dirname "$dll_file")
        
        # Output to lib/
        local lib_out_dir="$dll_dir"
        [[ "$dll_dir" == *"/bin" ]] && lib_out_dir="${dll_dir%/bin}/lib"
        mkdir -p "$lib_out_dir"

        local out_lib="$lib_out_dir/$lib_name"

        # Skip if valid lib exists
        if [[ -f "$out_lib" ]] && [[ $(stat -c%s "$out_lib" 2>/dev/null) -lt 2097152 ]]; then
            log_debug "${CHECK_MARK} Valid import lib exists for $dll_name (size: $(stat -c%s "$out_lib" | numfmt --to=si))"
            continue
        fi

        log_debug "${BUILD_MARK} Creating import lib for $dll_name"

        local tmp_build=$(mktemp -d)
        cp "$dll_file" "$tmp_build/"
        pushd "$tmp_build" > /dev/null

        local def_file="${base_name}.def"

        # FIX: Use objdump to extract symbols, filter for imports
        if command -v objdump &> /dev/null; then
            # Extract all symbols and filter for import symbols (__imp_*)
            # We look for lines that look like imports: 00000000 g     DF .idata 0000000000000000 _Z...
            objdump -p "$dll_name" 2>/dev/null | \
            grep -E "  [0-9A-F] [0-9A-F] [0-9A-F] [0-9A-F] " | \
            grep -v " 00000000 " | \
            awk '{print $NF}' | \
            sort -u > "$def_file"
            
            # Ensure EXPORTS section exists
            if ! grep -q "^EXPORTS" "$def_file"; then
                echo "EXPORTS" > "$def_file"
            fi
        else
            # Fallback
            log_warn "objdump not found, creating minimal def"
            echo "EXPORTS" > "$def_file"
        fi

        # FIX: Create the import library
        if $DLLTOOL -d "$def_file" -l "$lib_name" -D "$dll_name" 2>/dev/null; then
            local size=$(stat -c%s "$lib_name" 2>/dev/null)
            if [[ $size -lt 2097152 ]]; then
                cp "$lib_name" "$out_lib"
                log_info "${CHECK_MARK} Created valid import lib: $out_lib ($size bytes)"
            else
                log_warn "Generated lib too large ($size bytes), likely malformed. Deleting."
                rm -f "$lib_name"
            fi
        else
            log_error "dlltool failed for $dll_name"
        fi

        popd > /dev/null
        rm -rf "$tmp_build"
    done
}
export -f generate_implibs

clean_la_files() {
    if [[ "$PREFER_SHARED" == "1" ]]; then
        return 0
    fi

    local target_dir="$INSTALL_ROOT"
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

strip_files() {
    local target_dir="$1"
    local stage_name="$2"

    if [[ "$SKIP_POST_STRIP" == "1" ]]; then
        log_info "${LOCK_MARK} Stripping skipped (global/manual flag)"
        return 0
    fi

    # Проверка списка исключений
    local IFS_ORIG="$IFS"
    IFS=',' read -ra _excl_arr <<< "$STRIP_EXCLUDE_LIST"
    IFS="$IFS_ORIG"
    for _excl in "${_excl_arr[@]}"; do
        if [[ "${_excl// /}" == "$stage_name" ]]; then # trim spaces
            log_info "${LOCK_MARK} Stripping skipped for $stage_name (exclude list)"
            return 0
        fi
    done

    [[ ! -d "$target_dir" ]] && return 0

    local _strip_cmd="${FFBUILD_CROSS_PREFIX}strip"
    local size_before=$(du -sh "$target_dir" | cut -f1) # Замеряем размер ДО

    log_info "${BROOM_MARK} Stripping $stage_name from debug symbols: [Size: ${GREY_B}$size_before${NC}]"

    find "$target_dir" -type f \
        \( -name "*.exe" -o -name "*.dll" -o -name "*.a" -o -name "*.so*" \) \
        ! -name "*.dll.a" -exec "$_strip_cmd" --strip-debug {} + 2>/dev/null || true

    local size_after=$(du -sh "$target_dir" | cut -f1)

    if [[ "$size_before" == "$size_after" ]]; then
        log_info "${CHECK_MARK} Stripping finished. [Size unchanged: ${GREY_B}$size_after${NC}]"
    else
        log_info "${CHECK_MARK} Stripping finished. [$size_before -> ${GREY_B}$size_after${NC}]"
    fi
}
export -f strip_files

# 1. Standard
# 2. Binary (for CRLF issues)
# 3. Ignore Whitespace
# 4. Max Fuzz (fuzz=3)
apply_patches() {
    local PATCH_DIR="$PATCHES_DIR/$COMPONENT_NAME"
    [[ -d "$PATCH_DIR" ]] || { log_info "${CHECK_MARK} No patches found for $COMPONENT_NAME"; return 0; }

    # Сохраняем текущую папку (куда нас завел авто-поиск корня)
    local CURRENT_ROOT=$(pwd)
    # Сохраняем базовую папку билда
    local BUILD_BASE="/build/$STAGENAME"

    shopt -s nullglob
    local patch_failed_any=false

    for patch in "$PATCH_DIR"/*.patch; do
        log_info "${TARGET_MARK} APPLYING PATCH: $(basename "$patch")"

        local success=false
        local last_output=""

        # ПЕРЕБОР ДИРЕКТОРИЙ. сначала текущая (из авто-поиска), потом базовая
        for try_dir in "$CURRENT_ROOT" "$BUILD_BASE"; do
            [[ -d "$try_dir" ]] || continue
            pushd "$try_dir" &>/dev/null
            log_debug "Attempting patch in: $(pwd)"

        # Try git am first
        if [[ -d ".git" ]]; then
            local git_opts
            for git_opts in \
                "git am --ignore-space-change --whitespace=fix" \
                "git am --ignore-space-change --whitespace=fix --reject"
            do
                log_debug "Trying: $git_opts"
                # 'if' suppresses set -e on the command
                if last_output=$(eval "$git_opts" < "$patch" 2>&1); then
                    log_info "${CHECK_MARK} SUCCESS: Applied with [$git_opts]"
                    success=true
                    break
                else
                    git am --abort 2>/dev/null || true
                fi
            done
        fi

        # Try git apply (with temporary git init if needed)
        if [[ "$success" == "false" ]]; then
            local temp_git=false
            if [[ ! -d ".git" ]]; then
                if git init -q && git add -A && git commit -qm "temp_init"; then
                    temp_git=true
                fi
            fi

            local apply_opts
            for apply_opts in \
                "--ignore-space-change --ignore-whitespace" \
                "--ignore-space-change --ignore-whitespace --3way" \
                "--ignore-space-change --ignore-whitespace --recount"
            do
                log_debug "Trying: git apply $apply_opts"
                if last_output=$(git apply $apply_opts "$patch" 2>&1); then
                    log_info "${CHECK_MARK} SUCCESS: Applied with [git apply $apply_opts]"
                    success=true
                    break
                fi
            done

            # Cleanup temporary git
            if [[ "$temp_git" == "true" ]]; then
                rm -rf .git || true
            fi
        fi

        # Fall back to patch utility
        if [[ "$success" == "false" ]]; then
            local patch_opts
            for patch_opts in \
                "-p1 -N -r -" "-p0 -N -r -" \
                "-p1 -N -r - --binary" "-p0 -N -r - --binary" \
                "-p1 -N -r - -l" "-p0 -N -r - -l" \
                "-p1 -N -r - -l --fuzz=3" "-p0 -N -r - -l --fuzz=3"
            do
                log_debug "Trying: patch $patch_opts"
                # Сначала проверяем, применится ли патч без изменения файлов
                if patch --dry-run --silent $patch_opts < "$patch" &>/dev/null; then
                    # 'if' suppresses set -e on patch exit code
                    if last_output=$(patch $patch_opts < "$patch" 2>&1); then
                        log_info "${CHECK_MARK} SUCCESS: Applied with [patch $patch_opts]"
                        success=true
                        break
                    fi
                fi
            done
        fi

            popd &>/dev/null
            [[ "$success" == "true" ]] && break
        done

        if [[ "$success" == "false" ]]; then
            log_error "FAILED: All attempts to apply $(basename "$patch") failed."
            log_debug "Last attempt output:\n${last_output}"
            patch_failed_any=true
            # Uncomment to make patch failure fatal:
            # return 1
        fi
    done

    shopt -u nullglob

    if [[ "$patch_failed_any" == "true" ]]; then
        log_warn "Some patches failed to apply for $COMPONENT_NAME — build continuing."
    fi

    return 0
}
export -f apply_patches

apply_ffmpeg_patches() {
    local FFMPEG_PATCH_DIR="$PATCHES_DIR/ffmpeg/$FFMPEG_BRANCH"

    [[ -d "$FFMPEG_PATCH_DIR" ]] || { log_info "${CHECK_MARK} No patches found for branch: $FFMPEG_BRANCH"; return 0; }

    log_info "${SEARCH_MARK} Applying FFmpeg patches from: $FFMPEG_PATCH_DIR"

    if [[ ! -d ".git" ]]; then
        log_warn "FFmpeg source is not a git repo. Initializing temporary git for reliable patching..."
        git init -q && git add -A && git commit -qm "base"
    fi

    shopt -s nullglob
    for patch in "$FFMPEG_PATCH_DIR"/*.patch; do
        log_info "${TARGET_MARK} APPLYING: $(basename "$patch")"

        if git apply --ignore-whitespace --intent-to-add "$patch" 2>/dev/null; then
            log_info "${CHECK_MARK} SUCCESS: Applied $(basename "$patch")"
            git add -A || true
        else
            log_error "FAILED: $(basename "$patch") - skipping"
            git reset -q HEAD -- . || true
        fi
    done
    shopt -u nullglob

    return 0
}
export -f apply_ffmpeg_patches

# checking flags validity for final FFmpeg build; if found we just drop them and continue
# tip: check logs after applying \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z |\[?(0|1)?(m|;)?(3.m|) regex to them! search: REGEX replace: empty
check_and_fix_configure() {
    if [[ "$SAFE_CONFIGURE" != "1" ]]; then
        return 0
    fi

    log_info "SAFE_CONFIGURE: Checking flags for validity..."

    local new_flags=()
    local dropped=()
    local fixed=()

    # Кэшируем справку. Используем расширенный поиск.
    local help_output=$(./configure --help)

    for flag in "${CONF_FLAGS[@]}"; do
        # Извлекаем чистое имя опции для проверки (убираем --enable-/--disable- и всё что после =)
        local clean_opt=$(echo "$flag" | sed -E 's/--[a-z]+-//; s/=.*//')
        local action=$(echo "$flag" | grep -oE "^--(enable|disable)")
        
        # Если это не стандартный переключатель (например --prefix, --cc), проверяем и пропускаем
        if [[ ! "$flag" =~ ^--enable- ]] && [[ ! "$flag" =~ ^--disable- ]]; then
            new_flags+=("$flag")
            continue
        fi

        # Блок автозамены (Aliasing)
        local opt_name="$clean_opt"
        case "$opt_name" in
            zstd)          opt_name="libzstd" ;;
            pcre2)         opt_name="libpcre2" ;;
            pcre)          opt_name="libpcre" ;;
            fontconfig)    opt_name="libfontconfig" ;;
            openjpeg)      opt_name="libopenjpeg" ;;
            curl)          opt_name="libcurl" ;;
            brotli)        opt_name="libbrotli" ;;
            rav1e)         opt_name="librav1e" ;;
            dav1d)         opt_name="libdav1d" ;;
            aom)           opt_name="libaom" ;;
            svtav1)        opt_name="libsvtav1" ;;
            vpx)           opt_name="libvpx" ;;
            webp)          opt_name="libwebp" ;;
            xml2)          opt_name="libxml2" ;;
            # Можно добавить другие частые ошибки здесь
        esac

        # Собираем флаг обратно (сохраняя аргумент после =, если он был)
        local suffix=$(echo "$flag" | grep -oE "=.*$" || true)
        # Формируем потенциально исправленный флаг
        local current_flag="${action}-${opt_name}${suffix}"

        # Валидация через grep
        # Ищем в help: --enable-opt_name, --enable-opt_name[=arg], или описание начинающееся с opt_name
        # Используем [[:punct:]]? чтобы поймать опциональные скобки [=arg]
        if echo "$help_output" | grep -qE "\--(en|dis)able-${opt_name}([[:punct:]]|=|[[:space:]]|$)"; then
            if [[ "$current_flag" != "$flag" ]]; then
                fixed+=("$flag -> $current_flag")
            fi
            new_flags+=("$current_flag")
        else
            # Если это специфический компонент (энкодер/декодер), проверяем его наличие в списках
            # Но ТОЛЬКО если это действительно точное совпадение слова, а не часть другого флага
            if echo "$help_output" | grep -qiwE "${opt_name}"; then
                 new_flags+=("$current_flag")
            else
                 dropped+=("$flag")
            fi
        fi
    done

    # Вывод отчета
    [ ${#fixed[@]} -ne 0 ] && log_info "${BUILD_MARK} FIXED flags: ${fixed[*]}"
    [ ${#dropped[@]} -ne 0 ] && log_warn "DROPPED invalid flags: ${dropped[*]}"

    CONF_FLAGS=("${new_flags[@]}")
}
export -f check_and_fix_configure

# Получаем версию VER_FULL=$(get_stage_version)
get_stage_version() {
    local version_file=".ffbuild_version"
    [[ -f "$version_file" ]] && { cat "$version_file"; return 0; }

    local ver=""

    # Поиск в файлах конфигурации пакетов
    if [[ -z "$ver" ]]; then
        local pc_in=$(find . -maxdepth 3 -name "*.pc.in" -o -name "*.pc" | head -n 1)
        if [[ -f "$pc_in" ]]; then
            ver=$(grep -i "^Version:" "$pc_in" | grep -oE '[0-9]+(\.[0-9]+)+[^ ]*' | head -n1)
        fi
    fi

    # Git (учитываем аннотированные теги и сортировку)
    if [[ -z "$ver" && -d ".git" ]]; then
        # Получаем последний тег, очищая от ^{} и префиксов v
        ver=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//;s/\^{}//')
        # Если локальных тегов нет, пробуем удаленные, но только если сеть доступна
        if [[ -z "$ver" ]]; then
            local remote_url=$(git config --get remote.origin.url 2>/dev/null)
            if [[ -n "$remote_url" ]]; then
                ver=$(git ls-remote --tags --refs "$remote_url" | tail -n1 | cut -d/ -f3 | sed 's/^v//;s/\^{}//')
            fi
        fi

        # Если это "raw" репозиторий без тегов, берем короткий хэш
        [[ -z "$ver" ]] && ver="git-$(git rev-parse --short HEAD 2>/dev/null)"
    fi

    # CMake (многострочный поиск)
    if [[ -z "$ver" && -f "CMakeLists.txt" ]]; then
        # Ищем паттерн VERSION 1.2.3 даже если он на другой строке после project(
        ver=$(grep -Pzo '(?i)project\s*\(.*VERSION\s+([0-9.]+)' CMakeLists.txt | tr -d '\0' | grep -oE '[0-9]+(\.[0-9]+)+')
    fi

    # парсинг CMake (ищем PROJECT_VERSION или MAJOR/MINOR)
    if [[ -z "$ver" && -f "CMakeLists.txt" ]]; then
        local v_maj=$(grep -iP 'SET.*VERSION_MAJOR' CMakeLists.txt | grep -oP '[0-9]+')
        local v_min=$(grep -iP 'SET.*VERSION_MINOR' CMakeLists.txt | grep -oP '[0-9]+')
        local v_pat=$(grep -iP 'SET.*VERSION_BUILD|SET.*VERSION_PATCH' CMakeLists.txt | grep -oP '[0-9]+')
        [[ -n "$v_maj" && -n "$v_min" ]] && ver="${v_maj}.${v_min}.${v_pat:-0}"
    fi

    # Meson
    if [[ -z "$ver" && -f "meson.build" ]]; then
        ver=$(grep -m1 "version\s*:" meson.build | grep -oE "[0-9]+(\.[0-9]+)+" | head -n1)
    fi

    # Autotools (configure.ac / configure.in)
    if [[ -z "$ver" ]]; then
        local conf_ac=$(find . -maxdepth 1 \( -name "configure.ac" -o -name "configure.in" \))
        if [[ -n "$conf_ac" ]]; then
            ver=$(grep -m1 "AC_INIT" "$conf_ac" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')
        fi
    fi

    # Header файлы (для библиотек вроде x264/x265)
    if [[ -z "$ver" ]]; then
        local h_file=$(find . -maxdepth 2 -name "version.h" -o -name "*_version.h" | head -n 1)
        if [[ -f "$h_file" ]]; then
            # Ищем макросы типа #define VERSION "..." или #define API_VERSION 123
            ver=$(grep -iE 'define.*VERSION' "$h_file" | grep -oE '[0-9]+(\.[0-9]+)+[^ "]*' | head -n1)
        fi
    fi

    # Fallback на имя папки
    [[ -z "$ver" ]] && ver=$(basename "$PWD" | grep -oE '[0-9]+(\.[0-9]+)+[^ ]*' | head -n1)

    # Очистка результата от лишних символов (запятые, кавычки)
    ver=$(echo "$ver" | tr -d '",)')

    # Валидация
    if [[ -n "$ver" ]]; then
        echo "$ver" > "$version_file"
        echo "$ver"
    else
        echo "0.0.1" > "$version_file"
        echo "0.0.1"
    fi
}
export -f get_stage_version

if [[ "${USE_WINE:-0}" = "1" ]]; then
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
            [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && log_raw "${DIRS_MARK} WINEPATH (Windows style):" "$WINEPATH"
        fi
    fi
fi

# Определяем режим работы Wine (берем из ENV или ставим auto по умолчанию)
# may not work from here because $STAGE is set in run_stage.sh before setup_wine_env is called; might need to be moved to top of run_stage.sh
USE_WINE="${USE_WINE:-1}"
setup_wine_env() {
    # Сохраняем текущее состояние set -e
    local errexit_state=$([[ $- =~ e ]] && echo "set -e" || echo "set +e")
    set +e # Временно отключаем остановку при ошибках

    # Wine globally disabled
    if [[ "${USE_WINE:-0}" != "1" ]]; then
        eval "$errexit_state"; return 0
    fi

    # No stage to inspect
    if [[ -z "$STAGE" || ! -f "$STAGE" ]]; then
        eval "$errexit_state"; return 0
    fi

    # Scan the stage script for patterns that indicate Wine is needed.
    # We search for:
    #   - explicit wine invocations
    #   - test runner calls that require executing Windows binaries
    #   - direct .exe execution
    # NOTE: grep searches the script SOURCE FILE, so patterns must match
    # what authors write in ffbuild_dockerbuild(), not runtime commands.
    local wine_patterns=(
        'wine[[:space:]]'       # wine <binary>
        'wineboot'              # explicit wineboot call
        '\.exe'                 # any .exe reference (run or test)
        'meson[[:space:]]+test' # meson test runner
        'ctest'                 # cmake test runner
        'make[[:space:]]+check' # autotools make check
        'make[[:space:]]+test'  # autotools make test
        'ninja[[:space:]]+test' # ninja test target
        'WINELOADER'
    )

    local combined_pattern
    combined_pattern=$(printf '%s|' "${wine_patterns[@]}")
    combined_pattern="${combined_pattern%|}" # strip trailing |

    if ! grep -qE "$combined_pattern" "$STAGE"; then
        log_debug "Wine: skipped for $STAGENAME (no execution patterns found)"
        eval "$errexit_state"; return 0
    fi

    log_info "${START_MARK} Wine required for $STAGENAME — initializing..."

    # Start virtual display if not already running
    if ! pgrep -x "Xvfb" > /dev/null 2>&1; then
        log_info "${START_MARK} Initializing Xvfb on :99 for Wine tests..."
        # Запуск на дисплее 99 без xvfb-run (меньше оверхед)
        ( Xvfb :99 -screen 0 1024x768x16 >/dev/null 2>&1 & )
        local retry=0
        while [[ $retry -lt 15 ]]; do
            DISPLAY=:99 xset -q >/dev/null 2>&1 && break
            sleep 0.4
            (( retry++ ))
        done
        if [[ $retry -ge 15 ]]; then
            log_warn "Xvfb did not start in time - Wine tests may fail"
        fi
    fi

    export DISPLAY=:99

    # Warm up Wine server asynchronously

    ( wineboot -u >/dev/null 2>&1 & )

    eval "$errexit_state"
}
export -f setup_wine_env

conf_finder() {
    # Opt-IN: only run if script explicitly requests it
    [[ "$USE_CONF_FINDER" != "1" ]] && return 0

    # Если configure нет, или он старый (configure.ac новее), запускаем регенерацию
    if [[ ! -f "configure" || "configure.ac" -nt "configure" ]]; then
        log_debug "${SYNC_MARK} conf_finder: Regenerating build files..."

        # Создаем папку для макросов, если она прописана, но её нет (частая ошибка libffi)
        local m4_dir=$(grep -oP 'AC_CONFIG_MACRO_DIRS?\(\[\K[^\]]+' configure.ac 2>/dev/null || echo "m4")
        mkdir -p "$m4_dir"

        # Пытаемся сначала autoreconf, так как он наиболее стандартизирован
        # -f (force), -i (install missing), -v (verbose)
        if autoreconf -fiv; then
            log_info "${CHECK_MARK} autoreconf: Success"
        elif [[ -f "autogen.sh" ]]; then
            log_warn "autoreconf failed, trying ./autogen.sh..."
            chmod +x autogen.sh
            ./autogen.sh || { log_error "autogen.sh failed"; return 1; }
        elif [[ -f "bootstrap" ]]; then
            log_warn "autoreconf failed, trying ./bootstrap..."
            chmod +x bootstrap
            ./bootstrap || { log_error "bootstrap failed"; return 1; }
        else
            log_error "conf_finder: All regeneration attempts failed."
            return 1
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

# Enhanced separator with box-drawing characters
# separator_box <char> <label> [style]
#   style: "top" | "mid" | "bottom" (default: full box)
separator_box() {
    local char="${1:-─}"
    local label="${2:-}"
    local style="${3:-top}"
    local width
    width=$(_term_width)
    local inner=$(( width - 2 )) # width minus ┌ and ┐

    case "$style" in
        top)
            # ┌─────────────────────────────────────────────────────────────┐
            if [[ -z "$label" ]]; then
                printf '┌%s┐\n' "$(_repeat_char "$inner" "$char")" >&2
            else
                # Автоматически добавляем скобки, если их нет
                if [[ ! "$label" =~ ^\[.*\]$ ]]; then
                    label="[ $label ]"
                fi

                local label_len=${#label}
                local fill=$(( inner - label_len ))
                [[ $fill -lt 0 ]] && fill=0

                local left=$(( fill / 2 ))
                local right=$(( fill - left ))
                # Печатаем без лишних пробелов, так как они теперь внутри label
                printf '┌%s%s%s┐\n' \
                    "$(_repeat_char "$left" "$char")" \
                    "$label" \
                    "$(_repeat_char "$right" "$char")" >&2
            fi
            ;;
        mid)
            # ├─────────────────────────────────────────────────────────────┤
            printf '├%s┤\n' "$(_repeat_char "$inner" "$char")" >&2
            ;;
        bottom)
            # └─────────────────────────────────────────────────────────────┘
            printf '└%s┘\n' "$(_repeat_char "$inner" "$char")" >&2
            ;;
        # *)
            # Full box (top + bottom in one call — not typical, but available)
            # separator_box "$char" "$label" "top"
            # separator_box "$char" "" "bottom"
            # ;;
    esac
}
export -f separator_box

# phase_header <EMOJI> <TITLE>
phase_header() {
    local emoji="$1"; shift
    local width=$(_term_width)
    local line=$(_repeat_char $((width - 2)) "─")

    printf '╭%s╮\n' "$line" >&2
    printf '  %b%s %s%b  \n' "${LOG_INFO}" "$emoji" "$*" "${NC}" >&2
    printf '╰%s╯\n' "$line" >&2
}
# Enhanced phase_header with box borders
# phase_header() {
    # local emoji="$1"; shift
    # local width=$(_term_width)
    
    # separator_box "─" "" "top"
    # printf '  %b%s %s%b  \n' "${LOG_INFO}" "$emoji" "$*" "${NC}" >&2
    # separator_box "─" "" "bottom"
# }
export -f phase_header

# phase_footer <message>
phase_footer() {
    local width=$(_term_width)
    local line=$(_repeat_char $((width - 2)) "─")
    printf '╭%s╮\n' "$line" >&2
    printf '  %b%s%b  \n' "${LOG_INFO}" "$*" "${NC}" >&2
    printf '╰%s╯\n' "$line" >&2
}
# phase_footer with box borders
# phase_footer() {
    # separator_box "─" "" "top"
    # printf '  %b%s%b  \n' "${LOG_INFO}" "$*" "${NC}" >&2
    # separator_box "─" "" "bottom"
# }
export -f phase_footer

dl_result_line() {
    local status="$1" name="$2" hash="$3" extra="$4"
    local icon
    case "$status" in
        hit)  icon="✔" ; color="$LOG_INFO"  ;;
        miss) icon="🡇" ; color="$LOG_WARN"  ;;
        skip) icon="—" ; color="$LOG_DEBUG" ;;
        fail) icon="✖" ; color="$LOG_ERROR" ;;
        *)    icon="?" ; color="$NC"    ;;
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
        08|11|12|42)            echo "Compression & Runtime" ;; # Zlib, Zstd, FFI
        15|16)                  echo "Base Integration" ;; # Glib, XML2
        18)                     echo "Hardware Integration" ;; # cdio
        19|20|21|22)            echo "Low-level X-Graphics & DRM" ;; # xproto, libdrm
        23|24)                  echo "X11 Core" ;; # libxau, libx11
        25)                     echo "X11 Extensions" ;; # libxext, libxrender
        26|27)                  echo "OpenGL & Display Drivers" ;; # libglvnd, libxrandr
        30|31|32|33|34)         echo "Net" ;; # OpenSSL, Curl
 14|17|37|38|39|40|41|43|45|46) echo "Core Graphics & Fonts" ;; # PNG, Cairo
        47)                     echo "Subtitles & Teletext" ;; # libass, zvbi
        48)                     echo "QR-Codes" ;; # quirc, qrencode
        49|50|51|52|53)         echo "Vulkan & Shaders" ;; # SPIR-V, Glslang
        54|55|56|66)            echo "Hardware Acceleration API" ;; # VMAF
        57)                     echo "Video Capture" ;; # Decklink, libklvanc
        58|59|60|61|62)         echo "Compute & Vision" ;; # OpenVINO, OpenCV
        63|64|65|67|68)         echo "Audio API & Codecs" ;; #
        69)                     echo "Speech Recognition" ;; # Flite, Whisper
        44|70|71|72|73|74)      echo "Software Codecs" ;; # x264, x265
        80|81|82|83|84)         echo "Frameservers & Filtering" ;; # Vapoursynth, OpenAL
        51|85|86|87|88|89)      echo "Video Extensions" ;; # Libglvnd, Xrandr
        96|97|98)               echo "LV2 & Plugins" ;; # Serd, Sord, Lilv
        99|zz)                  echo "Meta & Finalize" ;;
        *)                      echo "Other" ;;
    esac
}
export -f get_component_group

# Render download results table with box borders
render_dl_table() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local width=$(_term_width)
    local inner_width=$(( width - 4 ))

    # Top border with label
    separator_box "─" "DOWNLOAD SUMMARY" "top"

    # Header row
    printf '  %-30s  %-16s  %s\n' "COMPONENT" "HASH" "RESULT" >&2

    # Header separator
    separator_box "─" "" "mid"

    local current_group=""
    while IFS=$'\t' read -r status icon name hash extra; do
        local group=$(get_component_group "$name")

        if [[ "$group" != "$current_group" ]]; then
            if [[ -n "$current_group" ]]; then
                # Close previous group
                printf '  %b╰%s%b\n' "${LOG_DEBUG}" "$(_repeat_char "$inner_width" "-")" "${NC}" >&2
            fi
            # Open new group
            local group_label="─[ $group ]"
            local remain=$(( inner_width - ${#group_label} ))
            [[ $remain -lt 0 ]] && remain=0
            printf '  %b╭%s%s%b\n' "${LOG_DEBUG}" "$group_label" "$(_repeat_char "$remain" "-")" "${NC}" >&2
            current_group="$group"
        fi

        local color
        case "$status" in
            hit)  color="${LOG_INFO}"  ;;
            miss) color="${LOG_WARN}"  ;;
            skip) color="${LOG_DEBUG}" ;;
            fail) color="${LOG_ERROR}" ;;
            *)    color="${NC}"    ;;
        esac

        printf '  %b│%b ' "${LOG_DEBUG}" "${NC}" >&2
        # printf '%b' "$color" >&2
        printf '%b%-28s  %-16s  %s%b\n' "$color" "$name" "$hash" "$extra" "${NC}" >&2
        # printf '%b\n' "$NC" >&2

    # This sorts by status (hit/miss/skip/fail)
    # sort -t$'\t' -k1,1 "$file"
    # sort by name (field 3)
    # sort -t$'\t' -k3,3 "$file"
    done < <(sort -t$'\t' -k3,3 "$file")

    if [[ -n "$current_group" ]]; then
        # Close final group
        printf '  %b╰%s%b\n' "${LOG_DEBUG}" "$(_repeat_char "$inner_width" "-")" "${NC}" >&2
    fi

    # Bottom border
    separator_box "─" "" "bottom"

    # Summary line
    local n_hit=$(tr -d '\r' < "$file" | grep -c '^hit' || true)
    local n_miss=$(tr -d '\r' < "$file" | grep -c '^miss' || true)
    local n_skip=$(tr -d '\r' < "$file" | grep -c '^skip' || true)
    local n_fail=$(tr -d '\r' < "$file" | grep -c '^fail' || true)

    printf '  %b✔ %s%b hit   %b🡇 %s%b downloaded   %b— %s%b skipped   %b✖ %s%b failed\n' \
        "${LOG_INFO}"  "${n_hit:-0}"  "${NC}" \
        "${LOG_WARN}"  "${n_miss:-0}" "${NC}" \
        "${LOG_DEBUG}" "${n_skip:-0}" "${NC}" \
        "${LOG_ERROR}" "${n_fail:-0}" "${NC}" >&2
}
export -f render_dl_table
