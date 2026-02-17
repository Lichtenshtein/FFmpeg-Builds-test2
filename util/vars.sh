#!/bin/bash

# ANSI Color Codes
export LOG_DEBUG='\033[1;35m'  # Purple (Bold)
export LOG_INFO='\033[1;32m'   # Green (Bold)
export LOG_WARN='\033[1;33m'   # Yellow (Bold)
export LOG_ERROR='\033[1;31m'  # Red (Bold)
export LOG_NC='\033[0m'        # No Color (Reset)
export RED='\033[0;31m'        # Red
export GREEN='\033[0;32m'      # Green
export NC='\033[0m'            # No Color (Reset)
export CHECK_MARK='✅'
export CROSS_MARK='❌'

# Функции для логирования пишут в stderr (>&2)
log_info()  { echo -e "${LOG_INFO}[INFO]${LOG_NC}  $*" >&2; }
log_warn()  { echo -e "${LOG_WARN}[WARN]${LOG_NC}  $*" >&2; }
log_error() { echo -e "${LOG_ERROR}[ERROR]${LOG_NC} $*" >&2; }
log_debug() { echo -e "${LOG_DEBUG}[DEBUG]${LOG_NC} $*" >&2; }

export -f log_info log_warn log_error log_debug

if [[ $# -lt 2 ]]; then
    log_error "Invalid Arguments"
    exit -1
fi

# Улучшенная проверка: приоритет аргументам, иначе берем из ENV
TARGET="${1:-$TARGET}"
VARIANT="${2:-$VARIANT}"

# Валидация: если ни аргументов, ни переменных нет — тогда ошибка
if [[ -z "$TARGET" || -z "$VARIANT" ]]; then
    log_error "Missing TARGET or VARIANT. Usage: source vars.sh [target] [variant]"
    # Не используем exit -1, чтобы не закрывать сессию терминала при source
    return 1 2>/dev/null || exit 1
fi

# Сдвигаем аргументы только если они были переданы
if [[ $# -ge 2 ]]; then
    shift 2
fi

# Проверка файла варианта
if ! [[ -f "variants/${TARGET}-${VARIANT}.sh" ]]; then
    log_error "Invalid target/variant: ${TARGET}-${VARIANT}"
    return 1 2>/dev/null || exit 1
fi

LICENSE_FILE="COPYING.LGPLv2.1"

ADDINS=()
ADDINS_STR=""
while [[ "$#" -gt 0 ]]; do
    if ! [[ -f "addins/${1}.sh" ]]; then
        log_error "Invalid addin: $1"
        exit -1
    fi

    ADDINS+=( "$1" )
    ADDINS_STR="${ADDINS_STR}${ADDINS_STR:+-}$1"

    shift
done

REPO="${GITHUB_REPOSITORY}"
REPO="${REPO,,}"
REGISTRY="${REGISTRY_OVERRIDE:-ghcr.io}"
BASE_IMAGE="${REGISTRY}/${REPO}/base:latest"
TARGET_IMAGE="${REGISTRY}/${REPO}/base-${TARGET}:latest"
IMAGE="${REGISTRY}/${REPO}/${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}:latest"

ffbuild_ffver() {
    case "$ADDINS_STR" in
    *4.3*)
        echo 403
        ;;
    *4.4*)
        echo 404
        ;;
    *5.0*)
        echo 500
        ;;
    *5.1*)
        echo 501
        ;;
    *6.0*)
        echo 600
        ;;
    *6.1*)
        echo 601
        ;;
    *7.0*)
        echo 700
        ;;
    *7.1*)
        echo 701
        ;;
    *8.0*)
        echo 800
        ;;
    *)
        echo 99999999
        ;;
    esac
}


ffbuild_depends() {
    echo base
}

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

ffbuild_configure() {
    return 0
}

ffbuild_unconfigure() {
    return 0
}

ffbuild_cflags() {
    log_debug "Applying global CFLAGS for $STAGENAME" >&2
    # глобальный макрос для всех, кто включает заголовки glib
    echo "-DGLIB_STATIC_COMPILATION -mms-bitfields"
}

ffbuild_uncflags() {
    return 0
}

ffbuild_cxxflags() {
    return 0
}

ffbuild_uncxxflags() {
    return 0
}

ffbuild_ldexeflags() {
    return 0
}

ffbuild_unldexeflags() {
    return 0
}

ffbuild_ldflags() {
    return 0
}

ffbuild_unldflags() {
    return 0
}

ffbuild_libs() {
    log_debug "Adding system libraries for Win64" >&2
    # Только системные либы
    echo "-lsetupapi -lstdc++ -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lws2_32"
}

ffbuild_unlibs() {
    return 0
}
ffbuild_dockerdl() {
    if [[ -n "$SCRIPT_REPO" ]]; then
        default_dl .
    fi
}

ffbuild_enabled() {
    return 0
}

# 1 для подробных логов, в 0 для кратких
export FFBUILD_VERBOSE=${FFBUILD_VERBOSE:-1}

if [[ "$FFBUILD_VERBOSE" == "1" ]]; then
    export MAKE_V="V=1"
    export NINJA_V="-v"
    export CARGO_V="-v"
else
    export MAKE_V=""
    export NINJA_V=""
    export CARGO_V=""
fi

export FFBUILD_RUST_TARGET="x86_64-pc-windows-gnu"

# Конфигурация ccache
export CCACHE_DIR=/root/.cache/ccache
export CCACHE_MAXSIZE=20G
export CCACHE_SLOPPINESS="include_file_ctime,include_file_mtime,locale,time_macros,file_macro,pch_defines"
export CCACHE_BASEDIR="/builder"
export CCACHE_COMPILERCHECK="content"
export CCACHE_DEPEND="1"
export CCACHE_COMPRESS=1

# экспорт важных переменных MinGW, чтобы они пробрасывались в download.sh и run_stage.sh:
export TARGET VARIANT REPO REGISTRY BASE_IMAGE TARGET_IMAGE IMAGE
