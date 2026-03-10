#!/bin/bash

set -o pipefail

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
log_warn()  { echo -e "${LOG_WARN}[WARN]${LOG_NC}  $*" >&2; }
log_error() { echo -e "${LOG_ERROR}[ERROR]${LOG_NC} $*" >&2; }
log_debug() { echo -e "${LOG_DEBUG}[DEBUG]${LOG_NC} $*" >&2; }

export -f log_info log_warn log_error log_debug

export PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"

export PKG_CONFIG_LIBDIR="/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig"
unset PKG_CONFIG_SYSROOT_DIR
export PKG_CONFIG_STATIC=1
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=0
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=0

BASE_CFLAGS="-U_WIN32_WINNT -D_WIN32_WINNT=0x0A00 -D_WIN32 -mms-bitfields"
BASE_CPPFLAGS="-U_WIN32_WINNT -D_WIN32_WINNT=0x0A00 -D_WIN32"
SYSTEM_LIBS="-lsetupapi -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lws2_32 -lbcrypt -lssp -pthread -lstdc++"
export LIBS="$SYSTEM_LIBS"
export CFLAGS="-O3 -march=broadwell -mtune=broadwell -mfpmath=sse -D_FORTIFY_SOURCE=2 $BASE_CFLAGS -I$FFBUILD_PREFIX/include -pipe -fstack-protector-strong -std=gnu11"
export CPPFLAGS="$BASE_CPPFLAGS"
export CXXFLAGS="-O3 -march=broadwell -mtune=broadwell -mfpmath=sse -D_FORTIFY_SOURCE=2 $BASE_CFLAGS -I$FFBUILD_PREFIX/include -pipe -fstack-protector-strong -std=c++17"
export LDFLAGS="-O3 -static-libgcc -static-libstdc++ -L$FFBUILD_PREFIX/lib -pthread -Wl,--high-entropy-va -Wl,--nxcompat -Wl,--dynamicbase -Wl,--reduce-memory-overheads -Wl,--stack,16777216"
export STAGE_CFLAGS="-fno-semantic-interposition"
export STAGE_CXXFLAGS="-fno-semantic-interposition"


# disable -fPIC, -ffast-math, -flto=auto if troubles occur
# add -D_FORTIFY_SOURCE=2 for security
# --as-needed is dangerous for static linking: when linking static libraries for Windows, if the linker sees a library before a symbol is requested, it will discard it.
# LDFLAGS="-lssp" is it needed?
# -Wl,--gc-sections, because of it the linker may throw out what it considers "unnecessary" sections from static libraries if dependencies are specified in the wrong order in .pc files
# Stable:
# CFLAGS="-O2 -march=x86-64-v3 -mtune=generic -D_FORTIFY_SOURCE=2 -static-libgcc -static-libstdc++ -I/opt/ffbuild/include -pipe"


