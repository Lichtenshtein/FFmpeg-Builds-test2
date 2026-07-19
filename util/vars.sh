#!/bin/bash

set -o pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# ANSI Color Codes
export LOG_DEBUG='\x1b[1;35m' # Purple (Bold)
export LOG_INFO='\x1b[1;32m'  # Green (Bold)
export LOG_WARN='\x1b[1;33m'  # Yellow (Bold)
export LOG_ERROR='\x1b[1;31m' # Red (Bold)
export CYAN_B='\x1b[1;36m'    # Cyan (Bold)
export GREY_B='\x1b[1;30m'    # Grey (Bold)
export BLUE_B='\x1b[1;34m'    # Blue (Bold)
export NC='\x1b[0m'           # No Color (Reset)
export RED='\x1b[0;31m'       # Red
export GREEN='\x1b[0;32m'     # Green
export YELLOW='\x1b[0;33m'    # Yellow
export BLUE='\x1b[0;34m'      # Blue
export PURPLE='\x1b[0;35m'    # Purple
export CYAN='\x1b[0;36m'      # Cyan

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
export LOGS_MARK='📝'
export STAT_MARK='📊'
export TEST_MARK='🧪'

# Logging functions write to stderr (>&2)
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

# Build variables (inside the container)
# Prefer positional args, fall back to ENV
export TARGET="${1:-$TARGET}"
export VARIANT="${2:-$VARIANT}"
# use env vars
export CPU_FAMILY="x86_64"
export CPU_ARCH="${CPU_ARCH:-x86-64-v3}"
export CPU_TUNE="${CPU_TUNE:-x86-64-v3}"
# Build variables (inside the container)
# just duplicate from Dockerfile for convenience
export TOOLCHAIN_BIN="/opt/ct-ng/bin"
export FFBUILD_RUST_TARGET="x86_64-pc-windows-gnu"
export FFBUILD_TOOLCHAIN="x86_64-w64-mingw32"
export FFBUILD_CROSS_PREFIX="x86_64-w64-mingw32-"
export CHOST="${FFBUILD_TOOLCHAIN}"
export STRIP="${FFBUILD_CROSS_PREFIX}strip"
export WINDRES="${FFBUILD_CROSS_PREFIX}windres"
export DLLTOOL="${FFBUILD_CROSS_PREFIX}dlltool"
export OBJDUMP="${FFBUILD_CROSS_PREFIX}objdump"
export OBJCOPY="${FFBUILD_CROSS_PREFIX}objcopy"
export GENDEF="${FFBUILD_CROSS_PREFIX}gendef"
export AS="${FFBUILD_CROSS_PREFIX}as"
export CC="${FFBUILD_CROSS_PREFIX}gcc"
export CXX="${FFBUILD_CROSS_PREFIX}g++"
# export LD="${FFBUILD_CROSS_PREFIX}gcc"
# export LD="${FFBUILD_CROSS_PREFIX}ld"
export LD="/usr/bin/ld.lld"
export HOST_LD="mold"
export TARGET_LD="lld" # or bfd

export FFBUILD_PREFIX="/opt/ffbuild" # persistent installed compoents storage
export FFBUILD_DESTDIR="/opt/ffdest"
export INSTALL_ROOT="${FFBUILD_DESTDIR}${FFBUILD_PREFIX}" # single less confusing source of truth
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
# * --libs                      — only -l and -L paths
# * --libs-only-l               — only -l (-lSdl2) WITHOUT -L paths
# * --libs-only-other           — only flags WITHOUT -l (-pthread)
# * --static --libs             — -L/opt/lib -lfftw3
# * --static --libs-only-l      — only -l from Libs + Libs.private
# * --static --libs-only-other  — any~ flags WITHOUT -L paths
# * --cflags                    — any~ flags WITH -I paths
# * --cflags-only-other         — only flags WITHOUT -I paths
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

export FFBUILD_TARGET_FLAGS="--pkg-config=${PKG_CONFIG} --cross-prefix=${FFBUILD_CROSS_PREFIX} --arch=${CPU_FAMILY} --target-os=mingw32"

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
export FFMPEG_HASH_FILE="${FFMPEG_DIR}/.current_commit" # hash of the last downloaded commit

# Container root is always /builder
export CONTAINER_ROOT="/builder"

# ---------------------------------------------------------------------------
# CACHE_DIR: always inside the project tree so host and container agree.
# The workflow mounts .cache/downloads → $CACHE_DIR, so the target must
# match what generate.sh writes into the Dockerfile --mount target.
# ---------------------------------------------------------------------------
export CACHE_DIR="${ROOT_DIR}/.cache/downloads"

# ccache
export PATH="/opt/ccache-links:${PATH}"
export CCACHE_PATH="/opt/ct-ng/bin:/usr/bin"
export CCACHE_DIR="${CCACHE_DIR:-/root/.cache/ccache}"
export CCACHE_BASEDIR="${CONTAINER_ROOT}"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-2G}"
export CCACHE_COMPILERCHECK="${CCACHE_COMPILERCHECK:-content}"
export CCACHE_DEPEND="${CCACHE_DEPEND:-1}"
export CCACHE_COMPRESS="${CCACHE_COMPRESS:-1}"
export CCACHE_COMPRESSLEVEL="${CCACHE_COMPRESSLEVEL:-6}"
export CCACHE_PATH_MGMT="${CCACHE_PATH_MGMT:-true}"
export CCACHE_NLEVELS="${CCACHE_NLEVELS:-4}"
export CCACHE_SLOPPINESS="${CCACHE_SLOPPINESS}"

# wine
if [[ "${USE_WINE:-0}" = "1" ]]; then
    export WINEARCH=win64
    export WINEPREFIX="/root/.wine"
    export DISPLAY=:99
    export WINEDEBUG=-all
    export WINEDLLOVERRIDES="mscoree,mshtml="
fi

# Forces glibc to print a verbose backtrace to stderr when fortify/overflow is triggered
export LIBC_FATAL_STDERR_=1

export LOG_RAW_SYMB="${LOG_RAW_SYMB:-20}" # number of lines displaying external library deps
export LOG_SIZES="${LOG_SIZES:-500}" # number of lines displayed in logs
export LOG_FF_SIZES="${FF_LOG_SIZES:-1000}" # number of lines displayed in ffmpeg logs
export LOG_INSTALLED="${LOG_INSTALLED:-85}" # shown number of installed files in DESTDIR prefix
export LOG_PATCH_ERRORS="${FFBUILD_PREFIX}/patch_errors.log"

# Helper hooks to skip .la files, dependancies and .pc files auditing and patching
export GLOBAL_SKIP_PRE_PATCH=0
export GLOBAL_SKIP_POST_PC_PATCH=0
export GLOBAL_SKIP_POST_CLEAN_LA_FILES=0
export GLOBAL_SKIP_POST_DEP_AUDIT=0
export GLOBAL_DISABLE_VERSION_FINDER=0
export GLOGAL_SKIP_POST_STRIP=0
export GLOBAL_DISABLE_CONF_FINDER=0

mkdir -p "$CACHE_DIR" "$TMP_DIR" "$FFMPEG_BUILD_ROOT" "$FFMPEG_DIR"

# Clear base flags before declaration
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS RUSTFLAGS LIBS

# ==============================================================
# SMART SELECTIVE LTO OPTIMIZATION UNIT
# ==============================================================
# LTO in ffmpeg is bugged when compiled with gcc-(13-14-15) in mingw. You will meet 'lto1: internal compiler error: in choose_baseaddr, at config/i386/i386.cc:7447' or similar at linking time; compiler will crash.
# You can 1) disable LTO for ffmpeg only, but enable LTO for ffmpeg components. 
# Tip: -ffat-lto-objects is needed for ffmpeg linker to understand LTO code if LTO disabled for ffmpeg only but enabled for components. You can also add -fno-use-linker-plugin to --extra-ldflags to avoud the use of LTO code by ffmpeg itself. But you must be sure to NOT use cmake-specific flags that enable LTO (IPO) because they forcefully add -fno-fat-lto-objects that is unacceptable in our case.
# Option 2) add -mstackrealign to ffmpeg c(xx)flags. With this flag the compiler does not crash. -mpreferred-stack-boundary=4 should not be used.
# LTO will crash anyway because GCC is bugged, so don't bother too much. You may try to activate LTO selectivly for some components only.
# Tip: rust has -C linker-plugin-lto LLVM Bitcode or LLVM MinGW
# Tip: RUST may use -C lto=thin
# Tip: add -Wa,-mbig-obj to cflags to accept non-PE-COFF file format
should_apply_lto() {
    # If the global LTO flag is turned off, no optimization is applied
    [[ "$USE_LTO" != "1" ]] && return 1

    # If this is definitely the final build of FFmpeg - LTO is allowed
    [[ "$FFMPEG_BUILD_STAGE" == "1" ]] && return 0

    # If the stage name is not defined below or at all
    [[ -z "$STAGENAME" ]] && return 1

    # Blacklist: LTO is prohibited for libraries that break linker symbol tables
    case "$STAGENAME" in
        *"libicu"|*"glib2"|*"libxml2"|*"libiconv"|*"gettext"|*"bzlib"|*"xz"|*"zstd"|*"libffi"|*"pcre2"|*"openssl"|*"libssh"|*"curl"|*"libtensorflow"|*"libtorch"|*"librsvg"|*"cairo"|*"pango"|*"spirv-cross"|*"shaderc"|*"spirv-tools"|*"glslang"|*"openmpt"|*"cryptopp"|*"kvazaar")
            return 1
            ;;
    esac

    # WHITELIST: LTO will ONLY be enabled for these libraries.
    case "$STAGENAME" in
        # Basic libs
        *"mingw"|*"zlib"|*"tbbmalloc"|*"fftw3"|*"freeglut"|*"openblas")
            return 0
            ;;
        # Major heavy video codecs
        *"rav1e"|*"aom"|*"lcevcdec"|*"libtheora"|*"libvpx"|*"openapv"|*"openh264"|*"svthevc"|*"svtvp9"|*"vvdec"|*"vvenc"|*"x264"|*"x265"|*"xeve"|*"xevd"|*"dav1d"|*"dav2d")
            return 0
            ;;
        # Audio codecs and audio processing
        *"libogg"|*"bs2b"|*"chromaprint"|*"libmysofa"|*"libsamplerate"|*"soundtouch"|*"soxr"|*"speex"|*"rubberband"|*"libmpg123"|*"audiotoolbox"|*"fdk-aac"|*"ilbc"|*"lc3"|*"libcelt"|*"libcodec2"|*"libgsm"|*"libmad"|*"libmp3lame"|*"libmpeghdec"|*"libopus"|*"mp3shine"|*"mpeghe"|*"opencore-amr"|*"twolame"|*"vo-amrwb"|*"gme"|*"modplug")
            return 0
            ;;
        # Key High Level Graphics Filters
        *"zimg"|*"libtesseract"|*"leptonica"|*"libplacebo"|*"opencl"|*"openvino"|*"opencv"|*"nnedi3"|*"whisper"|*"vapoursynth")
            return 0
            ;;
        # lightweight codecs
        *"giflib"|*"spng"|*"libjpeg-turbo"|*"libpng"|*"libtiff"|*"openjpeg"|*"svtjpegxs"|*"libwebp"|*"libavif"|*"libjxl")
            return 0
            ;;
        # other
        *"cdio"|*"cdiowpar"|*"cddb"|*"lensfun"|*"libaribb24"|*"libaribcaption"|*"libass"|*"zvbi"|*"qrencode"|*"quirc"|*"amf"|*"libklvanc"|*"vidstab"|*"libcaca"|*"libudfread"|*"libdvdcss"|*"libdvdread"|*"libdvdnav"|*"libbluray"|*"libomnidrive"|*"libdatachannel")
            return 0
            ;;
        # All other components are assembled WITHOUT LTO
        *)
            return 1
            ;;
    esac

    # OPTION B: Enable LTO for everything except blacklist. 
    # (Uncomment the line below, comment out the Option A block)

    # return 0
}
export -f should_apply_lto

# ==============================================================
# Flags for the component build stage
# ==============================================================
# Tip: disable -fPIC, -ffast-math, if troubles occur
# Tip: enable -ftree-vectorize for opt levels lower than -O3
# Tip: don't use cflags -ffunction-sections, -fdata-sections, linker flag -Wl,--gc-sections with non-static and non GCC builds
# Tip: don't use -fno-plt flag other than Linux host
# Tip: use -Wa,-mbig-obj for c(xx)flags if see 'too many sections' and 'file too big'
# Tip: add -Wl,--whole-archive $LIBS -Wl,--no-whole-archive $OTHER_LIBS in 'Libs:' section in .pc file to incapsulate more libs (voices or other) when using LTO for static builds

