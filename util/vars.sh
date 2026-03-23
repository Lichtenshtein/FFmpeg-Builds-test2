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

# Argument resolution: prefer positional args, fall back to environment. приоритет аргументам, иначе берем из ENV
TARGET="${1:-$TARGET}"
VARIANT="${2:-$VARIANT}"

# Validate TARGET and VARIANT only enforce when called directly OR when
# arguments were explicitly passed (sourced scripts may not pass args)
if [[ "${BASH_SOURCE}" == "${0}" ]] || [[ $# -ge 2 ]]; then
    if [[ -z "$TARGET" || -z "$VARIANT" ]]; then
        log_error "${CROSS_MARK} Missing TARGET or VARIANT. Usage: source vars.sh [target] [variant]"
        return 1 2>/dev/null || exit 1
    fi
fi

# Shift positional args only if they were passed
if [[ $# -ge 2 ]]; then shift 2; fi

# Validate variant file exists (only if TARGET and VARIANT are known)
if [[ -n "$TARGET" && -n "$VARIANT" ]]; then
    if ! [[ -f "variants/${TARGET}-${VARIANT}.sh" ]]; then
        log_error "${CROSS_MARK} Invalid target/variant: ${TARGET}-${VARIANT}"
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
# use env vars with broadwell fallback
export CPU_ARCH="${CPU_ARCH:-broadwell}"
export CPU_TUNE="${CPU_TUNE:-broadwell}"
export FFBUILD_PREFIX="/opt/ffbuild"
export PKG_CONFIG_PATH="" # don't touch
export PKG_CONFIG_FLAGS="--static"
export PKG_CONFIG_LIBDIR="/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig:/opt/ffbuild/lib64/pkgconfig"
export PC_DIR="/opt/ffdest/opt/ffbuild/lib/pkgconfig"
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=0
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=0

BASE_CFLAGS="-mms-bitfields -fstack-protector-strong"
BASE_CPPFLAGS="-D__USE_MINGW_ANSI_STDIO=1 -U_WIN32_WINNT -D_WIN32_WINNT=0x0A00 -D_WIN32 -D_FORTIFY_SOURCE=2"
SYSTEM_LIBS="-lsetupapi -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lws2_32 -lbcrypt -lpthread"

# Флаги для стадии сборки компонентов; disable -fPIC, -ffast-math, -flto=auto if troubles occur
export CFLAGS="-march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe $BASE_CFLAGS -std=c11"
export CPPFLAGS="-I/opt/ffbuild/include $BASE_CPPFLAGS"
export CXXFLAGS="-march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe $BASE_CFLAGS -lstdc++"
export LDFLAGS="-Wl,-Bstatic -static -static-libgcc -static-libstdc++ -L/opt/ffbuild/lib -pipe -Wl,--high-entropy-va -Wl,--nxcompat -Wl,--dynamicbase -Wl,--reduce-memory-overheads -Wl,--stack,16777216"
export LIBS="${LIBS:-$SYSTEM_LIBS}"

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

# собирают флаги от всех скриптов в scripts.d для финального ./configure
ffbuild_enabled()      { return 0; }
ffbuild_depends()      { echo base; }
ffbuild_configure()    { 
    if [[ -n "$*" ]]; then
        export FF_CONFIGURE="$FF_CONFIGURE $*"
    else
        return 0 
    fi
}
ffbuild_cflags()       { [[ -n "$*" ]] && export FF_CFLAGS="$FF_CFLAGS $*"; }
ffbuild_cppflags()     { [[ -n "$*" ]] && export FF_CPPFLAGS="$FF_CPPFLAGS $*"; }
ffbuild_cxxflags()     { [[ -n "$*" ]] && export FF_CXXFLAGS="$FF_CXXFLAGS $*"; }
ffbuild_ldflags()      { [[ -n "$*" ]] && export FF_LDFLAGS="$FF_LDFLAGS $*"; }
ffbuild_ldexeflags()   { [[ -n "$*" ]] && export FF_LDEXEFLAGS="$FF_LDEXEFLAGS $*"; }
ffbuild_libs()         { [[ -n "$*" ]] && export FF_LIBS="$FF_LIBS $*"; }
ffbuild_uncflags()     { return 0; }
ffbuild_unconfigure()  { return 0; }
ffbuild_uncxxflags()   { return 0; }
ffbuild_unldexeflags() { return 0; }
ffbuild_unldflags()    { return 0; }
ffbuild_unlibs()       { return 0; }

# Экспортируем функции, чтобы они были доступны внутри run_stage и других подпроцессов
export -f ffbuild_enabled ffbuild_depends ffbuild_configure ffbuild_cflags ffbuild_cppflags ffbuild_cxxflags ffbuild_ldflags ffbuild_ldexeflags ffbuild_libs ffbuild_unconfigure ffbuild_uncflags ffbuild_uncxxflags ffbuild_unldexeflags ffbuild_unldflags ffbuild_unlibs

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

patch_pc_files() {
    log_info "${TARGET_MARK} Patching $STAGENAME .pc files..."
    local pc_dir="$PC_DIR"
    [[ -d "$pc_dir" ]] || return 0

    # Определяем корень исходников (для поиска конфигов билд-систем)
    local src_root="."
    if [[ -f "../configure.ac" || -f "../meson.build" || -f "../CMakeLists.txt" ]]; then
        src_root=".."
    elif [[ -f "../../configure.ac" || -f "../../meson.build" || -f "../../CMakeLists.txt" ]]; then
        src_root="../.."
    fi

    # Список библиотек, которые сканер будет искать в конфигах
    local scan_candidates="zstd lzma bz2 webp openjp2 jpeg tiff png zlib brotli iconv lcms2 jbig"

    # замена абсолютных путей на переменные
    find "$pc_dir" -name "*.pc" | while read -r pc; do
        log_debug "Fixing paths in $pc"

        # Удаляем все строки, которые определяют стандартные переменные путей,
        # чтобы избежать рекурсии типа libdir=${libdir}
        sed -i '/^prefix=/d; /^exec_prefix=/d; /^libdir=/d; /^includedir=/d; /^bindir=/d' "$pc"

        # Вставляем эталонные определения в самое начало файла
        # Используем жесткий префикс /opt/ffbuild, так как это стандарт для Docker
        sed -i '1i prefix=/opt/ffbuild\nexec_prefix=${prefix}\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\nbindir=${prefix}/bin' "$pc"

        # Заменяем абсолютные пути на переменные только в строках, НЕ являющихся определениями (где нет '='). Это защитит наши вставленные в пункте 2 строки от порчи.
        sed -i '/=/! s|'"$FFBUILD_PREFIX"'/include|${includedir}|g' "$pc"
        sed -i '/=/! s|'"$FFBUILD_PREFIX"'/lib|${libdir}|g' "$pc"
        sed -i '/=/! s|'"$FFBUILD_PREFIX"'|${prefix}|g' "$pc"

        # сканер зависимостей (Autotools, CMake, Meson)
        local extra_found=""
        for lib in $scan_candidates; do
        # Если .pc файл для этой либы уже существует в нашем префиксе
            local pc_exists=false
            if [[ -f "$FFBUILD_PREFIX/lib/pkgconfig/${lib}.pc" ]] || \
               [[ -f "$FFBUILD_PREFIX/lib/pkgconfig/lib${lib}.pc" ]] || \
               [[ -f "$FFBUILD_PREFIX/share/pkgconfig/${lib}.pc" ]]; then
                pc_exists=true
            fi

            if [[ "$pc_exists" == "true" ]]; then
            # Ищем признаки включения в разных билд-системах:
            # - Autotools: HAVE_LIB... или config.h
            # - CMake: Find... или CM_HAS_...
            # - Meson: found: true или meson-info
                if grep -rqiE "(have_lib|#define.*HAVE_LIB|found.*|find_package.*)${lib}.*(yes|1|true|found)" "$src_root" \
                    --include="config.*" --include="*.ac" --include="*.cmake" --include="CMakeLists.txt" \
                    --include="meson.build" --include="*.meson" --max-count=1 2>/dev/null; then
                    case "$lib" in
                        zlib)   extra_found+="-lz " ;;
                        bz2)    extra_found+="-lbz2 " ;;
                        iconv)  extra_found+="-liconv " ;;
                        jpeg)   extra_found+="-ljpeg " ;;
                        *)      local clean_name="${lib#lib}"
                                extra_found+="-l${clean_name} " ;;
                    esac
                fi
            fi
        done

        # Гарантируем наличие Libs.private
        if ! grep -q "^Libs.private:" "$pc"; then
            sed -i "/^Libs:/ a Libs.private:" "$pc"
        fi

        # Вливаем найденное сканером и системные $LIBS (из vars.sh)
        sed -i "/^Libs.private:/ s/$/ $extra_found $LIBS/" "$pc"

        # Умная дедупликация. Собираем всё, что уже есть в публичных полях, чтобы не дублировать это в private
        local public_stuff=$(grep -E "^(Libs|Requires|Requires.private):" "$pc" | cut -d':' -f2- | tr ',' ' ' | awk '{for(i=1;i<=NF;i++) print $i}')
        local priv_line=$(grep "^Libs.private:" "$pc" | cut -d':' -f2-)
        local new_priv=$(echo "$priv_line" | awk -v pub="$public_stuff" '
            BEGIN { split(pub, p, " ") }
            {
                for(i=1;i<=NF;i++) {
                    is_dup=0;
                    for(j in p) if($i == p[j]) is_dup=1;
                    if(!is_dup && !seen[$i]++) printf "%s ", $i
                }
                print ""
            }
        ')
        sed -i "s|^Libs.private:.*|Libs.private: $new_priv|" "$pc"

        # Чистим лишние пробелы в конце и между флагами
        sed -i 's/[[:space:]]*$//; s/  */ /g' "$pc"
    done
}
export -f patch_pc_files