if [[ $# -lt 2 ]]; then
    log_error "${CROSS_MARK} Invalid Arguments"
    # exit -1
    return 1 2>/dev/null || exit 1
fi

# Улучшенная проверка: приоритет аргументам, иначе берем из ENV
TARGET="${1:-$TARGET}"
VARIANT="${2:-$VARIANT}"

# Валидация: если ни аргументов, ни переменных нет — тогда ошибка
if [[ -z "$TARGET" || -z "$VARIANT" ]]; then
    log_error "${CROSS_MARK} Missing TARGET or VARIANT. Usage: source vars.sh [target] [variant]"
    # Не используем exit -1, чтобы не закрывать сессию терминала при source
    return 1 2>/dev/null || exit 1
fi

# Сдвигаем аргументы только если они были переданы
if [[ $# -ge 2 ]]; then
    shift 2
fi

# Проверка файла варианта
if ! [[ -f "variants/${TARGET}-${VARIANT}.sh" ]]; then
    log_error "${CROSS_MARK} Invalid target/variant: ${TARGET}-${VARIANT}"
    return 1 2>/dev/null || exit 1
fi

LICENSE_FILE="COPYING.LGPLv2.1"

ADDINS=()
ADDINS_STR=""
while [[ "$#" -gt 0 ]]; do
    # Проверяем, существует ли файл в addins
    if [[ -f "addins/${1}.sh" ]]; then
        ADDINS+=( "$1" )
        ADDINS_STR="${ADDINS_STR}${ADDINS_STR:+-}$1"
    else
        # Если файла нет, просто пропускаем (это может быть lto или skip_ffmpeg)
        log_warn "${XCLAM_MARK} Note: Argument '$1' is not a valid addin, ignoring."
    fi
    shift
done

REPO="${GITHUB_REPOSITORY:-lichtenshtein/ffmpeg-build}"
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
    echo "-D_WIN32_WINNT=0x0A00 -D_WIN32 -mms-bitfields"
}

ffbuild_uncflags() {
    return 0
}

ffbuild_cxxflags() {
    log_debug "Applying global CXXFLAGS for $STAGENAME" >&2
    # глобальный макрос для всех, кто включает заголовки
    echo "-std=c++17 -D_WIN32_WINNT=0x0A00 -D_WIN32"
}

ffbuild_cppflags() {
    log_debug "Applying global CPPFLAGS for $STAGENAME" >&2
    # глобальный макрос для всех, кто включает заголовки
    echo "-D_WIN32_WINNT=0x0A00 -D_WIN32"
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
    echo "-lsetupapi -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lstdc++ -lws2_32 -lbcrypt -pthread"
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
# export FFBUILD_VERBOSE=${FFBUILD_VERBOSE:-1}
# Значение FFBUILD_VERBOSE уже пришло из Docker ENV
if [[ "$FFBUILD_VERBOSE" == "1" ]]; then
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

get_deps_list() {
    if [[ "$FFBUILD_VERBOSE" != "1" ]]; then
        return 0
    fi
    log_info "################################################################"
    local name="${STAGENAME:-${0##*/}}"
    local lib_dir="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib"
    local bin_dir="$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin"
    log_debug "Showing dependencies for: $name"
    local sys_libs="libc\.so|libm\.so|libdl\.so|librt\.so|libpthread\.so|libgcc_s\.so|libstdc\+\+\.so|ld-linux|libresolv\.so|libutil\.so"

    if [[ -d "$lib_dir/pkgconfig" ]]; then
        find "$lib_dir/pkgconfig" -name "*.pc" -exec bash -c '
            set +e 
            printf "\n%b %s\n" "$XCLAM_MARK" "$1"
            cat "$1"
            printf "\n%b DEPS for %s:\n" "$SEARCH_MARK" "${1##*/}"
            deps=$(pkg-config --print-requires --print-requires-private "$1" 2>/dev/null || true)
            if [[ -n "$deps" ]]; then
                echo "$deps"
                for d in $deps; do
                    if ! pkg-config --exists "$d" 2>/dev/null; then
                        log_error "MISSING DEPENDENCY: $d (required by $1)"
                    fi
                done
            else
                echo "No dependencies found."
            fi
            exit 0
        ' _ {} \; || true
    fi
    find "$lib_dir" "$bin_dir" -type f \( -name "*.so*" -o -executable \) -print0 2>/dev/null | xargs -0 -I{} bash -c "
        if \"\${FFBUILD_TOOLCHAIN}-readelf\" -h \"\$1\" &>/dev/null; then
            raw_deps=\$(\"\${FFBUILD_TOOLCHAIN}-readelf\" -d \"\$1\" | grep 'NEEDED' | sed -E 's/.*\[(.*)\].*/\1/' || true)
            clean_deps=\$(echo \"\$raw_deps\" | grep -vE \"$sys_libs\")
            if [[ -n \"\$clean_deps\" ]]; then
                log_debug \"\n\$XCLAM_MARK NEEDED LIBRARIES for \$1:\"
                echo \"\$clean_deps\"
                for lib in \$clean_deps; do
                    if [[ ! -f \"$lib_dir/\$lib\" ]]; then
                         log_error \"BROKEN LINK: \$lib not found in $lib_dir (needed by \$1)\"
                    fi
                done
            fi
        fi
    " _ {}
    find "$lib_dir" -name "*.a" -print0 2>/dev/null | xargs -0 -I{} bash -c '
        log_debug "\n$XCLAM_MARK EXTERNAL SYMBOLS (TOP 10) in $1:"
        "${FFBUILD_TOOLCHAIN}-nm" -u "$1" 2>/dev/null | grep -v "@@" | sort -u | head -n 10
    ' _ {}
    find "$lib_dir" "$bin_dir" -type f -executable -print0 2>/dev/null | xargs -0 -I{} bash -c "
        if \"\${FFBUILD_TOOLCHAIN}-readelf\" -h \"\$1\" &>/dev/null; then
            log_debug \"\n\$XCLAM_MARK RPATH/RUNPATH for \$1:\"
            \"\${FFBUILD_TOOLCHAIN}-objdump\" -p \"\$1\" | grep -E 'RPATH|RUNPATH' || true
        fi
    " _ {}
}
export -f get_deps_list

clean_la_files() {
    local target_dir="$FFBUILD_DESTDIR$FFBUILD_PREFIX"
    # Проверяем, существует ли вообще директория префикса
    if [[ ! -d "$target_dir" ]]; then
        return 0
    fi
    log_debug "Cleaning up libtool archives (.la) in $target_dir"
    # Используем find с проверкой на наличие файлов, чтобы не выводить ошибки, если их нет
    if find "$target_dir" -name "*.la" -type f -print -quit | grep -q .; then
        local count=$(find "$target_dir" -name "*.la" -type f | wc -l)
        find "$target_dir" -name "*.la" -type f -delete
        log_info "${BROOM_MARK} Removed $count .la files from prefix."
    else
        log_debug "No .la files found to clean."
    fi
}
export -f clean_la_files

# 1. Standard
# 2. Binary (for CRLF issues)
# 3. Ignore Whitespace
# 4. Max Fuzz (fuzz=3)
apply_patches() {
    local COMPONENT_NAME=$(echo "$STAGENAME" | sed 's/^[0-9]*-//')
    local PATCH_DIR="/builder/patches/$COMPONENT_NAME"

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
                log_error "${CROSS_MARK} FAILED: All attempts to apply $(basename "$patch") failed."
                # return 1 # не прерывать сборку при ошибках
            fi
        done
        shopt -u nullglob
    else
        log_debug "${XCLAM_MARK} No patches found for $COMPONENT_NAME"
    fi
}
export -f apply_patches

# Динамическое определение путей тулчейна
# Ищем, где реально лежат заголовочные файлы и либы mingw в образе
# /opt/ct-ng/x86_64-w64-mingw32/sysroot/usr/x86_64-w64-mingw32/bin/
# Проверяем, находимся ли мы внутри Docker (где есть тулчейн)
if [ -d "/opt/ct-ng" ]; then
    MINGW_BIN_PATH=$(find /opt/ct-ng -maxdepth 5 -type d -name "bin" | grep "x86_64-w64-mingw32/bin" | head -n 1)
    if [ -n "$MINGW_BIN_PATH" ]; then
        export WINEPATH="${MINGW_BIN_PATH};${FFBUILD_PREFIX}/bin;${FFBUILD_PREFIX}/lib"
        log_info "${DIRS_MARK} WINEPATH unified to: $WINEPATH"
    else
        log_warn "${XCLAM_MARK} Could not find MinGW BIN directory for WINEPATH"
    fi
else
    # Если мы на хосте (этап генерации/загрузки), просто игнорируем тулчейн
    log_debug "Running outside of build container, skipping toolchain path discovery."
fi

# экспорт важных переменных MinGW, чтобы они пробрасывались в download.sh и run_stage.sh:
export TARGET VARIANT REPO REGISTRY BASE_IMAGE TARGET_IMAGE IMAGE