# Function to assemble the string RUSTFLAGS from an array
# Accepts a prefix (eg "-C link-arg=") and an array name
to_rust_flags() {
    local prefix="$1"; shift
    printf " ${prefix}%s" "$@"
}
export -f to_rust_flags

# Dynamically rearrange environment variables
apply_lto_policy() {
    local is_lld=0
    if [[ "${TARGET_LD}" == "lld" || "${TARGET_LD}" == *"ld.lld"* ]]; then
        is_lld=1
    fi

    local OPT_LEVEL="-O3"

    if should_apply_lto; then
        log_info "⚡ [LTO ENABLED] Applying Link-Time Optimization for: $STAGENAME"

        export RUSTLTO=" -C lto=fat"
        export USELTO="-flto=4 -flto-partition=balanced"
        export USELTO_C=" -ffat-lto-objects -fmerge-all-constants"

        # -O3 optimization will be added to LDFLAGS as well
        if [[ $is_lld -eq 0 ]]; then
            export USELTO_L=" ${OPT_LEVEL}"
        else
            local GCC_LTO_PLUGIN=$("${CC}" -print-prog-name=liblto_plugin.so)
            export USELTO_L=" ${OPT_LEVEL} -Wl,-plugin,${GCC_LTO_PLUGIN}"
        fi

        export NOLTO="-fno-lto"
        export AR="${FFBUILD_CROSS_PREFIX}gcc-ar"
        export NM="${FFBUILD_CROSS_PREFIX}gcc-nm"
        export RANLIB="${FFBUILD_CROSS_PREFIX}gcc-ranlib"
    else
        export RUSTLTO=""
        export USELTO="-fno-lto"
        export USELTO_C=""
        export USELTO_L=""
        export NOLTO="-fno-lto"
        export AR="${FFBUILD_CROSS_PREFIX}ar"
        export NM="${FFBUILD_CROSS_PREFIX}nm"
        export RANLIB="${FFBUILD_CROSS_PREFIX}ranlib"
    fi

    # these flags appear to conflict with pthread and other threading implementations and cannot be used simultaneously. They should only be used selectively where supported by the libraries themselves
    [[ "$USE_OPENMP" == "1" ]] && \
    export OPENMP_C="-fopenmp " && \
    export OPENMP_LIB="-lgomp "

    # Sanitizer flags slow down ffmpeg by 2-3 times (bad) 
    # Without some of them, ffmpeg will not link, you need to forward it for it too (bad) 
    # -fno-sanitize-recover=all at the slightest error in fdk-aac FFmpeg will immediately exit without a chance to continue (bad) 
    # if you leave only -fsanitize=undefined (UBSan), then this gives much less overhead than address. But it still slows down the work, although not 3 times (bad)
    if [[ "$USE_ASAN" == "1" ]]; then
        local ASAN_CFLAGS=" -fsanitize=address,undefined -fno-omit-frame-pointer"
        local ASAN_CXXFLAGS=" -fsanitize=address,undefined -fno-omit-frame-pointer"
        local ASAN_LDFLAGS="-static-libasan -fsanitize=address,undefined "
        local STACK_FLAGS=" -fstack-protector-strong"
    else
        local STACK_FLAGS=" -fstack-protector-strong" # -mstackrealign
    fi
    
    if [[ "$DEBUG_MODE" == "1" ]]; then
        local G_FLAGS="-g1"
        local RUST_STRIP_POLICY="none"
    else
        # -g0 -fno-var-tracking-assignments: for the GCC/G++ compiler:
        # Do not inflate debugging information (even hidden ones)
        local G_FLAGS="-g0 -fno-var-tracking-assignments"
        local RUST_STRIP_POLICY="debuginfo"
    fi

    # General and additional libs
    # -lkernel32 -lmingwex -lgcc_eh -lgcc
    local SYSTEM_LIBS="-lsetupapi -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lws2_32 -lbcrypt -pthread"
    export ADDITIONAL_LIBS="-lusp10 -lmsimg32 -lcfgmgr32 -lruntimeobject -ldwrite -ld2d1 -lwindowscodecs -lopengl32 -lssp -lgdi32 -lrpcrt4 -lntdll -luserenv -liphlpapi -lwinmm -luuid -ldnsapi -lcrypt32 -lwldap32 -lnormaliz -lwsock32 -lcomctl32 -lshell32 -loleaut32 -ld3d11 -ld3d12 -ldxgi -ldxguid -lmfplat -lmfuuid -lmfreadwrite -lgomp"

    # Flags for HOST (Linux), which are always needed for native builds 
    # * -Wl,--hash-style=gnu: Creates faster symbol tables (GNU-style), which speeds up program launch (relevant for tools that are called thousands of times per build). 
    # * -Wl,--strip-all (or just -s): Removes debugging symbols, significantly reducing the size of the binary. 
    # * -Wl,--gc-sections: Removes unused code from the binary. Works in tandem with -ffunction-sections -fdata-sections in CFLAGS. It is useful for a native tool to be compact. 
    # * -Wl,-O1: Enables optimizations of the linker itself (for example, reduction of hash tables). 
    # * -Wl,--as-needed: Ignores libraries that were specified on the command line but are not actually used by the code. This prevents unnecessary dependencies. 
    # * -Wl,-z,relro -Wl,-z,now: This is “Full RELRO”. Analogous to --dynamicbase. Makes the function table (GOT) read-only, which prevents many exploits. 
    # * -Wl,-z,noexecstack: Direct analogue of --nxcompat. Prevents code from being executed on the stack.
    # * -Wl,--no-keep-memory: reread from disk not ram
    local HOST_LINUX_LDFLAGS=(
        "-pipe"
        "-fuse-ld=${HOST_LD}"
        "-Wl,-z,relro"
        "-Wl,-z,now"
        "-Wl,-z,noexecstack"
        "-Wl,--hash-style=gnu"
        "-Wl,-O1"
        "-Wl,--as-needed"
    )
    [[ "$PREFER_SHARED" != "1" ]] && HOST_LINUX_LDFLAGS+=( "-Wl,--gc-sections" )

    # General Rust settings; codegen-units = 16 (default)
    local COMMON_RUST_OPTS="-C target-cpu=${CPU_ARCH} -C strip=${RUST_STRIP_POLICY} -C codegen-units=1 -C opt-level=3${RUSTLTO}"

    export HOST_RUSTFLAGS="${COMMON_RUST_OPTS} $(to_rust_flags "-C link-arg=" "${HOST_LINUX_LDFLAGS[@]}") -C embed-bitcode=yes"
    export HOST_LDFLAGS="${HOST_LINUX_LDFLAGS[*]} ${USELTO}${USELTO_L}"
    export HOST_CFLAGS="${OPT_LEVEL} -march=${CPU_ARCH} -mtune=${CPU_TUNE} -fno-plt -pipe ${G_FLAGS} -ffunction-sections -fdata-sections -std=gnu23 ${USELTO}${USELTO_C}"
    export HOST_CXXFLAGS="${OPT_LEVEL} -march=${CPU_ARCH} -mtune=${CPU_TUNE} -fno-plt -pipe ${G_FLAGS} -ffunction-sections -fdata-sections -std=gnu++20 ${USELTO}${USELTO_C}"
    export HOST_CPPFLAGS="-D_FORTIFY_SOURCE=2"
    # Force for the native Linux compiler, which calls Meson
    export CFLAGS_FOR_BUILD="${HOST_CFLAGS} ${HOST_CPPFLAGS}"
    export CXXFLAGS_FOR_BUILD="${HOST_CXXFLAGS} ${HOST_CPPFLAGS}"
    export LDFLAGS_FOR_BUILD="${HOST_LDFLAGS}"
    export CC_LD_FOR_BUILD="${HOST_LD}"
    export CXX_LD_FOR_BUILD="${HOST_LD}"

    # Branching by TARGET
    if [[ "$TARGET" == "win64" ]]; then
        export BASE_CFLAGS="-mms-bitfields${STACK_FLAGS} -Wno-attributes -fgraphite-identity -floop-nest-optimize"
        export BASE_CPPFLAGS="-D__USE_MINGW_ANSI_STDIO=1 -U_WIN32_WINNT -D_WIN32_WINNT=0x0A00 -D_WIN32 -D_FORTIFY_SOURCE=2"

        local console_flag=" -mconsole"
        local BASE_LD_FLAGS=(
            "-pipe"
            "-fuse-ld=${TARGET_LD}"
            "-Wl,--high-entropy-va"
            "-Wl,--nxcompat"
            "-Wl,--dynamicbase"
            "-Wl,--stack=8388608"
            "-Wl,--as-needed"
            "-Wl,--subsystem=console"
        )

        if [[ $is_lld -eq 1 ]]; then
            BASE_LD_FLAGS+=(
                # # "-Wl,--thinlto-jobs=all" # only for no fat lto
                # "-Wl,-mllvm,-lldtailmerge" # clang flags
            )
        else
            BASE_LD_FLAGS+=( "-Wl,--reduce-memory-overheads" )
        fi

        [[ "$PREFER_SHARED" != "1" ]] && BASE_LD_FLAGS+=( "-Wl,--gc-sections" )

        local MAIN_LDFLAGS=("${BASE_LD_FLAGS[@]}")
        MAIN_LDFLAGS+=("-L${FFBUILD_PREFIX}/lib")

        if [[ "$PREFER_SHARED" == "1" ]]; then
            export CFLAGS="${OPT_LEVEL} -march=${CPU_ARCH} -mtune=${CPU_TUNE} -pipe ${G_FLAGS} ${BASE_CFLAGS} -fPIC -std=gnu17${ASAN_CFLAGS}${console_flag}"
            export CXXFLAGS="${OPT_LEVEL} -march=${CPU_ARCH} -mtune=${CPU_TUNE} -pipe ${G_FLAGS} ${BASE_CFLAGS} -fPIC -std=gnu++20${ASAN_CXXFLAGS}${console_flag}"
            local RUST_STATIC_CFG=""
            export LDFLAGS="${ASAN_LDFLAGS}${MAIN_LDFLAGS[*]}"
        else
            export CFLAGS="${OPT_LEVEL} -march=${CPU_ARCH} -mtune=${CPU_TUNE} -pipe ${G_FLAGS} ${BASE_CFLAGS} -ffunction-sections -fdata-sections -std=gnu17${ASAN_CFLAGS}${console_flag}"
            export CXXFLAGS="${OPT_LEVEL} -march=${CPU_ARCH} -mtune=${CPU_TUNE} -pipe ${G_FLAGS} ${BASE_CFLAGS} -ffunction-sections -fdata-sections -std=gnu++20${ASAN_CXXFLAGS}${console_flag}"
            MAIN_LDFLAGS=("-Wl,-Bstatic" "-static" "-static-libgcc" "-static-libstdc++" "${MAIN_LDFLAGS[@]}")
            local RUST_STATIC_CFG="-C target-feature=+crt-static -C embed-bitcode=yes"
            export LDFLAGS="${ASAN_LDFLAGS}${MAIN_LDFLAGS[*]}"
        fi

        # RUST SAFE INJECTION
        local rust_link_args=()
        for flag in "${MAIN_LDFLAGS[@]}"; do
            [[ "$flag" == *"-plugin"* ]] && continue
            [[ "$flag" == *"-fuse-ld="* ]] && continue
            [[ "$flag" == *"--thinlto-jobs"* ]] && continue
            [[ "$flag" == *"-lldtailmerge"* ]] && continue
            [[ "$flag" == *"--subsystem"* ]] && continue
            rust_link_args+=("$flag")
        done

        export RUSTFLAGS="${RUST_STATIC_CFG} ${COMMON_RUST_OPTS} $(to_rust_flags "-C link-arg=" "${rust_link_args[@]}")"
        export LIBS="${LIBS:-$SYSTEM_LIBS}"
        export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="${CC}"

        # Disable ASLR and High Entropy VA to fix the PE base address
        if [[ "$DEBUG_MODE" == "1" ]]; then
            log_info "Adjusting LDFLAGS locally for FFmpeg to allow precise debugging..."
            export LDFLAGS=$(echo " ${LDFLAGS} " | sed \
                -e 's/ -Wl,--dynamicbase / /g' \
                -e 's/ -Wl,--high-entropy-va / /g' \
                -e 's/ -Wl,--stack=8388608 / /g' | xargs)
        fi

        # Strict Injection for Cargo Target (Overrides hidden cargo-c defaults)
        local RTARCH="${FFBUILD_RUST_TARGET//-/_}"
        export "CARGO_TARGET_${RTARCH^^}_RUSTFLAGS"="${RUSTFLAGS}"

    elif [[ "$TARGET" == "linux64" ]]; then
        export BASE_CFLAGS="${STACK_FLAGS} -Wno-attributes -fgraphite-identity -floop-nest-optimize"
        export BASE_CPPFLAGS="-D_FORTIFY_SOURCE=2"

        # Use Linux-specific LDFLAGS
        local MAIN_LDFLAGS=("${HOST_LINUX_LDFLAGS[@]}")
        MAIN_LDFLAGS+=("-L${FFBUILD_PREFIX}/lib")

        if [[ "$PREFER_SHARED" == "1" ]]; then
            export CFLAGS="${OPT_LEVEL} -march=${CPU_ARCH} -mtune=${CPU_TUNE} -pipe ${G_FLAGS} ${BASE_CFLAGS} -fPIC -std=gnu17${ASAN_CFLAGS}"
            export CXXFLAGS="${OPT_LEVEL} -march=${CPU_ARCH} -mtune=${CPU_TUNE} -pipe ${G_FLAGS} ${BASE_CFLAGS} -fPIC -std=gnu++20${ASAN_CXXFLAGS}"
            export STAGE_CFLAGS="-fno-semantic-interposition"
            export STAGE_CXXFLAGS="-fno-semantic-interposition"
            local RUST_STATIC_CFG=""
            export LDFLAGS="${ASAN_LDFLAGS}${MAIN_LDFLAGS[*]}"
        else
            export CFLAGS="${OPT_LEVEL} -march=${CPU_ARCH} -mtune=${CPU_TUNE} -pipe ${G_FLAGS} ${BASE_CFLAGS} -ffunction-sections -fdata-sections -std=gnu17${ASAN_CFLAGS}"
            export CXXFLAGS="${OPT_LEVEL} -march=${CPU_ARCH} -mtune=${CPU_TUNE} -pipe ${G_FLAGS} ${BASE_CFLAGS} -ffunction-sections -fdata-sections -std=gnu++20${ASAN_CXXFLAGS}"
            MAIN_LDFLAGS=("-static" "-static-libgcc" "-static-libstdc++" "${MAIN_LDFLAGS[@]}")
            local RUST_STATIC_CFG="-C target-feature=+crt-static -C embed-bitcode=yes"
            export LDFLAGS="${ASAN_LDFLAGS}${MAIN_LDFLAGS[*]}"
        fi

        # RUST SAFE INJECTION
        local rust_link_args=()
        for flag in "${MAIN_LDFLAGS[@]}"; do
            [[ "$flag" == *"-plugin"* ]] && continue
            [[ "$flag" == *"-fuse-ld="* ]] && continue
            [[ "$flag" == *"--thinlto-jobs"* ]] && continue
            [[ "$flag" == *"-lldtailmerge"* ]] && continue
            [[ "$flag" == *"--subsystem"* ]] && continue
            rust_link_args+=("$flag")
        done

        export RUSTFLAGS="${RUST_STATIC_CFG} ${COMMON_RUST_OPTS} $(to_rust_flags "-C link-arg=" "${rust_link_args[@]}")"
        export LIBS="${LIBS} -ldl -lrt"
        export CUDA_PATH=/usr/lib/nvidia-cuda-toolkit
        export PATH="${PATH}:/usr/local/cuda/bin"

        # Disable ASLR and High Entropy VA to fix the PE base address
        if [[ "$DEBUG_MODE" == "1" ]]; then
            log_info "Adjusting LDFLAGS locally for FFmpeg to allow precise debugging..."
            export LDFLAGS=$(echo " ${LDFLAGS} " | sed \
                -e 's/ -Wl,--dynamicbase / /g' \
                -e 's/ -Wl,--high-entropy-va / /g' \
                -e 's/ -Wl,--stack=8388608 / /g' | xargs)
        fi
        # Strict Injection for Cargo Target (Overrides hidden cargo-c defaults)
        local RTARCH="${FFBUILD_RUST_TARGET//-/_}"
        export "CARGO_TARGET_${RTARCH^^}_RUSTFLAGS"="${RUSTFLAGS}"
    fi

    export CPPFLAGS="-I${FFBUILD_PREFIX}/include ${BASE_CPPFLAGS}"
}
export -f apply_lto_policy