get_deps_list() {
    set +o pipefail 
    if [[ "$FFBUILD_VERBOSE" != "1" ]]; then
        return 0
    fi
    local name="${STAGENAME:-${0##*/}}"
    local lib_dir="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib"
    local bin_dir="$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin"
    local sys_libs="libc\.so|libm\.so|libdl\.so|librt\.so|libpthread\.so|libgcc_s\.so|libstdc\+\+\.so|ld-linux|libresolv\.so|libutil\.so"

    log_info "################################################################"
    log_debug "Showing dependencies for: $name"

    if [[ -d "$lib_dir/pkgconfig" ]]; then
        find "$lib_dir/pkgconfig" -name "*.pc" -exec bash -c '
            pc_file="$1"; shift
            pkg_config_cmd="$1"; shift
            xclam_mark="$1"; shift
            search_mark="$1"; shift
            local current_lib_dir="$5"
            export PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR:$lib_dir/pkgconfig"
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
                        echo "MISSING DEPENDENCY: $pkg_name (Searched in: $PKG_CONFIG_LIBDIR)"
                    fi
                done <<< "$deps"
            else
                echo "No dependencies found."
            fi
        ' _ {} "${PKG_CONFIG:-pkg-config}" "$XCLAM_MARK" "$SEARCH_MARK" "$lib_dir" \; || true
    fi
    find "$lib_dir" "$bin_dir" -type f \( -name "*.so*" -o -name "*.exe" -o -name "*.dll" \) -print0 2>/dev/null | \
    xargs -0 -r -I{} bash -c '
        file="$1"; shift
        toolchain_prefix="$1"; shift
        sys_libs_regex="$1"; shift
        xclam_mark="$1"; shift

        if "${toolchain_prefix}-readelf" -h "$file" &>/dev/null; then
            raw_deps=$("${toolchain_prefix}-readelf" -d "$file" 2>/dev/null | awk "/NEEDED/ { gsub(/.*\[|\]/, \"\"); print }")
            clean_deps=$(echo "$raw_deps" | awk "!/$sys_libs_regex/")
            if [[ -n "$clean_deps" ]]; then
                printf "\n%b NEEDED LIBRARIES for %s:\n%s\n" "$xclam_mark" "$file" "$clean_deps"
            fi
        fi
    ' _ {} "$FFBUILD_TOOLCHAIN" "$sys_libs" "$XCLAM_MARK" || true
    find "$lib_dir" -name "*.a" -print0 2>/dev/null | \
    xargs -0 -r -I{} bash -c '
        file="$1"; shift
        toolchain_prefix="$1"; shift
        xclam_mark="$1"; shift

        if "${toolchain_prefix}-nm" -u "$file" &>/dev/null; then
            printf "\n%b EXTERNAL SYMBOLS (TOP 10) in %s:\n" "$xclam_mark" "$file"
            # Using double backslash for awk to escape $ inside single-quoted bash -c
            "${toolchain_prefix}-nm" -u "$file" 2>/dev/null | \
            awk "!/^[[:space:]]*$/ && !/@@/ && !/__imp_/" | sort -u | head -n 10
        fi
    ' _ {} "$FFBUILD_TOOLCHAIN" "$XCLAM_MARK" || true
    { find "$lib_dir" "$bin_dir" -type f \( -name "*.so*" -o -executable \) -print0 2>/dev/null | xargs -0 -r -I{} bash -c "
        set +o pipefail
        if \"\${FFBUILD_TOOLCHAIN}-readelf\" -h \"\$1\" &>/dev/null; then
            log_debug \"\n\$XCLAM_MARK RPATH/RUNPATH for \$1:\"
            \"\${FFBUILD_TOOLCHAIN}-objdump\" -p \"\$1\" 2>/dev/null | awk '/RPATH|RUNPATH/ {print}' || true
        fi
        exit 0
    " _ {} ; } || true
}
export -f get_deps_list

clean_la_files() {
    local target_dir="$FFBUILD_DESTDIR$FFBUILD_PREFIX"
    [[ ! -d "$target_dir" ]] && return 0
    log_debug "${BROOM_MARK} Cleaning up libtool archives (.la) in $target_dir"
    if find "$target_dir" -name "*.la" -type f -print -quit | grep -q .; then
        local count=$(find "$target_dir" -name "*.la" -type f | wc -l 2>/dev/null || true)
        find "$target_dir" -name "*.la" -type f -delete 2>/dev/null || true
        log_info "${CHECK_MARK} Removed $count .la files from prefix."
    else
        log_debug "${CHECK_MARK} No .la files found to clean."
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

# .la files, dependancies and .pc files auditing
# add ffbuild_dockerbuild() { export SKIP_POST_PATCH=1 } to disable
# export SKIP_POST_PATCH=0
# export SKIP_POST_CLEAN=0
# export SKIP_POST_AUDIT=0

# Динамическое определение путей тулчейна
# Ищем, где реально лежат заголовочные файлы и либы mingw в образе
# /opt/ct-ng/x86_64-w64-mingw32/sysroot/usr/x86_64-w64-mingw32/bin/
# Проверяем, находимся ли мы внутри Docker (где есть тулчейн)
if [ -d "/opt/ct-ng" ]; then
    MINGW_BIN_PATH=$(find /opt/ct-ng -maxdepth 5 -type d -name "bin" | grep "x86_64-w64-mingw32/bin" | head -n 1)
    if command -v winepath &>/dev/null; then
        # Suppress ALL winepath output including Wine debug messages
        _p_bin=$(winepath -w "${FFBUILD_PREFIX}/bin" 2>/dev/null | tr -d '\r\n')
        _p_lib=$(winepath -w "${FFBUILD_PREFIX}/lib" 2>/dev/null | tr -d '\r\n')
        _m_bin=$(winepath -w "${MINGW_BIN_PATH}" 2>/dev/null | tr -d '\r\n')
        # Validate results before using them
        if [[ -n "$_p_bin" && -n "$_p_lib" ]]; then
            export WINEPATH="${_p_bin};${_p_lib};${_m_bin}"
        else
        # We are on the GitHub Host (generate/download phase)
            export WINEPATH="winepath -w ${FFBUILD_PREFIX}/bin:${FFBUILD_PREFIX}/lib:${MINGW_BIN_PATH}"
        fi
        printf '%b WINEPATH (Windows style): %s\n' "${DIRS_MARK}" "$WINEPATH"
    else
        export WINEPATH="winepath -w ${FFBUILD_PREFIX}/bin:${FFBUILD_PREFIX}/lib:${MINGW_BIN_PATH}"
    fi
fi

# Определяем режим работы Wine (берем из ENV или ставим auto по умолчанию)
USE_WINE="${USE_WINE:-auto}"
WINE_CMD=$(command -v wine64 || command -v wine)
# Функция для принятия решения о запуске графического окружения и Wine
# Detect if the script needs a display (Wine, Meson, CMake tests)
should_run_wine() {
    [[ "$USE_WINE" == "on" ]] && return 0
    [[ "$USE_WINE" == "off" ]] && return 1
    grep -qE "meson setup|cmake|\./configure|wine" "$SCRIPT_PATH"
}
export -f should_run_wine

# Wrapper function to execute commands
wine_run_wrapped() {
    if should_run_wine; then
        # -n 99: use display 99
        # -s: Xvfb arguments
        # -a: auto-servernum (use next available if 99 is busy)
        log_info "${START_MARK} Starting Xvfb (Display :99) for Wine/Build tests..."
        xvfb-run -n 99 -a -s "-screen 0 1024x768x16" bash -c "
            . /builder/util/vars.sh '$TARGET' '$VARIANT'
            . '$SCRIPT_PATH'
            $cmd
        "
    else
         log_debug "Stage $STAGENAME: Wine/Xvfb initialization skipped (Mode: $USE_WINE)."
        "$@"
    fi
}
export -f wine_run_wrapped

# экспорт важных переменных MinGW, чтобы они пробрасывались в download.sh и run_stage.sh:
export TARGET VARIANT REPO REGISTRY BASE_IMAGE TARGET_IMAGE IMAGE
