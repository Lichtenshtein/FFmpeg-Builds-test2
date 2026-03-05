#!/bin/bash

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
export XCLAM_MARK='❗'
export BROOM_MARK='🧹'
export CACHE_MARK='🗄️'
export ARCH_MARK='🗃️'
export SEARCH_MARK='🔎'
export BUILD_MARK='🛠️'
export DIRS_MARK='📂'
export LOCK_MARK='🔒'
export SYNC_MARK="${LOG_INFO}♻{NC}"
export TARGET_MARK='🎯'
export DOWN_MARK="${LOG_INFO}🡇${NC}"
export LOGS_MARK="${LOG_DEBUG}🗎${NC}"

# Функции для логирования пишут в stderr (>&2)
log_info()  { echo -e "${LOG_INFO}[INFO]${LOG_NC}  $*" >&2; }
log_warn()  { echo -e "${LOG_WARN}[WARN]${LOG_NC}  $*" >&2; }
log_error() { echo -e "${LOG_ERROR}[ERROR]${LOG_NC} $*" >&2; }
log_debug() { echo -e "${LOG_DEBUG}[DEBUG]${LOG_NC} $*" >&2; }

export -f log_info log_warn log_error log_debug

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
    echo "-lsetupapi -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lstdc++ -lws2_32 -lbcrypt -lpthread"
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
            printf "\n%b PKG-CONFIG DEPS for %s:\n" "$XCLAM_MARK" "$1"
            deps=$(pkg-config --print-requires --print-requires-private "$1")
            echo "$deps"
            for d in $deps; do
                if ! pkg-config --exists "$d"; then
                    log_error "MISSING DEPENDENCY: $d (required by $1)"
                fi
            done
        ' _ {} \;
    fi
    find "$lib_dir" "$bin_dir" -type f \( -name "*.so*" -o -executable \) -print0 2>/dev/null | xargs -0 -I{} bash -c "
        if \"\${FFBUILD_TOOLCHAIN}-readelf\" -h \"\$1\" &>/dev/null; then
            raw_deps=\$(\"\${FFBUILD_TOOLCHAIN}-readelf\" -d \"\$1\" | grep 'NEEDED' | sed -E 's/.*\[(.*)\].*/\1/')
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

export FFBUILD_RUST_TARGET="x86_64-pc-windows-gnu"
export PKG_CONFIG_PATH="/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig"
export PKG_CONFIG_LIBDIR="/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig"
# Принудительно включаем статический поиск для pkg-config во всех под-скриптах
export PKG_CONFIG_STATIC=1

# Конфигурация ccache
export CCACHE_DIR=/root/.cache/ccache
export CCACHE_MAXSIZE=20G
export CCACHE_SLOPPINESS="include_file_ctime,include_file_mtime,locale,time_macros,file_macro,pch_defines"
export CCACHE_BASEDIR="/builder"
export CCACHE_COMPILERCHECK="content"
export CCACHE_DEPEND="1"
export CCACHE_COMPRESS=1
export CCACHE_NOHASHDIR=1

# Базовые настройки Wine
export WINEARCH=win64
export WINEPREFIX="/root/.wine"
export DISPLAY=:99
export WINEDEBUG=-all
export WINEDLLOVERRIDES="mscoree,mshtml=" # Отключаем попытки скачивания Mono/Gecko
# Пути к бинарникам Wine (Noble)
export WINE_BIN_DIR="/opt/wine-stable/bin"
export PATH="$WINE_BIN_DIR:${PATH}"
# Пути к библиотекам Wine (нужны для работы самого wine64)
export LD_LIBRARY_PATH="/opt/wine-stable/lib64:/opt/wine-stable/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
# Динамическое определение путей тулчейна
# Ищем, где реально лежат заголовочные файлы и либы mingw в вашем образе
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

# Явно задаем хост-систему для Autotools
export CHOST="$FFBUILD_TOOLCHAIN"

# Убеждаемся, что все инструменты имеют префикс
export CC="${FFBUILD_TOOLCHAIN}-gcc"
# Форсируем C++ рантайм для всех CC
# export CC="${FFBUILD_TOOLCHAIN}-g++"
export CXX="${FFBUILD_TOOLCHAIN}-g++"
export AR="${FFBUILD_TOOLCHAIN}-gcc-ar"
export NM="${FFBUILD_TOOLCHAIN}-gcc-nm"
export RANLIB="${FFBUILD_TOOLCHAIN}-gcc-ranlib"
export OBJDUMP="${FFBUILD_TOOLCHAIN}-objdump"
export STRIP="${FFBUILD_TOOLCHAIN}-strip"

# экспорт важных переменных MinGW, чтобы они пробрасывались в download.sh и run_stage.sh:
export TARGET VARIANT REPO REGISTRY BASE_IMAGE TARGET_IMAGE IMAGE

if [[ -z "$VARS_INFRA_APPLIED" ]]; then
    export VARS_INFRA_APPLIED=1

    # Получаем список системных либ
    SYSTEM_LIBS="-lsetupapi -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lws2_32 -lbcrypt -lpthread"
    export LIBS="$LIBS $SYSTEM_LIBS"
    BASE_CFLAGS="-D_WIN32_WINNT=0x0A00 -D_WIN32 -mms-bitfields"
    BASE_CPPFLAGS="-D_WIN32_WINNT=0x0A00 -D_WIN32"
    export CFLAGS="$CFLAGS $BASE_CFLAGS"
    export CPPFLAGS="$CPPFLAGS $BASE_CPPFLAGS"
    export CXXFLAGS="$CXXFLAGS -std=c++17"
    export LDFLAGS="$LDFLAGS"
fi

# "-DARCHIVE_STATIC -DBROTLI_STATIC -DCAIRO_WIN32_STATIC_BUILD -DCURL_STATICLIB -DGLIB_STATIC_COMPILATION -DHARFBUZZ_STATIC -DIB_STATIC -DICONV_STATIC -DLIBJPEG_STATIC -DLIBSSH_STATIC -DVAPOURSYNTH_STATIC -DLIBTIFF_STATIC -DLIBXML_STATIC -DPANGO_STATIC_COMPILATION -DWEBP_STATIC -DXML_STATIC -DZLIB_STATIC -DZSTD_STATIC_LINKING -D_WIN32 -D_WIN32_WINNT=0x0A00"