generate_meson_cross() {

    local extra_c_links=""
    local extra_cpp_links=""
    local def_lib="static"
    local exe_wrap_line=""

    if [[ "$PREFER_SHARED" != "1" ]]; then
        extra_c_links=", '-static', '-static-libgcc'"
        extra_cpp_links=", '-static', '-static-libgcc', '-static-libstdc++'"
        def_lib="static"
    else
        def_lib="shared"
    fi

    [[ "$USE_WINE" == "1" ]] && exe_wrap_line="exe_wrapper = 'wine'"

    cat <<EOF > /cross.meson
[binaries]
c = '${CC}'
cpp = '${CXX}'
ar = '${AR}'
ranlib = '${RANLIB}'
nm = '${NM}'
strip = '${STRIP}'
windres = '${WINDRES}'
dlltool = '${DLLTOOL}'
nasm = 'nasm'
# ld = '/usr/bin/ld.lld'
c_ld = '${TARGET_LD}'
cpp_ld = '${TARGET_LD}'
${exe_wrap_line}

[properties]
pkg_config_static = $( [[ "$PREFER_SHARED" == "1" ]] && echo "false" || echo "true" )
needs_exe_wrapper = $( [[ "$USE_WINE" == "1" ]] && echo "false" || echo "true" )
sys_root = '/'
pkg_config_libdir = '${PKG_CONFIG_LIBDIR}'

[built-in options]
# flags can be passed like this globally, but passed individially
# c_args = ['-I${FFBUILD_PREFIX}/include', $(echo "${CFLAGS}" | sed "s/ /', '/g" | sed "s/^/'/;s/$/'/")]
c_args = ['-I${FFBUILD_PREFIX}/include']
cpp_args = ['-I${FFBUILD_PREFIX}/include']
c_link_args = ['-L${FFBUILD_PREFIX}/lib'${extra_c_links}]
cpp_link_args = ['-L${FFBUILD_PREFIX}/lib'${extra_cpp_links}]
default_library = '${def_lib}'

[host_machine]
system = 'windows'
cpu_family = '${CPU_FAMILY}'
cpu = '${CPU_FAMILY}'
endian = 'little'
EOF

    export FFBUILD_MESON_CROSS="/cross.meson"
}
export -f generate_meson_cross

generate_cmake_toolchain() {
    local base_ld_init="-fuse-ld=${TARGET_LD}"

    cat <<EOF > /toolchain.cmake
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR ${CPU_FAMILY})
set(CMAKE_SYSTEM_VERSION 10.0)

set(CMAKE_SYSROOT /opt/ct-ng/${FFBUILD_TOOLCHAIN}/sysroot)
set(CMAKE_FIND_ROOT_PATH ${FFBUILD_PREFIX} /opt/ct-ng/${FFBUILD_TOOLCHAIN}/sysroot /opt/ct-ng)

set(CMAKE_C_COMPILER ${CC})
set(CMAKE_CXX_COMPILER ${CXX})
set(CMAKE_RC_COMPILER ${WINDRES})
set(CMAKE_RANLIB ${RANLIB} CACHE FILEPATH "Forced RANLIB")
set(CMAKE_AR ${AR} CACHE FILEPATH "Forced AR")
set(CMAKE_NM ${NM} CACHE FILEPATH "Forced NM")

# =============================================================================
# FLAGS INJECTION (Safe initialization preventing project overrides)
# =============================================================================

# set(CMAKE_C_FLAGS_INIT "${CFLAGS} ${CPPFLAGS}")
# set(CMAKE_CXX_FLAGS_INIT "${CXXFLAGS} ${CPPFLAGS}")
# set(CMAKE_EXE_LINKER_FLAGS_INIT ${LDFLAGS}")

# set(CMAKE_EXE_LINKER_FLAGS_INIT    "${base_ld_init}")
# set(CMAKE_SHARED_LINKER_FLAGS_INIT "${base_ld_init}")
# set(CMAKE_MODULE_LINKER_FLAGS_INIT "${base_ld_init}")

# set(CMAKE_LINKER "${LD}" CACHE FILEPATH "Forced Linker")
set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Choose the type of build" FORCE)

set(BUILD_SHARED_LIBS $( [[ "$PREFER_SHARED" == "1" ]] && echo "ON" || echo "OFF" ) CACHE BOOL "Build shared libraries" FORCE)

# =============================================================================
# ROOT PATH & PKG-CONFIG CONFIGURATION
# =============================================================================
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

set(ENV{PKG_CONFIG_SYSROOT_DIR} "/")
set(ENV{PKG_CONFIG_PATH} "")
set(ENV{PKG_CONFIG_LIBDIR} "${PKG_CONFIG_LIBDIR}")

set(PKG_CONFIG_ARGN "$( [[ "$PREFER_SHARED" != "1" ]] && echo "--static" )")

if(NOT DEFINED CMAKE_INSTALL_PREFIX)
    set(CMAKE_INSTALL_PREFIX "${INSTALL_ROOT}" CACHE PATH "")
endif()

set(CMAKE_WARN_DEPRECATED OFF CACHE BOOL "" FORCE)
set(CMAKE_WARN_ON_INITIAL_TARGETS OFF CACHE BOOL "" FORCE)
set(CMAKE_POLICY_WARNING_CMP0218 OFF CACHE BOOL "" FORCE)
set(CMAKE_POLICY_WARNING_CMP0219 OFF CACHE BOOL "" FORCE)
set(CMAKE_POLICY_WARNING_CMP0177 OFF CACHE BOOL "" FORCE)
set(CMAKE_POLICY_WARNING_CMP0146 OFF CACHE BOOL "" FORCE)
set(CMAKE_POLICY_WARNING_CMP0148 OFF CACHE BOOL "" FORCE)
set(CMAKE_POLICY_DEFAULT_CMP0218 NEW CACHE STRING "" FORCE)
set(CMAKE_POLICY_DEFAULT_CMP0219 NEW CACHE STRING "" FORCE)
set(CMAKE_POLICY_DEFAULT_CMP0177 NEW CACHE STRING "" FORCE)
set(CMAKE_POLICY_DEFAULT_CMP0146 OLD CACHE STRING "" FORCE)
set(CMAKE_POLICY_DEFAULT_CMP0148 OLD CACHE STRING "" FORCE)
EOF

    export FFBUILD_CMAKE_TOOLCHAIN="/toolchain.cmake"
}
export -f generate_cmake_toolchain

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

export ADDINS_STR="${ADDINS_STR:-}"

export REPO="${GITHUB_REPOSITORY:-lichtenshtein/ffmpeg-build}"
export REPO="${REPO,,}"
export REGISTRY="${REGISTRY_OVERRIDE:-ghcr.io}"
export BASE_IMAGE="${REGISTRY}/${REPO}/base:latest"
# export TARGET_IMAGE="${TARGET_IMAGE:-${REGISTRY}/${REPO}/base-${TARGET}:latest}"
export IMAGE="${REGISTRY}/${REPO}/${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}:latest"

# 2 for verbose logs, 0 for brief
# FFBUILD_VERBOSE value from Docker ENV
if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
    export MAKE_V="V=1"
    export NINJA_V="-v"
    export CARGO_V="-v"
    export OP_VERB="-v" # mv and cp operations verbocity
    export OP_V="v"
    export OP_VERB2="--verbose"
    export GIT_VERB="--progress"
    export LINK_VERB=" -Wl,-v"
else
    export MAKE_V=""
    export NINJA_V=""
    export CARGO_V=""
    export OP_VERB=""
    export OP_V=""
    export OP_VERB2=""
    export GIT_VERB="--quiet"
    export LINK_VERB=""
fi

# =================
# HELPER FUNCTIONS
# =================

get_stage_hash() {
    local STAGE_PATH="$1"

    # If forced static cache mode is enabled
    # if [[ "$DEBUG_NO_HASH" == "1" ]]; then
        # Compute a deterministic string in advance, without interrupting the pipeline with return
        # Disabled because manual changes no longer force cache updates 
        # local STAGE_NAME=$(basename "$STAGE_PATH" .sh)
        # printf "%s_static_cache" "$STAGE_NAME" | sha256sum | cut -c1-16
    # else
        # Take the entire file content
        # Remove \r (protection against Windows hyphenation)
        # Remove empty lines and comments
        # Calculate the hash of everything else
        grep -v '^[[:space:]]*#' "$STAGE_PATH" \
            | sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' \
            | grep -v '^[[:space:]]*$' \
            | tr -d '\r' \
            | sha256sum | cut -c1-16
    # fi
}
export -f get_stage_hash

# Helper function — call after we have set $STAGE:
# eval "$(stage_vars "$STAGE")"
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

# Substitute paths to libraries depending on PREFER_SHARED state
export lib_ext=$([ "${PREFER_SHARED}" == "1" ] && echo "dll.a" || echo "a")

# Script usage: local DEP_LIBS=$(get_pc_libs tesseract lept libarchive libcurl)
get_pc_libs() {
    local libs=""
    for lib in "$@"; do
        if "${PKG_CONFIG}" --exists "$lib"; then
            libs="$libs $lib"
        fi
    done
    "${PKG_CONFIG}" --static --libs $libs
}
export -f get_pc_libs

# Checks for the presence of a static or dynamic library by its base name
has_library() {
    local lib_name="$1"
    local lib_dir="${FFBUILD_PREFIX}/lib"
    if [ -e "${lib_dir}/lib${lib_name}.a" ] || \
       [ -e "${lib_dir}/lib${lib_name}.dll" ] || \
       [ -e "${lib_dir}/lib${lib_name}.dll.a" ] || \
       compgen -G "${lib_dir}/lib${lib_name}.so*" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}
export -f has_library

# Function for cleaning files with logging
# Arguments: 1 - description (for the log), 2 - search conditions (find expression)
clean_unwanted_libs() {
    local label="$1"
    local find_expr="$2"
    local DELETED_FILES

    # Perform deletion and grab the list
    DELETED_FILES=$(eval "find \"$INSTALL_ROOT\" -type f $find_expr -print -delete 2>/dev/null" | sed "s|$FFBUILD_DESTDIR||g")

    if [[ -n "$DELETED_FILES" ]]; then
        log_debug "${BROOM_MARK} Removing $label for ${STAGENAME}:\n $DELETED_FILES"
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
        if [[ "$base_name" == lib* ]]; then
            base_name="${base_name#lib}"
        fi
        local lib_name="lib${base_name}.a"
        local dll_dir=$(dirname "$dll_file")

        local lib_out_dir="$dll_dir"
        [[ "$dll_dir" == *"/bin" ]] && lib_out_dir="${dll_dir%/bin}/lib"
        mkdir -p "$lib_out_dir"

        local out_lib="$lib_out_dir/$lib_name"

        # Exceptions
        if [[ "$dll_name" == "tensorflow.dll" ]]; then
            log_info "${CACHE_MARK} Using pre-packaged MSVC import lib for tensorflow.dll"
            continue
        fi

        if [[ -f "$out_lib" ]]; then
            # List of stages where we ALWAYS force imports to be rebuilt
            if [[ "$dll_name" == "openvino.dll" || "$dll_name" == "openvino_c.dll" || "$STAGENAME" == *"opencv"* ]]; then
                log_warn "Forcing regeneration of $lib_name for MinGW compatibility..."
                rm -f "$out_lib"
            else
                local current_size=$(stat -c%s "$out_lib" 2>/dev/null)
                if [[ $current_size -gt 4096 ]]; then
                    log_debug "${CACHE_MARK} Skipping: A valid import for $dll_name already exists"
                    continue
                fi
            fi
        fi

        log_debug "${BUILD_MARK} Creating import lib for $dll_name"

        local tmp_build=$(mktemp -d)
        cp "$dll_file" "$tmp_build/"
        pushd "$tmp_build" > /dev/null

        local def_file="${base_name}.def"
        echo "EXPORTS" > "$def_file"

        # Try to use the official gendef (for PE32+)
        if command -v gendef &>/dev/null; then
            gendef - "$dll_name" 2>/dev/null | grep -v '^;' >> "$def_file"
        else
            # If there is no gendef, parse objdump using grep -o
            # Pull out the words at the very end of the lines of the Export Table section.
            # The pattern covers C, C++ GCC (_Z) and C++ MSVC (?).
            objdump -p "$dll_name" 2>/dev/null | \
            sed -n '/\[Ordinal\/Name Pointer\] Table/,/^$/p' | \
            grep -oE '[A-Za-z0-9_?@$]+$' | \
            grep -vE '^[0-9]+$' | sort -u >> "$def_file"
        fi

        # Strict flags for 64-bit Windows environment
        # -k (--kill-at) protects C++ mangling from damage by the dlltool utility
        local DLLTOOL_FLAGS="-m i386:x86-64 --as-flags=--64 -k"

        if $DLLTOOL ${DLLTOOL_FLAGS} -d "$def_file" -l "$lib_name" -D "$dll_name" 2>/dev/null; then
            local size=$(stat -c%s "$lib_name" 2>/dev/null)
            if [[ $size -gt 1024 && $size -lt 52428800 ]]; then
                cp "$lib_name" "$out_lib"
                log_info "${CHECK_MARK} Successfully created Win64 import: $out_lib"
            else
                log_warn "The generated import file is invalid in size. Deleting."
                rm -f "$lib_name"
            fi
        else
            log_error "dlltool failed with error for $dll_name"
        fi

        popd > /dev/null
        rm -rf "$tmp_build"
    done
}
export -f generate_implibs

# ===================
# FLAG DEDUPLICATORS
# ===================

# Remove ANSI colors
# Remove line breaks (replace with spaces)
# xargs will collapse extra spaces into one line
clean_val() {
    echo "$*" | \
        sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" | \
        sed -E "s/''|\"\"//g" | \
        tr -s '[:space:]' ' ' | \
        xargs -r echo
}

# Fast deduplicators
dedupe_logic() {
    local input="$1"
    local mode="$2"
    # Split on whitespace, filter garbage words, group flags, and empty lines
    local clean=$(echo "$input" | tr ' ' '\n' | \
        grep -vE "^(Package .* not found|No package .* found)$|^$|^-Wl,--(start|end)-group$|^-Wl,--(no-)?as-needed$")
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
        echo "$input" | tr ' ' '\n' | \
            grep -vE "^-Wl,--(start|end)-group$|^-Wl,--(no-)?as-needed$" | \
            tr '\n' ' ' | xargs -r
    fi
}

smart_libs_dedupe() {
    local input=$(clean_val "$*")
    [[ -z "$input" ]] && return
    # Specific cleaning for libraries 
    # unify pthread: replace -lpthread with -pthread 
    # clean garbage and PATH, remove -lstdc++
    # Remove -Wl flags
    local filtered=$(echo "$input" | tr ' ' '\n' | \
        grep -vE "^-L|^-lstdc\+\+$|^-Wl,--(start|end)-group$|^-Wl,--(no-)?as-needed$" | \
        sed 's/^-lpthread$/-pthread/')
    # Merge into one line without removing duplicates?
    if [[ "$DEDUPE_FLAGS" == "1" ]]; then
        dedupe_logic "$filtered" "last" | tr '\n' ' ' | xargs -r
    else
        echo "$filtered" | tr '\n' ' ' | xargs -r
    fi
}
export -f clean_val dedupe_logic smart_dedupe smart_libs_dedupe

# ==============================
# PKG-CONFIG CORRECTION POLICY
# ==============================

should_skip_post_pc_patch() {
    [[ -z "$STAGENAME" ]] && return 1

    [[ "${GLOBAL_SKIP_POST_PC_PATCH:-0}" == "1" ]] && return 0

    case "$STAGENAME" in
        *"libtorch"|*"opencv"|*"openvino_shared")
            return 0 # Skip .pc fix
            ;;
        *) 
            return 1 # perform the correction for all other components
            ;;
    esac
}
export -f should_skip_post_pc_patch

patch_pc_files() {
    # Check the centralized bypass hook
    if should_skip_post_pc_patch; then
        log_info "${LOCK_MARK} Post-PC patching skipped for $STAGENAME"
        return 0
    fi

    # Check the physical presence of the pkgconfig directory
    local pc_dir="$PC_DIR"
    if [[ ! -d "$pc_dir" ]]; then
        log_debug "No pkgconfig directory found at $pc_dir for $STAGENAME — skipping audit."
        return 0
    fi

    # Count the number of .pc files in the directory before outputting the log
    shopt -s nullglob
    local pc_files=("$pc_dir"/*.pc)
    shopt -u nullglob

    if [[ ${#pc_files[@]} -eq 0 ]]; then
        log_debug "No .pc files found in $pc_dir — skipping audit."
        return 0
    fi

    log_info "${TARGET_MARK} Correcting $STAGENAME .pc files..."

    local sl="--follow-symlinks"

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

        # If the path matches the prefix or is nested within it
        if [[ "$path" == "$FFBUILD_PREFIX"* ]]; then
            # If the path is just the root of the includes
            if [[ "$path" == "$FFBUILD_PREFIX/include" ]]; then
                echo "\${includedir}"
            else
                # If the path is deeper (e.g. /include/openjpeg-2.5),
                # save the relative path from ${includedir}
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

        # If the path is not recognized, return its original
        echo "$path"
        return 0
    }

    # helper escape string for use as a literal sed pattern
    sed_escape() { printf '%s' "$1" | sed 's/[[\.*^$()+?{|]/\\&/g'; }

    # collect all .pc files into an array and display a list of found files
    log_debug "Correcting values in .pc files:"
    mapfile -t PC_FILES < <(find "$pc_dir" -maxdepth 1 -name "*.pc")
    [[ ${#PC_FILES[@]} -eq 0 ]] && return 0
    for pc in "${PC_FILES[@]}"; do
        echo "$pc" >&2
    done

    find "$pc_dir" -maxdepth 2 -name "*.pc" | while read -r pc; do
        [[ -f "$pc" ]] || continue
        log_debug "Processing: $(basename "$pc")"

        # Check if the source file already contains a specific path
        local original_inc=$(grep "^includedir=" "$pc" | cut -d'=' -f2-)

        # Recreate path variables
        sed -i $sl '/^prefix=/d; /^exec_prefix=/d; /^libdir=/d; /^includedir=/d; /^bindir=/d; /^libdir64=/d' "$pc"

        # If the original path was deeper than the base path, restore it
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
                    # attempt to normalize. If the function returns 1 or empty,
                    # keep the original path to avoid losing it.
                    local normalized
                    normalized=$(normalize_include_path "$path") || normalized="$path"
                    if ! echo "$seen_paths" | grep -qF "x$normalized"; then
                        normalized_cflags="$normalized_cflags -I$normalized"
                        seen_paths="$seen_paths x$normalized"
                    fi
                else
                    # Preserve macros (-D) and other flags
                    normalized_cflags="$normalized_cflags $flag"
                fi
            done
            # guarantee the presence of a main path if there suddenly wasn't one
            if [[ ! "$normalized_cflags" == *"\${includedir}"* ]]; then
                 normalized_cflags="-I\${includedir} $normalized_cflags"
            fi
            # clear the gaps and write down
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

        # Libs Handling (Improved Capture for Multi-Library Packages)
        local libs_line=$(grep "^Libs:" "$pc" | cut -d':' -f2- | xargs)
        # Look for a path -L
        local lib_path=$(echo "$libs_line" | grep -oE '\-L[^ ]+' | head -n1)
        [[ -z "$lib_path" ]] && lib_path='-L${libdir}'

        # base name (e.g. 'lcms2' from 'lcms2.pc'). strip leading 'lib' prefix
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
        sed -i $sl 's/-lc //g;s/-lwinapi_kernel32//g;s/-lzlib\b/-lz/g' "$pc"
        # Fixing duplicate lib prefixes
        sed -i $sl 's/ -l-l/ -l/g' "$pc"
        # Remove the forward slash from the Cflags line
        sed -i $sl '/^Cflags:/ s|\${includedir}/\([[:space:]]\|$\)|\${includedir}\1|g' "$pc"

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

# ========================
# DEPENDENCY AUDIT POLICY
# ========================

# By default, auditing is ALWAYS performed (return 1) because it is too useful
should_skip_post_audit() {
    [[ -z "$STAGENAME" ]] && return 1

    [[ "${GLOBAL_SKIP_POST_DEP_AUDIT:-0}" == "1" ]] && return 0

    case "$STAGENAME" in
        # add here rare components that do not generate binaries/libraries
        # like header components
        *"vulkan-headers"|*"spirv-headers"|*"mingw-std-threads"|*"decklink"|*"zz-final")
            return 0 # Yes, SKIP audit for this component
            ;;
        *) 
            return 1 # No, for everyone else, DO NOT skip (perform audit)
            ;;
    esac
}
export -f should_skip_post_audit

get_deps_list() {
    set +o pipefail 

    if should_skip_post_audit; then
        return 0
    fi

    if [[ "${FFBUILD_VERBOSE:-0}" -lt 1 ]]; then
        return 0
    fi

    [[ ! -d "$INSTALL_ROOT" ]] && return 0

    log_info "${LOGS_MARK} Starting dependency audit for stage: $STAGENAME"

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

    # Create a temporary file to collect output
    local tmp_out=$(mktemp)

    # Calculate the total weight of installed component files
    local total_size="0"
    if [[ -d "$INSTALL_ROOT" ]]; then
        total_size=$(du -sh "$INSTALL_ROOT" | awk '{print $1}')
    fi

    # Search for pkg-config dependencies
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
                    # We get a tree, filter out system noise
                    tree_out=$("$cmd" -n -p "$file" 2>/dev/null | grep -Ev "$sys_regex" || true)

                    if [[ -n "$tree_out" ]]; then
                        # Highlight missing libraries in red# Check for "not found" lines in lddtree output
                        if echo "$tree_out" | grep -q "not found"; then
                            # Highlight missing libraries in red
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
        # Check RPATH / RUNPATH
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

            # External Dependency Management (IMP)
            raw_imports=$("${tc}-nm" -uA "$file" 2>/dev/null || true)
            clean_imports=""
            if [[ -n "$raw_imports" ]]; then
                clean_imports=$(echo "$raw_imports" | \
                    grep -Ev "(__mingw_|_Unwind_|__gcc_|___chkstk|__stack_chk|__main)" | \
                    awk -F: "{ 
                        split(\$NF, a, \" \"); 
                        sym = a[2]; 
                        if (sym != \"\") printf \"  ${LOG_WARN}•${NC} %-15s ${GREY_B}←${NC} %s\n\", \$2, sym 
                    }" | sort -u | head -n ${LOG_RAW_SYMB})
            fi

            # Collecting real exports (EXP)
            raw_exports=$("${tc}-nm" -g --defined-only "$file" 2>/dev/null || true)
            clean_exports=""
            if [[ -n "$raw_exports" ]]; then
                clean_exports=$(echo "$raw_exports" | \
                    grep -Ev "(__mingw_|_Unwind_|__gcc_|___chkstk|__stack_chk|__main)" | \
                    awk "{
                        sym = (\$3 == \"\") ? \$2 : \$3;
                        type = (\$3 == \"\") ? \$1 : \$2;
        
                        if (sym !~ /^(\.)/ && sym != \"\" && type ~ /[TTDDRR]/) {
                            printf \"  ${LOG_INFO}•${NC} ${CYAN_B}→${NC} ${GREEN}%s${NC}\n\", sym
                        }
                    }" | sort -u | head -n ${LOG_RAW_SYMB})
            fi

            if [[ -n "$clean_imports" || -n "$clean_exports" ]]; then
                printf "\n%b %bSYMBOL ANALYSIS%b for %s:\n" "$x_mark" "${YELLOW}" "${NC}" "$file"
                if [[ -n "$clean_exports" ]]; then
                    printf " %b↳ EXPORTED FUNCTIONS (What this library provides):%b\n" "${CYAN}" "${NC}"
                    echo "$clean_exports"
                fi
                if [[ -n "$clean_imports" ]]; then
                    printf " %b↳ EXTERNAL DEPENDENCIES (What this library requires):%b\n" "${PURPLE}" "${NC}"
                    echo "$clean_imports"
                fi
            fi
        ' _ {} "$toolchain" "$XCLAM_MARK" >> "$tmp_out" || true
    fi

    # Output
    local error_count=0
    if [[ -f "$tmp_out" ]]; then
        # We count both MISSING (from pkg-config) and NOT FOUND (from lddtree)
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

# ===============================
# VERSION FINDER POLICY (OPT-IN)
# ===============================

# By default is disabled for everyone (return 0) except for whitelisted
should_skip_version_finder() {
    [[ -z "$STAGENAME" ]] && return 0

    # if need to temporarily turn it off everywhere
    [[ "${GLOBAL_DISABLE_VERSION_FINDER:-0}" == "1" ]] && return 0

    case "$STAGENAME" in
        # WHITELIST (Opt-In): Here we list the components that need version searching
        # The function will return 1 (False to skip -> run get_stage_version).
        *"libiconv"|*"gettext"|*"jbigkit"|*"snappy"|*"libxxhash"|*"libdatachannel"|*"libmpg123"*|*"cryptopp"|*"giflib"|*"svtav1"|*"libavif"|*"quirc"|*"spirv-cross"|*"amf"|*"leptonica"|*"opencl"|*"openvino"|*"soundtouch"|*"libcodec2"|*"libgsm"|*"libmad"|*"libmp3lame"|*"libmpeghdec"|*"mpeghe"|*"flite"|*"x264"|*"x265"|*"xvid"|*"xevd"|*"vapoursynth")
            return 1 
            ;;
        # For all others, skip by default (search is disabled)
        *) 
            return 0 
            ;;
    esac
}
export -f should_skip_version_finder

# Get the version VER_FULL=$(get_stage_version)
get_stage_version() {
    if should_skip_version_finder; then
        return 0
    fi

    local version_file=".ffbuild_version"
    local global_version_file=""

    if [[ -n "${STAGENAME:-}" ]]; then
        local base_build_dir="${ROOT_DIR:-/build}"
        if [[ -d "${base_build_dir}/${STAGENAME}" ]]; then
            global_version_file="${base_build_dir}/${STAGENAME}/${version_file}"
        fi
    fi

    # If the global path could not be calculated or there is no file, search for the file up the tree
    if [[ -z "$global_version_file" || ! -f "$global_version_file" ]]; then
        local current_dir="$PWD"
        # go up a maximum of 3 levels in search of a file
        for _ in {1..3}; do
            if [[ -f "${current_dir}/${version_file}" ]]; then
                global_version_file="${current_dir}/${version_file}"
                break
            fi
            # Preventing system root access
            [[ "$current_dir" == "/" ]] && break
            current_dir=$(dirname "$current_dir")
        done
    fi

    # 1. Check for cached version first
    if [[ -n "$global_version_file" && -f "$global_version_file" ]]; then
        local cached_ver=$(cat "$global_version_file" 2>/dev/null | xargs)
        if [[ -n "$cached_ver" ]]; then
            echo "$cached_ver"
            return 0
        fi
    fi

    # Define verbose logger locally
    ver_log() { 
        if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then 
            log_debug "$*" >&2; 
        fi 
    }

    ver_log "${LOG_WARN}--- STARTING VERSION DETECTION FOR:${NC} ${GREY_B}${STAGENAME:-$PWD}${NC} ${LOG_WARN}---${NC}"

    local ver=""
    local current_repo=""
    local current_commit=""

    # 2. Determine Repo/Commit
    if [[ -n "${SCRIPT_REPO:-}" ]]; then
        current_repo="$SCRIPT_REPO"
        current_commit="${SCRIPT_COMMIT:-}"
    else
        for i in {1..9}; do
            local repo_var="SCRIPT_REPO$i"
            local commit_var="SCRIPT_COMMIT$i"
            if [[ -n "${!repo_var:-}" ]]; then
                current_repo="${!repo_var}"
                current_commit="${!commit_var:-}"
                ver_log "Selected MULTI-REPO Index $i: $current_repo"
                break
            fi
        done
    fi

    ver_log "Active Repo: $current_repo"
    ver_log "Active Commit: $current_commit"

    # Helper to clean version strings
    clean_ver() {
        local v="$1"
        # Remove quotes, spaces, 'v', 'R', etc.
        echo "$v" | sed -E 's/^[vRr_-]+//; s/["'\'']//g; s/^[[:space:]]+//; s/[[:space:]]+$//' | head -n1
    }

    # Local File Detection (HIGHEST PRIORITY)

    # A. libmpg123: Parse MPG123_MAJOR, MINOR, PATCH from src/version.h
    if [[ "$STAGENAME" == *"libmpg123"* ]]; then
        local h_file="src/version.h"
        [[ ! -f "$h_file" ]] && h_file=$(find . -maxdepth 3 -name "version.h" -path "*/src/*" 2>/dev/null | head -n1)
        if [[ -n "$h_file" && -f "$h_file" ]]; then
            local maj=$(grep -E '^#define\s+MPG123_MAJOR\s+' "$h_file" 2>/dev/null | awk '{print $NF}' || true)
            local min=$(grep -E '^#define\s+MPG123_MINOR\s+' "$h_file" 2>/dev/null | awk '{print $NF}' || true)
            local pat=$(grep -E '^#define\s+MPG123_PATCH\s+' "$h_file" 2>/dev/null | awk '{print $NF}' || true)

            maj=$(echo "$maj" | grep -oE '[0-9]+' | head -n1)
            min=$(echo "$min" | grep -oE '[0-9]+' | head -n1)
            pat=$(echo "$pat" | grep -oE '[0-9]+' | head -n1)

            if [[ -n "$maj" && -n "$min" ]]; then
                ver="${maj}.${min}.${pat:-0}"
                ver_log "Found mpg123 version in $h_file: ${LOG_INFO}$ver${NC}"
            fi
        fi
    fi

    # B. libflite: Parse PROJECT_VERSION from config/project.mak
    if [[ "$STAGENAME" == *"flite"* ]]; then
        local mak_file="config/project.mak"
        [[ ! -f "$mak_file" ]] && mak_file=$(find . -maxdepth 3 -name "project.mak" 2>/dev/null | head -n1)
        if [[ -n "$mak_file" && -f "$mak_file" ]]; then
            ver=$(grep -E '^PROJECT_VERSION\s*=' "$mak_file" 2>/dev/null | grep -oE '[0-9.]+' || true)
            [[ -n "$ver" ]] && ver_log "Found flite version in $mak_file: ${LOG_INFO}$ver${NC}"
        fi
    fi

    # C. libgsm: Parse "Release 1.0 Patchlevel 24" from ChangeLog
    if [[ "$STAGENAME" == *"libgsm"* ]]; then
        local changelog="ChangeLog"
        if [[ -f "$changelog" ]]; then
            ver=$(grep -i "Release.*Patchlevel" "$changelog" 2>/dev/null | head -n1 | sed -E 's/.*Release[[:space:]]+([0-9]+\.[0-9]+)[[:space:]]+Patchlevel[[:space:]]+([0-9]+).*/\1.\2/I' || true)
            if [[ -z "$ver" || "$ver" == *"Release"* ]]; then
                ver=$(grep -i "Release 1.0" "$changelog" 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+' || true)
                [[ -n "$ver" ]] && ver="${ver}.0"
            fi
            [[ -n "$ver" ]] && ver_log "Found gsm version in ChangeLog: ${LOG_INFO}$ver${NC}"
        fi
    fi

    # giflib: Parse GIFLIB_MAJOR, MINOR, RELEASE from gif_lib.h
    if [[ "$STAGENAME" == *"giflib"* ]]; then
        local h_file="gif_lib.h"
        [[ ! -f "$h_file" ]] && h_file=$(find . -maxdepth 3 -name "gif_lib.h" 2>/dev/null | head -n1)

        if [[ -n "$h_file" && -f "$h_file" ]]; then
            local maj=$(grep -E '^#define\s+GIFLIB_MAJOR\s+' "$h_file" 2>/dev/null | awk '{print $NF}' || true)
            local min=$(grep -E '^#define\s+GIFLIB_MINOR\s+' "$h_file" 2>/dev/null | awk '{print $NF}' || true)
            local pat=$(grep -E '^#define\s+GIFLIB_RELEASE\s+' "$h_file" 2>/dev/null | awk '{print $NF}' || true)

            maj=$(echo "$maj" | grep -oE '[0-9]+' | head -n1)
            min=$(echo "$min" | grep -oE '[0-9]+' | head -n1)
            pat=$(echo "$pat" | grep -oE '[0-9]+' | head -n1)

            if [[ -n "$maj" && -n "$min" ]]; then
                ver="${maj}.${min}.${pat:-0}"
                ver_log "Found giflib version in $h_file: ${LOG_INFO}$ver${NC}"
            fi
        fi
    fi

    # ffnvcodec: Parse raw CUDA_VERSION from dynlink_cuda.h
    if [[ "$STAGENAME" == *"ffnvcodec"* ]]; then
        local h_file="include/ffnvcodec/dynlink_cuda.h"
        [[ ! -f "$h_file" ]] && h_file=$(find . -maxdepth 3 -name "dynlink_cuda.h" 2>/dev/null | head -n1)

        if [[ -n "$h_file" && -f "$h_file" ]]; then
            local CUDA_VERSION=$(grep -E '^#define\s+CUDA_VERSION\s+' "$h_file" 2>/dev/null | awk '{print $NF}' || true)
            local ver=$(echo "$CUDA_VERSION" | grep -oE '[0-9]+' | head -n1)

            if [[ -n "$ver" ]]; then
                ver_log "Found CUDA_VERSION in $h_file: ${LOG_INFO}$ver${NC}"
            fi
        fi
    fi

    # svt-av1
    if [[ "$STAGENAME" == *"svtav1"* ]]; then
        # local svtav1="svt-av1-tritium/CMakeLists.txt"
        local svtav1=$(find . -maxdepth 2 -name "CMakeLists.txt" -print -quit 2>/dev/null)
        ver_log "SVT-AV1 detected: parsing version from CMakeLists.txt..."
        ver="" # Reset previous values

        if [[ -n "$svtav1" && -f "$svtav1" ]]; then
            while IFS= read -r line; do
                if [[ "$line" =~ project.*VERSION[[:space:]]+([0-9.]+) ]]; then
                    ver="${BASH_REMATCH[1]}"
                    break
                fi
            done < "$svtav1"
        fi

        [[ -n "$ver" ]] && ver_log "Found svtav1 version in CMakeLists.txt: ${LOG_INFO}$ver${NC}"
    fi

    # leptonica
    if [[ "$STAGENAME" == *"leptonica"* ]]; then
        local leptonica_cm=$(find . -maxdepth 2 -name "CMakeLists.txt" -print -quit 2>/dev/null)
        ver_log "Leptonica detected: parsing version from CMakeLists.txt..."
        ver=""

        if [[ -n "$leptonica_cm" && -f "$leptonica_cm" ]]; then
            ver=$(tr '\n' ' ' < "$leptonica_cm" | sed -nE 's/.*project\([^)]*VERSION[[:space:]]+([0-9.]+).*/\1/p')
        fi

        [[ -n "$ver" ]] && ver_log "Found leptonica version in CMakeLists.txt: ${LOG_INFO}$ver${NC}"
    fi

    # D. libxvid: Handle deep paths and XVID_MAKE_VERSION
    if [[ "$STAGENAME" == *"xvid"* ]]; then
        # Xvid is often in a subfolder 'xvidcore'
        local xvid_h=""
        if [[ -f "xvidcore/src/xvid.h" ]]; then
            xvid_h="xvidcore/src/xvid.h"
        else
            xvid_h=$(find . -maxdepth 4 -name "xvid.h" -path "*/src/*" 2>/dev/null | head -n1)
        fi

        if [[ -n "$xvid_h" && -f "$xvid_h" ]]; then
            # Parse XVID_MAKE_VERSION(1,4,-127) -> 1.4.-127 (or handle negative)
            # Or look for XVID_VERSION which might be a macro call
            local raw_ver=$(grep -E '#define\s+XVID_VERSION\s+' "$xvid_h" 2>/dev/null | head -n1 || true)
            if [[ -n "$raw_ver" ]]; then
                # Try to extract numbers from XVID_MAKE_VERSION(a,b,c)
                local maj min pat
                maj=$(echo "$raw_ver" | grep -oE 'XVID_MAKE_VERSION\s*\(\s*([0-9]+)' | grep -oE '[0-9]+' | head -n1 || true)
                min=$(echo "$raw_ver" | grep -oE 'XVID_MAKE_VERSION\s*\([0-9]+,\s*([0-9-]+)' | grep -oE '[0-9-]+' | tail -n1 | sed 's/^,//' || true)
                # If we can't parse the macro, fallback to tag search
                if [[ -n "$maj" && -n "$min" ]]; then
                    # Handle negative patch (e.g., -127) -> treat as 0 or skip? 
                    # Usually XVID_PATCH is positive in releases. 
                    # If the macro is XVID_MAKE_VERSION(1,4,-127), it's a dev version.
                    # Let's just try to get the numbers:
                    ver="${maj}.${min}"
                    # If patch is negative, we might just use maj.min or look for a tag
                    if [[ "$min" == *"-"* || "$maj" == *"-"* ]]; then
                        ver="" # Invalid dev version, fallback to tags
                    fi
                fi
            fi
            [[ -n "$ver" ]] && ver_log "Found xvid version in $xvid_h: ${LOG_INFO}$ver${NC}"
        fi
    fi

    # E. vapoursynth: Parse version from meson.build (version: '77')
    if [[ "$STAGENAME" == *"vapoursynth"* ]]; then
        local vapor="meson.build"
        ver=$(grep -E "^\s*version\s*:\s*['\"][0-9]+['\"]" "$vapor" 2>/dev/null | head -n1 | sed -E "s/.*version\s*:\s*['\"]([0-9]+)['\"].*/\1/" || true)
        [[ -n "$ver" ]] && ver_log "Found vapoursynth version in meson.build: ${LOG_INFO}$ver${NC}"
    fi

    # quirc lib
    if [[ "$STAGENAME" == *"quirc"* ]]; then
        local make_file="Makefile"
        if [[ -f "$make_file" ]]; then
            ver=$(grep -E '^\s*LIB_VERSION\s*=' "$make_file" 2>/dev/null | awk -F'=' '{print $NF}' | xargs || true)
            ver=$(echo "$ver" | grep -oE '[0-9]+(\.[0-9]+)+[^ ]*' | head -n1 || true)
            if [[ -n "$ver" ]]; then
                ver_log "Found quirc version in $make_file: ${LOG_INFO}$ver${NC}"
            fi
        fi
    fi

    # jbigkit lib
    if [[ "$STAGENAME" == *"jbigkit"* ]]; then
        local h_file="libjbig/jbig.h"
        [[ ! -f "$h_file" ]] && h_file=$(find . -maxdepth 3 -name "jbig.h" -path "*/libjbig/*" 2>/dev/null | head -n1)
        if [[ -n "$h_file" && -f "$h_file" ]]; then
            local maj=$(grep -E '^#define\s+JBG_VERSION_MAJOR\s+' "$h_file" 2>/dev/null | grep -oE '[0-9]+' || true)
            local min=$(grep -E '^#define\s+JBG_VERSION_MINOR\s+' "$h_file" 2>/dev/null | grep -oE '[0-9]+' || true)

            if [[ -n "$maj" && -n "$min" ]]; then
                ver="${maj}.${min}"
            else
                ver=$(grep -E '^#define\s+JBG_VERSION\s+' "$h_file" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1 || true)
            fi

            if [[ -n "$ver" ]]; then
                ver_log "Found jbigkit version in $h_file: ${LOG_INFO}$ver${NC}"
            fi
        fi
    fi

    # F. Generic Fallbacks (CMake, PC, Headers, Autotools)
    # Only run these if we haven't found a version yet
    if [[ -z "$ver" ]]; then
        # 1. VERSION files
        local txt_file=$(find . -maxdepth 2 \( -name "VERSION" -o -name "version.txt" -o -name "VERSION.txt" -o -name "version" \) 2>/dev/null | head -n 1)
        if [[ -n "$txt_file" && -f "$txt_file" ]]; then
            ver=$(head -n1 "$txt_file" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' 2>/dev/null | head -n 1 || true)
            [[ -n "$ver" ]] && ver_log "Found in VERSION file ($txt_file): ${LOG_INFO}$ver${NC}"
        fi

        # 2. CMakeLists.txt
        if [[ -z "$ver" && -f "CMakeLists.txt" ]]; then
            ver=$(grep -Pzo 'project\s*\([^)]*VERSION\s+([0-9.]+)' CMakeLists.txt 2>/dev/null | tr -d '\0' | grep -oE '[0-9]+(\.[0-9]+)+' 2>/dev/null | head -n1 || true)
            [[ -n "$ver" ]] && ver_log "Found in CMakeLists project files: ${LOG_INFO}$ver${NC}"

            if [[ -z "$ver" ]]; then
                local v_maj=$(grep -iE 'SET\s*\(\s*VERSION_MAJOR' CMakeLists.txt 2>/dev/null | grep -oE '[0-9]+' 2>/dev/null | head -n1 || true)
                local v_min=$(grep -iE 'SET\s*\(\s*VERSION_MINOR' CMakeLists.txt 2>/dev/null | grep -oE '[0-9]+' 2>/dev/null | head -n1 || true)
                local v_pat=$(grep -iE 'SET\s*\(\s*VERSION_(PATCH|BUILD)' CMakeLists.txt 2>/dev/null | grep -oE '[0-9]+' 2>/dev/null | head -n1 || true)
                [[ -n "$v_maj" && -n "$v_min" ]] && ver="${v_maj}.${v_min}.${v_pat:-0}"
                [[ -n "$ver" ]] && ver_log "Found in CMakeLists custom vars: ${LOG_INFO}$ver${NC}"
            fi
        fi

        # 3. Meson.build (Generic)
        if [[ -z "$ver" && "$STAGENAME" != *"vapoursynth"* ]]; then
            if [[ -f "meson.build" ]]; then
                ver=$(grep -i "version\s*:" meson.build 2>/dev/null | grep -v "meson_version" | grep -oE "[0-9]+(\.[0-9]+)+" | head -n 1 || true)
                [[ -n "$ver" ]] && ver_log "Found in Meson: ${LOG_INFO}$ver${NC}"
            fi
        fi

        # 4. .pc files
        if [[ -z "$ver" ]]; then
            local pc_file=$(find . -maxdepth 3 \( -name "*.pc.in" -o -name "*.pc" \) ! -path "*/build/*" ! -path "*/_build/*" 2>/dev/null | head -n 1)

            if [[ -n "$pc_file" && -f "$pc_file" ]]; then
                ver=$(grep -i "^Version:" "$pc_file" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+[^ ]*' 2>/dev/null | head -n 1 || true)
                [[ -n "$ver" ]] && ver_log "Found in PC file ($pc_file): ${LOG_INFO}$ver${NC}"
            fi
        fi

        # 5. Headers (Generic)
        if [[ -z "$ver" ]]; then
            local h_file=$(find . -maxdepth 3 \( -name "version.h" -o -name "*_version.h" \) 2>/dev/null | head -n 1)
            if [[ -n "$h_file" && -f "$h_file" ]]; then
                local maj=$(grep -iE 'define\s+.*VERSION_MAJOR' "$h_file" 2>/dev/null | grep -oE '[0-9]+' 2>/dev/null | head -n1 || true)
                local min=$(grep -iE 'define\s+.*VERSION_MINOR' "$h_file" 2>/dev/null | grep -oE '[0-9]+' 2>/dev/null | head -n1 || true)
                local pat=$(grep -iE 'define\s+.*VERSION_(MICRO|PATCH|BUILD)' "$h_file" 2>/dev/null | grep -oE '[0-9]+' 2>/dev/null | head -n1 || true)

                if [[ -n "$maj" && -n "$min" ]]; then
                    ver="${maj}.${min}.${pat:-0}"
                else
                    local ver_str=$(grep -iE 'define\s+VERSION\s+"?([0-9.]+)"?' "$h_file" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)
                    [[ -n "$ver_str" ]] && ver="$ver_str"
                fi
                [[ -n "$ver" ]] && ver_log "Found in Header ($h_file): ${LOG_INFO}$ver${NC}"
            fi
        fi

        # 6. Autotools
        if [[ -z "$ver" ]]; then
            local conf_ac=$(find . -maxdepth 2 \( -name "configure.ac" -o -name "configure.in" \) 2>/dev/null | head -n 1)
            if [[ -n "$conf_ac" && -f "$conf_ac" ]]; then
                ver=$(grep -m1 "AC_INIT" "$conf_ac" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' 2>/dev/null | head -n 1 || true)
                [[ -n "$ver" ]] && ver_log "Found in Autotools: ${LOG_INFO}$ver${NC}"
            fi
        fi
    fi

    # opencl (OpenCL-Headers)
    # CMakeLists.txt says "3.0", but releases are date-based (v2026.05.29).
    if [[ "$STAGENAME" == *"opencl"* ]]; then
        ver_log "OpenCL detected: Skipping CMake version, forcing remote tag lookup."
        ver="" # Force empty to trigger remote check immediately
    fi

    # openvino (Intel OpenVINO)
    if [[ "$STAGENAME" == *"openvino"* ]]; then
        ver_log "OpenVINO detected: Skipping generic file versions, forcing remote tag lookup."
        ver="" # Reset the version to ensure Git tag parsing
    fi

    # avisynth
    if [[ "$STAGENAME" == *"avisynth"* ]]; then
        ver_log "Avisynth detected: Skipping generic file versions, forcing remote tag lookup."
        ver=""
    fi

    # Aggressive parsing of any archive types (tar.gz, xz, bz2, zst, tgz, zip, 7z)
    if [[ "$current_repo" =~ \.(tar\.[a-z0-9]+|tgz|zip|7z|rar)$ ]]; then
        ver_log "Archive link detected, parsing version from URL..."
        ver="" # Reset the version
        # searches for a separator (- or _) followed by a digit.
        # captures the entire string of digits, periods, hyphens, and letters BEFORE expanding the archive.
        # Example: gettext-1.0.tar.gz -> 1.0; libwebp-1.4.0-rc1.zip -> 1.4.0-rc1
        if [[ "$current_repo" =~ [-_]([0-9][a-zA-Z0-9.-]*)\.(tar\.[a-z0-9]+|tgz|zip|7z|rar)$ ]]; then
            ver="${BASH_REMATCH[1]}"
            ver_log "Extracted version from archive name: ${LOG_INFO}$ver${NC}"
        fi
    fi

    # 4. Remote Git Detection
    if [[ -z "$ver" ]]; then
        if [[ -n "$current_repo" ]]; then
            if ! command -v git &> /dev/null; then
                ver_log "WARNING: git not found in PATH, skipping remote version check"
            else
                ver_log "No local version found. Attempting remote git check..."

                if [[ -n "$current_commit" ]]; then
                    ver_log "Checking remote tags for commit: ${current_commit:0:7}"

                    local remote_refs
                    remote_refs=$(timeout 10 git ls-remote --tags "$current_repo" 2>/dev/null || true)

                    if [[ -n "$remote_refs" ]]; then
                        local matched_tag
                        matched_tag=$(echo "$remote_refs" | grep -E "^${current_commit:0:7}" | grep "refs/tags/" | head -n1 | awk -F'/' '{print $NF}' | sed 's/\^{}$//' || true)

                        if [[ -n "$matched_tag" ]]; then
                            ver=$(clean_ver "$matched_tag")
                            ver_log "Found remote tag matching commit: ${LOG_INFO}$ver${NC}"
                        else
                            # OpenCL Headers - prefer date-based tags
                            if [[ "$STAGENAME" == *"opencl"* ]]; then
                                # Filter for tags starting with 'v' followed by a date pattern (YYYY.MM.DD)
                                local date_tag
                                date_tag=$(echo "$remote_refs" | grep "refs/tags/v[0-9]\{4\}\.[0-9]\{2\}\.[0-9]\{2\}" | tail -n1 | awk -F'/' '{print $NF}' | sed 's/\^{}$//' || true)
                                if [[ -n "$date_tag" ]]; then
                                    ver=$(clean_ver "$date_tag")
                                    ver_log "Found OpenCL date tag: ${LOG_INFO}$ver${NC}"
                                fi
                            fi

                            # OpenVINO (Ищет теги вида 2026.2.0 или v2026.2.0)
                            if [[ "$STAGENAME" == *"openvino"* ]]; then
                                local vino_tag
                                vino_tag=$(echo "$remote_refs" | grep -E "refs/tags/v?[0-9]+\.[0-9]+\.[0-9]+" | tail -n1 | awk -F'/' '{print $NF}' | sed 's/\^{}$//' || true)
                                if [[ -n "$vino_tag" ]]; then
                                    ver=$(clean_ver "$vino_tag")
                                    ver_log "Found OpenVINO version tag: $ver"
                                fi
                            fi

                            if [[ -z "$ver" ]]; then
                                local last_tag
                                last_tag=$(echo "$remote_refs" | grep "refs/tags/" | tail -n1 | awk -F'/' '{print $NF}' | sed 's/\^{}$//' || true)

                                if [[ -n "$last_tag" ]]; then
                                    local check_tag=$(clean_ver "$last_tag")
                                    if [[ "$check_tag" == "xvidcore" || "$check_tag" == "flite" || "$check_tag" == "mpg123" || -z "$check_tag" ]]; then
                                        ver_log "Remote tag '$last_tag' is invalid or just a repo name, skipping."
                                    else
                                        ver="$check_tag"
                                        ver_log "Fallback to last remote tag: ${LOG_INFO}$ver${NC}"
                                    fi
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi

    # 5. Local Git Fallback
    if [[ -z "$ver" && -d ".git" ]]; then
        if command -v git &> /dev/null; then
            local local_git_tag
            local_git_tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
            if [[ -n "$local_git_tag" ]]; then
                ver=$(clean_ver "$local_git_tag")
                ver_log "Found in local .git: ${LOG_INFO}$ver${NC}"
            fi

            if [[ -z "$ver" ]]; then
                ver="git-$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
                ver_log "Local .git found but no tag, using hash: ${LOG_INFO}$ver${NC}"
            fi
        fi
    fi

    # 6. Final Fallbacks (Commit hash or Folder name)
    if [[ -z "$ver" && -n "$current_commit" ]]; then
        ver="git-${current_commit:0:7}"
        ver_log "No tags found anywhere, defaulting to commit hash: ${LOG_INFO}$ver${NC}"
    fi

    # Fallback to folder name
    if [[ -z "$ver" ]]; then
        ver=$(basename "$PWD" | grep -oE '[0-9]+(\.[0-9]+)+[^ ]*' 2>/dev/null | head -n 1 || true)
        [[ -n "$ver" ]] && ver_log "Fallback to folder name: ${LOG_INFO}$ver${NC}"
    fi

    # Default of defaults
    if [[ -z "$ver" ]]; then
        ver="0.0.1"
    fi

    # Final string cleanup does not break the hash if it remains
    if [[ "$ver" == "git-"* ]]; then
        # If it's a hash, keep the git- prefix carefully
        local hash_part="${ver#git-}"
        ver="git-$(echo "$hash_part" | tr -d '"' | tr -d "'" | xargs)"
    else
        # For regular versions, cut off the letters
        ver=$(echo "$ver" | sed -E 's/^[a-zA-Z_-]+//' | tr -d '"' | tr -d "'" | xargs)
    fi

    ver_log "${LOG_WARN}--- FINAL RESULT FOR${NC} ${GREY_B}$STAGENAME${NC}: ${LOG_INFO}$ver${NC} ${LOG_WARN}---${NC}"

    if [[ -n "$global_version_file" ]]; then
        echo "$ver" > "$global_version_file"
    else
        echo "$ver" > "$version_file"
    fi

    echo "$ver"
    return 0
}
export -f get_stage_version

# ======================================
# LIBTOOL ARCHIVES CLEANUP POLICY (.la)
# ======================================

should_skip_post_clean_la_files() {
    # If the stage name is not defined, DO NOT skip
    [[ -z "$STAGENAME" ]] && return 1

    # always skip
    [[ "${GLOBAL_SKIP_POST_CLEAN_LA_FILES:-0}" == "1" ]] && return 0

    case "$STAGENAME" in
        *"example-component"*)
            return 0
            ;;
        *) 
            return 1
            ;;
    esac
}
export -f should_skip_post_clean_la_files

clean_la_files() {
    if [[ "$PREFER_SHARED" == "1" ]]; then
        return 0
    fi

    if should_skip_post_clean_la_files; then
        log_info "${LOCK_MARK} Cleanup of .la files skipped for $STAGENAME"
        return 0
    fi

    local target_dir="$INSTALL_ROOT"
    [[ ! -d "$target_dir" ]] && return 0

    shopt -s nullglob
    local la_files=()
    while IFS= read -r -d '' file; do
        la_files+=("$file")
    done < <(find "$target_dir" -name "*.la" \( -type f -o -type l \) -print0 2>/dev/null)
    shopt -u nullglob

    local count=${#la_files[@]}

    if [[ $count -gt 0 ]]; then
        log_info "${BROOM_MARK} Cleaning up libtool archives (.la) in $target_dir"
        rm -f "${la_files[@]}" 2>/dev/null
        log_info "${CHECK_MARK} Removed $count .la files (including symlinks) from prefix."
    else
        log_debug "No .la files found to clean for $STAGENAME."
    fi
}
export -f clean_la_files

# =================
# STRIPING POLICY
# =================

should_skip_post_strip() {
    [[ -z "$STAGENAME" ]] && return 1

    [[ "${GLOBAL_SKIP_POST_STRIP:-0}" == "1" ]] && return 0

    case "$STAGENAME" in
        # rust libs; frack it strip anyway
        # *"rav1e"|*"librsvg"|*"quiche")
            # return 0 
            # ;;
        # headers
        *"vulkan-headers"|*"spirv-headers"|*"mingw-std-threads"|*"ffnvcodec"|*"decklink"|*"zz-final")
            return 0 
            ;;
        *) 
            return 1 
            ;;
    esac
}
export -f should_skip_post_strip

strip_files() {
    local target_dir="$1"
    local stage_name="$2"

    if should_skip_post_strip; then
        log_info "${LOCK_MARK} Stripping skipped for $stage_name"
        return 0
    fi

    [[ ! -d "$target_dir" ]] && return 0

    local _strip_cmd="${STRIP}"
    local _objcopy_cmd="${OBJCOPY}"
    local size_before=$(du -sh "$target_dir" | cut -f1)

    if [[ "$DEBUG_MODE" == "1" ]]; then
        log_info "${BROOM_MARK} Extracting symbols from $stage_name... [Size: ${GREY_B}$size_before${NC}]"
        find "$target_dir" -type f \
            \( -name "*.exe" -o -name "*.dll" -o -name "*.so*" \) | while read -r file; do
                if $_objcopy_cmd --help | grep -q "only-keep-debug" 2>/dev/null; then
                    local debug_file="${file}.debug"
                    "$_objcopy_cmd" --only-keep-debug "$file" "$debug_file" 2>/dev/null || continue
                    "$_strip_cmd" --strip-debug "$file" 2>/dev/null || continue
                    cd "$(dirname "$file")"
                    "$_objcopy_cmd" --add-gnu-debuglink="$(basename "$debug_file")" "$(basename "$file")" 2>/dev/null || true
                    cd - >/dev/null
                fi
            done
    else
        if [[ "${FFMPEG_BUILD_STAGE:-0}" == "1" ]]; then
            log_info "${BROOM_MARK} Stripping $stage_name from unneeded symbols: [Size: ${GREY_B}$size_before${NC}]"
            find "$target_dir" -type f \( -name "*.exe" -o -name "*.dll" \) -exec "$_strip_cmd" --strip-unneeded {} + 2>/dev/null || true
        else
            log_info "${BROOM_MARK} Stripping $stage_name from debug symbols: [Size: ${GREY_B}$size_before${NC}]"
            find "$target_dir" -type f \( -name "*.exe" -o -name "*.dll" \) -exec "$_strip_cmd" --strip-debug {} + 2>/dev/null || true
        fi
        find "$target_dir" -type f \( -name "*.a" -o -name "*.so*" \) ! -name "*.dll.a" -exec "$_strip_cmd" --strip-debug {} + 2>/dev/null || true
    fi

    local size_after=$(du -sh "$target_dir" | cut -f1)

    if [[ "$size_before" == "$size_after" ]]; then
        log_info "${CHECK_MARK} Splitting/Stripping finished. [Size unchanged: ${GREY_B}$size_after${NC}]"
    else
        log_info "${CHECK_MARK} Splitting/Stripping finished. [$size_before -> ${GREY_B}$size_after${NC}]"
    fi
}
export -f strip_files

# =======================
# AUTO-PATCHING POLICY
# =======================

should_skip_pre_patch() {
    [[ -z "$STAGENAME" ]] && return 1

    [[ "${GLOBAL_SKIP_PRE_PATCH:-0}" == "1" ]] && return 0

    case "$STAGENAME" in
        *"libgsm")
            return 0 # Skip applying patches for libgsm
            ;;
        *) 
            return 1 # For everyone else, try applying patches
            ;;
    esac
}
export -f should_skip_pre_patch

# 1. Standard
# 2. Binary (for CRLF issues)
# 3. Ignore Whitespace
# 4. Max Fuzz (fuzz=3)
apply_patches() {
    if should_skip_pre_patch; then
        log_info "${LOCK_MARK} Patching skipped for $STAGENAME"
        return 0
    fi

    log_info "${SEARCH_MARK} Checking for patches for ${STAGENAME}..."

    local PATCH_DIR="$PATCHES_DIR/$COMPONENT_NAME"
    if [[ ! -d "$PATCH_DIR" ]]; then
        log_info "${CHECK_MARK} No patches folder found for $COMPONENT_NAME"
        return 0
    fi

    # Count the number of .patch files in the folder
    shopt -s nullglob
    local patches_files=("$PATCH_DIR"/*.patch)
    shopt -u nullglob

    if [[ ${#patches_files[@]} -eq 0 ]]; then
        log_info "${CHECK_MARK} No .patch files found in $PATCH_DIR"
        return 0
    fi

    log_info "${SEARCH_MARK} Executing patching chain for ${STAGENAME}..."

    # Save the current folder (where the auto-search for the root took us)
    local CURRENT_ROOT=$(pwd)
    # Save the base build folder
    local BUILD_BASE="/build/$STAGENAME"
    local patch_failed_any=false

    shopt -s nullglob
    for patch in "$PATCH_DIR"/*.patch; do
        local patch_name=$(basename "$patch")
        log_info "${TARGET_MARK} APPLYING PATCH: ${GREY_B}${patch_name}${NC}"

        local success=false
        local last_output=""
        local last_method=""

        # DIRECTORY SEQUENCE. First the current one (from auto-search), then the base one
        for try_dir in "$CURRENT_ROOT" "$BUILD_BASE"; do
            [[ -d "$try_dir" ]] || continue
            pushd "$try_dir" &>/dev/null
            log_debug "Attempting patch in: $(pwd)"

        # Try git am first
        if [[ -d ".git" && "$success" == "false" ]]; then
            local git_opts
            for git_opts in \
                "git am --ignore-space-change --whitespace=fix" \
                "git am --ignore-space-change --whitespace=fix --reject"
            do
                last_method="${git_opts}"
                log_debug "Trying: $git_opts"
                # 'if' suppresses set -e on the command
                if last_output=$(eval "$git_opts" < "$patch" 2>&1); then
                    log_info "${CHECK_MARK} ${GREEN}SUCCESS${NC}: Applied with [$git_opts]"
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
                if git init -q && git add -A && git commit -qm "temp_init" 2>/dev/null; then
                    temp_git=true
                fi
            fi

            local apply_opts
            for apply_opts in \
                "--ignore-space-change --ignore-whitespace" \
                "--ignore-space-change --ignore-whitespace --3way" \
                "--ignore-space-change --ignore-whitespace --recount"
            do
                last_method="git apply ${apply_opts}"
                log_debug "Trying: git apply $apply_opts"
                if last_output=$(git apply $apply_opts "$patch" 2>&1); then
                    log_info "${CHECK_MARK} ${GREEN}SUCCESS${NC}: Applied with [git apply $apply_opts]"
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
                "-p1 -t -N -r -" "-p0 -t -N -r -" \
                "-p1 -t -N -r - --binary" "-p0 -t -N -r - --binary" \
                "-p1 -t -N -r - -l" "-p0 -t -N -r - -l" \
                "-p1 -t -N -r - -l --fuzz=3" "-p0 -t -N -r - -l --fuzz=3"
            do
                last_method="patch ${patch_opts}"
                log_debug "Trying: patch $patch_opts"
                # First check whether the patch will be applied without changing files; &>/dev/null
                if last_output=$(patch --dry-run --silent $patch_opts < "$patch" 2>&1); then
                    # 'if' suppresses set -e on patch exit code
                    if last_output=$(patch $patch_opts < "$patch" 2>&1); then
                        log_info "${CHECK_MARK} ${GREEN}SUCCESS${NC}: Applied with [patch $patch_opts]"
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
            log_error "${RED}FAILED${NC}: All attempts to apply ${GREY_B}${patch_name}${NC} failed."
            log_debug "Last attempt output:\n${last_output}"
            patch_failed_any=true

            # Write a detailed error to the global accumulator
            mkdir -p "$(dirname "$LOG_PATCH_ERRORS")"
            {
                echo "--------------------------------------------------------"
                echo "COMPONENT: $COMPONENT_NAME | PATCH: $patch_name"
                echo "FAILED METHOD: $last_method"
                echo "OUTPUT ERROR:"
                echo "$last_output"
                echo "--------------------------------------------------------"
            } >> "$LOG_PATCH_ERRORS"

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
    if [[ "$FFMPEG_PATCHES" != "1" ]]; then
        return 0
    fi

    local FFMPEG_PATCH_DIR="$PATCHES_DIR/ffmpeg/$FFMPEG_BRANCH"

    [[ -d "$FFMPEG_PATCH_DIR" ]] || { log_info "${CHECK_MARK} No patches found for branch: $FFMPEG_BRANCH"; return 0; }

    log_info "${SEARCH_MARK} Applying FFmpeg patches from: $FFMPEG_PATCH_DIR"

    if [[ ! -d ".git" ]]; then
        log_warn "FFmpeg source is not a git repo. Initializing temporary git for reliable patching..."
        git init -q && git add -A && git commit -qm "base"
    fi

    shopt -s nullglob
    for patch in "$FFMPEG_PATCH_DIR"/*.patch; do
        log_info "${TARGET_MARK} APPLYING PATCH: ${GREY_B}$(basename "$patch")${NC}"

        if git apply --ignore-whitespace --intent-to-add "$patch" 2>/dev/null; then
            log_info "${CHECK_MARK} ${GREEN}SUCCESS${NC}"
            git add -A || true
        else
            log_error "${RED}FAILED${NC} - skipping"
            git reset -q HEAD -- . || true
        fi
    done
    shopt -u nullglob

    return 0
}
export -f apply_ffmpeg_patches

# Function to display the final patch report at the end of the build
show_patch_summary() {
    if [[ -f "$LOG_PATCH_ERRORS" && -s "$LOG_PATCH_ERRORS" ]]; then
        log_info "${TARGET_MARK} ${LOG_ERROR}=== PATCHING FAILURE SUMMARY ===${NC}"
        cat "$LOG_PATCH_ERRORS" >&2
        log_info "${LOG_ERROR}=================================${NC}"
    else
        log_info "${CHECK_MARK} All patches applied or verified successfully across all components!"
    fi
}
export -f show_patch_summary

# ===========================================================================
# REGENERATION POLICY FOR CONFIGURATION SCRIPTS (AUTOCONF/BOOTSTRAP/AUTOGEN)
# ===========================================================================

should_skip_conf_finder() {
    [[ -z "$STAGENAME" ]] && return 0

    [[ "${GLOBAL_DISABLE_CONF_FINDER:-0}" == "1" ]] && return 0

    case "$STAGENAME" in
        # WHITELIST (Opt-In): Regeneration is ALLOWED only for these libraries.
        # The function will return 1 (False to skip -> run conf_finder).
        *"some-broken-legacy-lib"*)
            return 1 
            ;;
        # For ALL other libraries, regeneration is DISABLED/SKIPPED by default.
        *) 
            return 0 
            ;;
    esac
}
export -f should_skip_conf_finder

conf_finder() {
    if should_skip_conf_finder; then
        return 0
    fi

    # If configure is not present, or is old (configure.ac is newer), run regeneration
    if [[ ! -f "configure" || "configure.ac" -nt "configure" ]]; then
        log_info "${SYNC_MARK} conf_finder: Regenerating build files for $STAGENAME..."

        # Create a folder for macros if it is registered, but it does not exist (a common error with libffi)
        local m4_dir=$(grep -oP 'AC_CONFIG_MACRO_DIRS?\(\[\K[^\]]+' configure.ac 2>/dev/null || echo "m4")
        mkdir -p "$m4_dir"

        # try autoreconf first, since it's the most standardized.
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
            log_error "conf_finder: All regeneration attempts failed for $STAGENAME."
            return 1
        fi
    fi
}
export -f conf_finder

# checking flags validity for final FFmpeg build; if found we just drop them and continue
check_and_fix_configure() {
    if [[ "$SAFE_CONFIGURE" != "1" ]]; then
        return 0
    fi

    log_info "SAFE_CONFIGURE: Checking flags for validity..."

    local new_flags=()
    local dropped=()
    local fixed=()

    # Cache help by using advanced search
    local help_output=$(./configure --help)

    for flag in "${CONF_FLAGS[@]}"; do
        # Extract the clear option name for checking (remove --enable-/--disable- and everything after =)
        local clean_opt=$(echo "$flag" | sed -E 's/--[a-z]+-//; s/=.*//')
        local action=$(echo "$flag" | grep -oE "^--(enable|disable)")
        
        # If it's not a standard switch (e.g. --prefix, --cc), check and skip
        if [[ ! "$flag" =~ ^--enable- ]] && [[ ! "$flag" =~ ^--disable- ]]; then
            new_flags+=("$flag")
            continue
        fi

        # Aliasing Block
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
            # add other common errors here
        esac

        # Put flag back (keeping the argument after =, if there was one)
        local suffix=$(echo "$flag" | grep -oE "=.*$" || true)
        # Generate a potentially corrected flag
        local current_flag="${action}-${opt_name}${suffix}"

        # Validation via grep
        # Search help for: --enable-opt_name, --enable-opt_name[=arg], or a description starting with opt_name
        # Use [[:punct:]]? to catch optional [=arg] brackets
        if echo "$help_output" | grep -qE "\--(en|dis)able-${opt_name}([[:punct:]]|=|[[:space:]]|$)"; then
            if [[ "$current_flag" != "$flag" ]]; then
                fixed+=("$flag -> $current_flag")
            fi
            new_flags+=("$current_flag")
        else
            # If it's a specific component (encoder/decoder), check for its presence in the lists
            # But ONLY if it's an exact word match, and not part of another flag
            if echo "$help_output" | grep -qiwE "${opt_name}"; then
                 new_flags+=("$current_flag")
            else
                 dropped+=("$flag")
            fi
        fi
    done

    # Report output
    [ ${#fixed[@]} -ne 0 ] && log_info "${BUILD_MARK} FIXED flags: ${fixed[*]}"
    [ ${#dropped[@]} -ne 0 ] && log_warn "DROPPED invalid flags: ${dropped[*]}"

    CONF_FLAGS=("${new_flags[@]}")
}
export -f check_and_fix_configure

if [[ "${USE_WINE:-0}" = "1" ]]; then
    # Dynamically determining paths for wine
    if [ -d "/opt/ct-ng" ]; then
        MINGW_BIN_PATH="/opt/ct-ng/x86_64-w64-mingw32/x86_64-w64-mingw32/bin"
        if [[ ! -d "$MINGW_BIN_PATH" ]]; then
            # Fallback to quick search if the path is different
            MINGW_BIN_PATH=$(find /opt/ct-ng -type d -path "*/x86_64-w64-mingw32/bin" -print -quit)
        fi
        # If WINEPATH is already set (for example, in a previous layer or call), skip heavy calculations
        if [[ -z "$WINEPATH" ]]; then
            MINGW_BIN_PATH=$(find /opt/ct-ng -maxdepth 5 -type d -name "bin" | grep "x86_64-w64-mingw32/bin" | head -n 1)
    
            if command -v winepath &>/dev/null; then
                # We translate paths only once
                _p_bin=$(winepath -w "${FFBUILD_PREFIX}/bin" 2>/dev/null | tr -d '\r\n')
                _p_lib=$(winepath -w "${FFBUILD_PREFIX}/lib" 2>/dev/null | tr -d '\r\n')
                _m_bin=$(winepath -w "${MINGW_BIN_PATH}" 2>/dev/null | tr -d '\r\n')
    
                if [[ -n "$_p_bin" && -n "$_p_lib" ]]; then
                    export WINEPATH="${_p_bin};${_p_lib};${_m_bin}"
                else
                    # Fallback for environments without Wine running (for example, generation on the host)
                    export WINEPATH="winepath -w ${FFBUILD_PREFIX}/bin:${FFBUILD_PREFIX}/lib:${MINGW_BIN_PATH}"
                fi
            else
                export WINEPATH="winepath -w ${FFBUILD_PREFIX}/bin:${FFBUILD_PREFIX}/lib:${MINGW_BIN_PATH}"
            fi
            # Display information about WINEPATH only when it is created
            [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && log_raw "${DIRS_MARK} WINEPATH (Windows style):" "$WINEPATH"
        fi
    fi
fi

# Determine the operating mode of Wine (take it from ENV or set auto by default)
USE_WINE="${USE_WINE:-1}"
setup_wine_env() {
    # Save the current state set -e
    local errexit_state=$([[ $- =~ e ]] && echo "set -e" || echo "set +e")
    set +e # Temporarily disable stopping on errors

    # Wine globally disabled
    if [[ "${USE_WINE:-0}" != "1" ]]; then
        eval "$errexit_state"; return 0
    fi

    # No stage to inspect
    if [[ -z "$STAGE" || ! -f "$STAGE" ]]; then
        eval "$errexit_state"; return 0
    fi

    # Scan the stage script for patterns that indicate Wine is needed.
    # Search for:
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
        # Run on display 99 without xvfb-run (less overhead)
        ( Xvfb :99 -screen 0 1024x768x16 >/dev/null 2>&1 & )
        local retry=0
        while [[ $retry -lt 50 ]]; do
            DISPLAY=:99 xset -q >/dev/null 2>&1 && break
            sleep 0.4
            (( retry++ ))
        done
        if [[ $retry -ge 50 ]]; then
            log_warn "Xvfb did not start in time - Wine tests may fail"
        fi
    fi

    export DISPLAY=:99

    # Warm up Wine server asynchronously

    ( wineboot -u >/dev/null 2>&1 & )

    eval "$errexit_state"
}
export -f setup_wine_env

ffbuild_dockerdl() {
    [[ -n "$SCRIPT_REPO" ]] && default_dl .
}

# These are DEFAULT implementations component scripts override them.
# Each prints its contribution to stdout. run_stage.sh owns accumulation.
# Collect flags from all scripts in scripts.d for the final ./configure
ffbuild_enabled()      { return 0; }
ffbuild_depends()      { return 0; }
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

export -f ffbuild_enabled ffbuild_depends ffbuild_configure ffbuild_cflags ffbuild_cppflags ffbuild_cxxflags ffbuild_ldflags ffbuild_ldexeflags ffbuild_libs ffbuild_unconfigure ffbuild_uncflags ffbuild_uncxxflags ffbuild_unldexeflags ffbuild_unldflags ffbuild_unlibs

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
 14|17|36|37|38|39|40|41|43|45|46) echo "Core Graphics & Fonts" ;; # PNG, Cairo
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
