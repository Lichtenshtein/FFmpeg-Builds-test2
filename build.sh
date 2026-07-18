#!/bin/bash

set -e
# set -xe

shopt -s globstar
cd "$(dirname "$0")"

source util/vars.sh "${1:-$TARGET}" "${2:-$VARIANT}" \
    || { echo "ERROR: vars.sh failed in build.sh" >&2; exit 1; }

# A hook announcing that we're at the final stage
export FFMPEG_BUILD_STAGE="1"
export STAGENAME="FFmpeg"

if declare -F apply_lto_policy >/dev/null; then
    apply_lto_policy
fi

# Reset statistics for a clean log
# ccache -z > /dev/null
# Reset the seconds counter at the beginning of the stage
SECONDS=0

# Define the cleaning function
cleanup() {
    local exit_code=$? # Remember the exit code (0 - success, >0 - error)

    log_info "Running cleanup (Exit code: $exit_code)..."

    # Delete the temporary build folder (pkgroot, temporary logs, etc.); not "$VARS_DIR"?
    rm -rf "$FFMPEG_PKG_ROOT" 2>/dev/null

    # If the build fails, leave the config log in an accessible location
    if [[ $exit_code -ne 0 && -f "$FFMPEG_CONFIG_LOG" ]]; then
        cp "$FFMPEG_CONFIG_LOG" "${FFBUILD_DESTDIR}/failed_config.log" 2>/dev/null || true
    else
    # Just copy the log to the folder for packaging
        cp "$FFMPEG_CONFIG_LOG" "${FFBUILD_DESTDIR}/config.log" 2>/dev/null || true
    fi

    log_info "Cleanup done."

    log_info "${CACHE_MARK} CCACHE STATISTICS:"
    ccache -s "${OP_VERB2}"
}
# EXIT will always be called: on success, on error, and on interruption
trap cleanup EXIT

# Initializing local (non-exported!) variables
# Clearing FF_ variables before loading to avoid old values
TOTAL_FF_CONFIGURE=""
TOTAL_FF_CFLAGS=""
TOTAL_FF_CXXFLAGS=""
TOTAL_FF_CPPFLAGS=""
TOTAL_FF_LDFLAGS=""
TOTAL_FF_LDEXEFLAGS=""
TOTAL_FF_LIBS=""

log_info "Loading component variables from cache..."

if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
    log_debug "Checking the connection with the variable caches in .vars"
    # Checking the connection to the cache (zlib)
    # If the file is empty, there's a problem with run_stage.sh or vars.sh during component build.
    # If the file isn't empty, but configure is empty, there's a problem with build.sh (in the source or dedupe command)
    # Use nullglob to make the array empty if there are no files.
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

# Dependencies (low numbers) should be at the beginning for CFLAGS
# and at the end for LIBS (but we'll solve this with tac deduplication)
counter=0
while IFS= read -r f; do
    # reset temporary variables before each source
    unset FF_CONFIGURE FF_LIBS FF_CFLAGS FF_CXXFLAGS FF_CPPFLAGS FF_LDFLAGS FF_LDEXEFLAGS
    log_debug "Sourcing $f"
    [[ -s "$f" ]] && source "$f"

    # Accumulate data from the file into final variables
    TOTAL_FF_CONFIGURE+=" ${FF_CONFIGURE:-}"
    TOTAL_FF_LIBS+=" ${FF_LIBS:-}"
    TOTAL_FF_CFLAGS+=" ${FF_CFLAGS:-}"
    TOTAL_FF_LDFLAGS+=" ${FF_LDFLAGS:-}"
    TOTAL_FF_CXXFLAGS+=" ${FF_CXXFLAGS:-}"
    TOTAL_FF_CPPFLAGS+=" ${FF_CPPFLAGS:-}"
    TOTAL_FF_LDEXEFLAGS+=" ${FF_LDEXEFLAGS:-}"

    counter=$((counter + 1))

    # Intermediate cleanup every 20 files,
    # to prevent memory line explosions
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

# load the target variant with its --enable flags ffbuild_configure()
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

# Determine the target option (they can add their own --enable)
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


log_info "Using pre-mounted FFmpeg source..."
if [[ ! -f "$FFMPEG_SOURCE_DIR/configure" ]]; then
    log_error "FFmpeg source not found at $FFMPEG_SOURCE_DIR/configure! Check if it is mounted correctly."
    exit 1
fi

pushd "$FFMPEG_SOURCE_DIR"

# =======================================
# FFMPEG SOURCE PATCHING SECTION 1
# =======================================

# AUTO-PATCHING
apply_ffmpeg_patches

log_info "Patching FFmpeg vf_libvmaf.c to use Pointer ABI..."
# replace the call in the filter source with the transfer of the structure address
sed -i 's/err = vmaf_init(\&s->vmaf, cfg);/err = vmaf_init(\&s->vmaf, \&cfg);/g' "libavfilter/vf_libvmaf.c"
if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
    # check whether the patch was applied (output a line to the log)
    grep -n "vmaf_init" "libavfilter/vf_libvmaf.c"
fi
log_info "Patching FFmpeg ffprobe ABI bug: Changing avtext_context_open to pass options by pointer..."
# change the signature in the header file
sed -i 's/AVTextFormatOptions options,/const AVTextFormatOptions \*options,/g' "fftools/textformat/avtextformat.h"
# change the function declaration in the implementation file
sed -i 's/AVTextFormatOptions options,/const AVTextFormatOptions \*options,/g' "fftools/textformat/avtextformat.c"
# Change only one assignment line inside the body of avtext_context_open,
# so that the data is dereferenced from the pointer back to the context object
sed -i 's/tctx->opts = options;/tctx->opts = *options;/g' "fftools/textformat/avtextformat.c"
# Add an ampersand to the caller in fftools/ffprobe.c
sed -i 's/tf_options, show_data_hash/\&tf_options, show_data_hash/g' "fftools/ffprobe.c"
# Patch the caller in fftools/graph/graphprint.c (add ampersand &)
sed -i 's/tf_options, NULL/\&tf_options, NULL/g' "fftools/graph/graphprint.c"
# Checking the success of the patch rollout in the builder logs
if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
    log_debug "Verifying patches application..."
    grep -n "avtext_context_open" "fftools/textformat/avtextformat.h"
    grep -n "avtext_context_open" "fftools/textformat/avtextformat.c" | head -n 2
    grep -n "avtext_context_open" "fftools/ffprobe.c"
    grep -n "avtext_context_open" "fftools/graph/graphprint.c"
fi

THPENC_C="libavformat/thpenc.c"
if [ -f "$THPENC_C" ]; then
    log_info "Fixing outdated packet_list API inside custom muxer: $THPENC_C..."

    sed -i 's/avpriv_packet_list_put/ff_packet_list_put/g' "$THPENC_C"
    sed -i 's/avpriv_packet_list_get/ff_packet_list_get/g' "$THPENC_C"
    sed -i 's/avpriv_packet_list_free/ff_packet_list_free/g' "$THPENC_C"

    # New ff_packet_list_* functions require "packet_list.h" inclusion instead of old codec ones.
    if ! grep -q '#include "packet_list.h"' "$THPENC_C"; then
        sed -i '2i #include "packet_list.h"' "$THPENC_C"
    fi
fi

# if [[ -f "${FFBUILD_PREFIX}/lib/pkgconfig/ffnvcodec.pc" ]]; then
    # sed -i 's| -I${includedir}/ffnvcodec||g' "${FFBUILD_PREFIX}/lib/pkgconfig/ffnvcodec.pc"
# fi

# TARGET_SEARCH_DIR="${FFBUILD_PREFIX}/lib"
# OBJDUMP="${OBJDUMP}"
# OBJCOPY="${OBJCOPY}"
# log_info "🔎 Starting automatic search for hidden subsystem directives in ${TARGET_SEARCH_DIR}..."
# DYNAMIC_POISON_LIBS=()
# cd "${TARGET_SEARCH_DIR}" || exit 1
# echo "🔎 Searching for object files that request or declare WinMain..."
# for lib in *.a; do
    # RES=$("${NM}" -A "$lib" 2>/dev/null | grep -i "WinMain" || true)
    # if [ ! -z "$RES" ]; then
        # echo -e "\n📦 Library: \033[1;33m$lib\033[0m"
        # echo "$RES"
    # fi
# done

# for lib in *.a; do
    # if "${NM}" "$lib" 2>/dev/null | grep -qi "WinMain" || \
       # strings "$lib" 2>/dev/null | grep -qi "subsystem,windows"; then
        # log_warn "The $lib library contains a reference to WinMain or subsystem:windows!"
        # FOUND_POISONERS+=("$lib")
    # fi
# done
# log_info "🎯 Potential culprits found: ${#FOUND_POISONERS[@]}"

# for lib in *.a; do
    # if $OBJDUMP -s -j .drectve "$lib" 2>/dev/null | grep -E "subsystem|windows|entry" > /dev/null 2>&1; then
        # log_warn "Found hidden directives in: ${lib}"
        # DYNAMIC_POISON_LIBS+=("$lib")
    # fi
# done

# log_info "🎯 Total number of problematic libraries found: ${#DYNAMIC_POISON_LIBS[@]}"

# if [ ${#DYNAMIC_POISON_LIBS[@]} -gt 0 ]; then
    # log_info "🧹 Starting automatic cleaning of .drectve sections..."
    # for poison_lib in "${DYNAMIC_POISON_LIBS[@]}"; do
        # if [[ -f "$poison_lib" ]]; then
            # log_info "🪓 Remove the .drectve section from: ${poison_lib}"
            # $OBJCOPY --remove-section=.drectve "$poison_lib"
        # fi
    # done
    # log_info "✨ All detected libraries were successfully normalized."
# else
    # log_info "✅ No malicious subsystem directives were found. No cleanup is required."
# fi

# cd - > /dev/null

# =======================================
# FLAGS AND LIBS PROCESSING SECTION
# =======================================

# Remove hard -static and -Wl,-Bstatic from the base linker flags
# LDFLAGS=$(echo " ${LDFLAGS} " | sed -e 's/ -static / /g' -e 's/ -Wl,-Bstatic / /g' | xargs)
# FINAL_CONFIGURE=$(echo " ${FINAL_CONFIGURE} " | sed -e 's/ --enable-libsvtjpegxs / /g' | xargs)

[[ "${PREFER_SHARED}" != "1" ]] && export LDEXEFLAGS="-static -static-libgcc -static-libstdc++"

[[ "$DEDUPE_FLAGS" == "1" ]] && log_info "${BROOM_MARK} Deduplicating ALL flags..."

# Preparing FINAL flags (Dedupe + Combine)
# Combine base flags from vars.sh and accumulated flags from components
# Configuration: base flags first, then variant-specific flags
FINAL_CONFIGURE=$(smart_dedupe "$TOTAL_FF_CONFIGURE" "$VARIANT_FF_CONFIGURE")
# CFLAGS: First, we put CPPFLAGS, then component CFLAGS, then variant CFLAGS.
# keeping the FIRST occurrence, the most important flags should be on the left.
FINAL_CFLAGS=$(smart_dedupe "$CFLAGS" "$CPPFLAGS" "$TOTAL_FF_CFLAGS" "$TOTAL_FF_CPPFLAGS" "$VARIANT_FF_CFLAGS" "$VARIANT_FF_CPPFLAGS" | sed 's/-std=gnu17/-std=gnu23/g')
FINAL_CXXFLAGS=$(smart_dedupe "$CXXFLAGS" "$CPPFLAGS" "$TOTAL_FF_CXXFLAGS" "$TOTAL_FF_CPPFLAGS" "$VARIANT_FF_CXXFLAGS" "$VARIANT_FF_CPPFLAGS")
# LDFLAGS: Similar to compilation flags
FINAL_LDFLAGS=$(smart_dedupe "$LDFLAGS" "$TOTAL_FF_LDFLAGS" "$VARIANT_FF_LDFLAGS")
FINAL_LDEXEFLAGS=$(smart_dedupe "$LDEXEFLAGS" "$TOTAL_FF_LDEXEFLAGS")
# LIBS: REVERSE logic; smart_libs_dedupe retains the LAST occurrence.
# best to put base system libs ($LIBS) at the beginning of the argument list.
# So that if a component brings its own version, it will push the base one to the end (to the right).
FINAL_LIBS=$(smart_libs_dedupe "$LIBS" "$TOTAL_FF_LIBS" "$ADDITIONAL_LIBS" "$VARIANT_FF_LIBS")

FINAL_CONFIGURE=$(echo " ${FINAL_CONFIGURE} " | sed -e 's/ --enable-cuda / /g' | xargs)
sed -i 's| -DCUDA_VERSION=7050||g' "${FFBUILD_PREFIX}/lib/pkgconfig/ffnvcodec.pc"
FINAL_CFLAGS=$(echo " ${FINAL_CFLAGS} " | sed -e 's/ -DCUDA_VERSION=7050 / /g' | xargs)

# Remove absolutely all references to mingw, gcc, and base build libraries
GCC_RUNTIME=""
for lib in -lmingw32 -lmingwex -lgcc -lgcc_eh -lmsvcrt -lkernel32; do
    if [[ " ${FINAL_LIBS} " == *" ${lib} "* ]]; then
        GCC_RUNTIME="${GCC_RUNTIME} ${lib}"
        FINAL_LIBS="${FINAL_LIBS// $lib / }"
        FINAL_LIBS="${FINAL_LIBS//$lib/}" # cleaning up the remains
    fi
done

# Enable wolfssl if the corresponding patch is applied
if [[ "${FFMPEG_PATCHES}" == "1" ]]; then
    [[ "$SEC_PROTO" == "wolfssl" ]] && \
        FINAL_CONFIGURE=$(echo "$FINAL_CONFIGURE" | sed -E 's/--enable-(gnutls|openssl|mbedtls|libtls|schannel|securetransport)\b/--disable-\1/g') && \
        FINAL_CONFIGURE="$FINAL_CONFIGURE --enable-wolfssl"
fi

# =======================================
# GENERATION OF COMPONENT STATE VARIABLES
# =======================================

[[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && log_debug "${SEARCH_MARK} Scanning FFmpeg configuration for enabled components (fast-scan)..."

declare -A ENABLED_COMPONENTS
for flag in $FINAL_CONFIGURE; do
    if [[ "$flag" =~ ^--enable-([^=[:space:]]+) ]]; then
        ENABLED_COMPONENTS["${BASH_REMATCH[1]}"]=1
    fi
done

# List of components to check
COMPONENTS=(libtorch libopenvino libflite audiotoolbox libtensorflow libtesseract openssl frei0r whisper liblcevc_dec)

# Create a variable name libtesseract -> HAS_LIBTESSERACT
for comp in "${COMPONENTS[@]}"; do
    clean_name="${comp^^}"
    clean_name="${clean_name//-/_}"
    var_name="HAS_${clean_name}"

    if [[ -n "${ENABLED_COMPONENTS[$comp]}" ]]; then
        export "$var_name=1"
        [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && log_debug "Component $comp: ${GREEN}ENABLED${NC} (${var_name}=1)"
    else
        export "$var_name=0"
        [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && log_debug "Component $comp: ${RED}DISABLED${NC} (${var_name}=0)"
    fi
done

unset ENABLED_COMPONENTS

# ==================================
# OPENVINO PROCESSING (If enabled)
# ==================================

# if [[ "$HAS_LIBOPENVINO" == "1" ]]; then
    # List of OpenVINO libraries that came from pkg-config and vars.sh
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

# Clean up any extra spaces that sed might have left behind.

# FINAL_LIBS=$(echo ${FINAL_LIBS} | xargs)

# Generate an isolated string for linker context switching
# -Wl,-Bdynamic switches MinGW ld to DLL import mode.
# -Wl,-Bstatic returns the linker to pure static build mode.

# DYNAMIC_LIBS_ACCUMULATOR+=""
# HYBRID_DYNAMIC_FLAGS=""
# if [[ -n "${DYNAMIC_LIBS_ACCUMULATOR}" ]]; then
    # HYBRID_DYNAMIC_FLAGS="-Wl,-Bdynamic ${DYNAMIC_LIBS_ACCUMULATOR} -Wl,-Bstatic "
# fi

# Using groups to solve cyclic dependencies
# Moving the LTO exception handling library outside the main group
FINAL_LIBS_GROUPED="-Wl,--start-group ${HYBRID_DYNAMIC_FLAGS}${FINAL_LIBS} -Wl,--end-group -lstdc++ ${GCC_RUNTIME}"

# =======================================
# FFMPEG AND TOOLCHAIN PARAMS DEBUG
# =======================================

if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
    log_info_line
    log_info "### ${BUILD_MARK} Start of DEBUG audit section"
    log_info_line

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

    log_debug "PRIORITY: 'as' priority: \n$(which -a as)"
    log_debug "PRIORITY: 'ld' priority: \n$(which -a ld)"
    log_debug "PRIORITY: 'x86_64-w64-mingw32-gcc' priority: \n$(which -a x86_64-w64-mingw32-gcc)"

    log_debug "${DIRS_MARK} Contents of /opt/ct-ng/bin (first 20 files):"
    ls -F /opt/ct-ng/bin | head -n 20

    log_debug "${SEARCH_MARK} Search for all 'as' files in /opt/ct-ng/:"
    find /opt/ct-ng -name "as" -type f || true
    log_debug "GNU assembler version:"

    as --version | head -n 1
    gcc --version | head -n 1
    # mold --version | head -n 1
    x86_64-w64-mingw32-as --version | head -n 1
    ccache --version | head -n 1
    file /opt/ct-ng/libexec/gcc/x86_64-w64-mingw32/15.2.0/liblto_plugin.so

    check_tool "CC" "$CC"
    check_tool "CXX" "$CXX"
    check_tool "AS" "x86_64-w64-mingw32-as"
    check_tool "AR" "$AR"
    check_tool "NM" "$NM"
    check_tool "RANLIB" "$RANLIB"
    check_tool "LD" "$LD"
    check_tool "STRIP" "x86_64-w64-mingw32-strip"

    if command -v ccache &>/dev/null; then
        log_info "${CACHE_MARK} ccache found. Configuration:"
        log_debug "CCACHE_PATH: $CCACHE_PATH"
        log_debug "REAL_CC: $(ccache -p | grep compiler_check || echo 'default')"
    else
        log_warn "ccache not in use"
    fi

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
            # Check if pkgconf crashes while reading flags of this lib
            pkgconf --static --libs "$(basename "$pc" .pc)" >/dev/null 2>&1 && log_info "  $(basename "$pc"): OK" || log_error "  $(basename "$pc"): CRASHED OR FAILED"
        done
    fi

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

# export flags
export FINAL_CONFIGURE FINAL_CFLAGS FINAL_CXXFLAGS FINAL_LDFLAGS FINAL_LDEXEFLAGS FINAL_LIBS_GROUPED
# Clear heavy variables so as not to interfere with process startup
unset TOTAL_FF_CONFIGURE TOTAL_FF_LIBS TOTAL_FF_CFLAGS TOTAL_FF_CXXFLAGS TOTAL_FF_CPPFLAGS TOTAL_FF_LDFLAGS
# Unset cross-compilation flags so host compiler stays clean during configure
unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS LDEXEFLAGS ASFLAGS LIBS

# Form an array of flags for configure
read -ra TARGET_FLAGS_ARR <<< "$FFBUILD_TARGET_FLAGS"
read -ra FF_CONF_ARR <<< "$FINAL_CONFIGURE"

# Calculate physical memory and swap (in GB)
# MEM_PHYS=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
# SWAP_TOTAL=$(awk '/SwapTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
# TOTAL_VIRTUAL=$(( MEM_PHYS + SWAP_TOTAL ))
# if [[ "$FINAL_CONFIGURE" =~ --enable-lto ]] || [[ "$USE_LTO" == "1" ]]; then
    # if [[ $TOTAL_VIRTUAL -gt 16 ]]; then
        # MAKE_JOBS=4
        # log_warn "LTO & High Swap: Using 4 threads for stability."
    # else
        # MAKE_JOBS=2
        # log_warn "LTO & Low Memory: Forcing dual-thread build to avoid OOM."
    # fi
# else
    # MEM_AVAIL=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo)
    # MEM_JOBS=$(( MEM_AVAIL * 10 / 15 ))
    # [[ $MEM_JOBS -lt 1 ]] && MEM_JOBS=1
    # CPU_CORES=$(nproc)
    # MAKE_JOBS=$(( CPU_CORES < MEM_JOBS ? CPU_CORES : MEM_JOBS ))
    # log_info "Non-LTO build: Setting MAKE_JOBS=${MAKE_JOBS} based on availability."
# fi

# log_info_line
# log_info "### ${CACHE_MARK} HOST INFO: MEM: ${MEM_PHYS}GB + SWAP: ${SWAP_TOTAL}GB = Total: ${TOTAL_VIRTUAL}GB; JOBS=${MAKE_JOBS}"

log_info_line
log_info "### ${START_MARK} Launching FFmpeg Configure..."
log_info_line

chmod +x configure

# Tip: -Wl,--allow-multiple-definition needed for KVAZAAR/cryptopp & OpenSSL/quiche.
# --extra-cflags="-DCOBJMACROS"
# -march=x86-64-v3 -mtune=generic
# --as="$CC"
# -fno-use-linker-plugin
# lld linker is broken, use ld
# FINAL_LDFLAGS="${FINAL_LDFLAGS// -fuse-ld=lld/}"
# FINAL_LDFLAGS="${FINAL_LDFLAGS//-Wl,-plugin*/}"

CONF_FLAGS=(
    --prefix="$INSTALL_ROOT"
    "${TARGET_FLAGS_ARR[@]}"
    --host-cc="ccache gcc"
    # --host-ld="gcc"
    --host-cflags="$HOST_CFLAGS $HOST_CPPFLAGS"
    --host-ldflags="$HOST_LDFLAGS"
    --extra-cflags="${FINAL_CFLAGS}"
    --extra-cxxflags="${FINAL_CXXFLAGS}"
    --extra-ldflags="${FINAL_LDFLAGS}${LINK_VERB} -Wl,--allow-multiple-definition"
    --extra-ldexeflags="${FINAL_LDEXEFLAGS}"
    --extra-libs="${FINAL_LIBS_GROUPED}"
    --enable-runtime-cpudetect
    --enable-cross-compile
    --disable-w32threads
    --enable-pthreads
    # --enable-filter=all
    --enable-opengl
    --enable-mediafoundation
    --enable-pic
    # --disable-ffprobe
    --disable-ffplay
    "${FF_CONF_ARR[@]}"
    --cc="$CC"
    --cxx="$CXX"
    --ar="$AR"
    --ld="$CC"
    --nm="$NM"
    --as="$AS"
    --ranlib="$RANLIB"
)

if [[ "${PREFER_SHARED}" != "1" ]]; then
    CONF_FLAGS+=( --pkg-config-flags="--static --libs-only-l" )
else
    CONF_FLAGS+=( --pkg-config-flags="" )
fi

[[ "$HAS_AUDIOTOOLBOX" == "0" ]] && \
    CONF_FLAGS+=( --disable-audiotoolbox --disable-videotoolbox )
[[ "$HAS_OPENSSL" == "0" ]] && \
    CONF_FLAGS+=( --disable-securetransport )
[[ "$TARGET" == "win*" ]] && \
    CONF_FLAGS+=( --enable-dxva2 --enable-d3d11va --enable-d3d12va )
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

# Function for checking and validating ffmpeg SAFE_CONFIGURE flags
check_and_fix_configure && printf "  %s\n" "${CONF_FLAGS[@]}"

# Redirect stderr to config.log for completeness
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

# lld+ffmpeg bug workaround
# ld.lld: error: undefined symbol: WinMain
# referenced by /ct-ng/build/x86_64-w64-mingw32/src/mingw-w64/mingw-w64-crt/crt/crtexewin.c:66
# libmingw32.a(lib64_libmingw32_a-crtexewin.o):(.text.startup)
# This works selectively during source code compilation. It forces GCC to compile fftools wrapper files (ffmpeg.c, ffprobe.c, etc.) as standard machine assembler. All internal FFmpeg libraries (libavcodec.a, etc.) and all third-party libraries (libshaderc, lcevc) remain fully-fledged LTO bytecode.

# if [[ "$FINAL_CONFIGURE" =~ --enable-lto ]] || [[ "$USE_LTO" == "1" ]]; then
    # is_lld=0
    # if [[ "${TARGET_LD}" == "lld" || "${TARGET_LD}" == *"ld.lld"* ]]; then
        # is_lld=1
    # fi
    # if [[ $is_lld -eq 1 ]]; then
        # if [ -f "ffbuild/config.mak" ]; then
            # log_info "Applying LLD patch: Disabling LTO flags for fftools objects..."
            # echo 'fftools/%.o: CFLAGS := $(filter-out -flto% -fno-fat-lto-objects -ffat-lto-objects, $(CFLAGS)) -fno-lto' >> ffbuild/config.mak
            # echo 'fftools/textformat/%.o: CFLAGS := $(filter-out -flto% -fno-fat-lto-objects -ffat-lto-objects, $(CFLAGS)) -fno-lto' >> ffbuild/config.mak
            # echo 'fftools/graph/%.o: CFLAGS := $(filter-out -flto% -fno-fat-lto-objects -ffat-lto-objects, $(CFLAGS)) -fno-lto' >> ffbuild/config.mak
            # echo 'fftools/resources/%.o: CFLAGS := $(filter-out -flto% -fno-fat-lto-objects -ffat-lto-objects, $(CFLAGS)) -fno-lto' >> ffbuild/config.mak
        # fi
    # if 
# fi

if [[ "$TARGET" == "win64" ]]; then
    log_info "Adjusting the generated config.h: forcibly disabling HAVE_FCNTL for Windows..."

    log_info "Searching for and patching all generated config.h files..."

    # Find all config.h files in the current build tree
    CONFIG_FILES=$(find . -type f -name "config.h")
    
    if [[ -n "$CONFIG_FILES" ]]; then
        for cfg in $CONFIG_FILES; do
            log_debug "Patching file: $cfg"
            # Replace "#define HAVE_FCNTL 1" with "#define HAVE_FCNTL 0"
            sed -i 's/#define HAVE_FCNTL 1/#define HAVE_FCNTL 0/g' "$cfg"
            # Just in case it's written as "#undef HAVE_FCNTL",
            # but we want to hard-guarantee zero:
            if ! grep -q "HAVE_FCNTL" "$cfg"; then
                echo "#define HAVE_FCNTL 0" >> "$cfg"
            fi
        done
        log_info "All config.h files have been successfully adjusted!"
    else
        log_error "No config.h files found! Please check if ./configure was successful."

        log_info "Applying 3 patches to remove fcntl from FFmpeg files..."

        # Patch libavformat/file.c
        if [[ -f "libavformat/file.c" ]]; then
            sed -i 's/#if HAVE_FCNTL/#if HAVE_FCNTL \&\& !defined(_WIN32)/g' libavformat/file.c
            log_info "Patch 1/3 (file.c) applied successfully."
        else
            log_warn "The file libavformat/file.c could not be found in this path."
        fi

        # Patch libavformat/network.c
        if [[ -f "libavformat/network.c" ]]; then
            sed -i 's/#if HAVE_FCNTL/#if HAVE_FCNTL \&\& !defined(_WIN32)/g' libavformat/network.c
            log_info "Patch 2/3 (network.c) applied successfully."
        else
            log_warn "The file libavformat/network.c could not be found in this path."
        fi

        # Patch libavutil/file_open.cr
        if [[ -f "libavutil/file_open.c" ]]; then
            sed -i 's/#if HAVE_FCNTL/#if HAVE_FCNTL \&\& !defined(_WIN32)/g' libavutil/file_open.c
            log_info "Patch 3/3 (file_open.c) applied successfully."
        else
            log_warn "The file libavutil/file_open.c could not be found in this path."
        fi

    fi
fi

# Clearing the ffmpeg header
if [ -f "config.h" ]; then

    if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
        log_info "${LOGS_MARK} >>> [BEFORE] config.h target line:"
        grep "#define FFMPEG_CONFIGURATION" config.h || echo "Line not found"
    fi

    # RAW_CONFIG=$(sed -n 's/^#define FFMPEG_CONFIGURATION "\(.*\)"/\1/p' config.h)

    # if [ -n "$RAW_CONFIG" ]; then
        # eval "FINAL_ARGS=($RAW_CONFIG)"

        # CLEANED_ARGS=()

        # for arg in "${FINAL_ARGS[@]}"; do
            # case "$arg" in
                # --host-cflags=*|--host-ldflags=*|--extra-cflags=*|--extra-cxxflags=*|--extra-ldflags=*|--extra-ldexeflags=*|--extra-libs=*)
                    # continue
                    # ;;
                # --pkg-config-flags=*|--cc=*|--cxx=*|--ar=*|--ranlib=*|--nm=*|--as=*)
                    # continue
                    # ;;
                # *)
                    # if [[ "$arg" == *" "* ]]; then
                        # CLEANED_ARGS+=("'$arg'")
                    # else
                        # CLEANED_ARGS+=("$arg")
                    # fi
                    # ;;
            # esac
        # done

        # CLEANED_CONFIG="${CLEANED_ARGS[*]}"

        # sed -i "s|^#define FFMPEG_CONFIGURATION.*|#define FFMPEG_CONFIGURATION \"${CLEANED_CONFIG}\"|" config.h
    # else
        # log_warn "Failed to parse FFMPEG_CONFIGURATION content for cleaning."
    # fi

    sed -i -E 's/--(host-cflags|host-ldflags|extra-cflags|extra-cxxflags|extra-ldflags|extra-ldexeflags|extra-libs|pkg-config-flags|cc|cxx|ar|ranlib|nm|as)=([^[:space:]]*|\x27[^\x27]*\x27|"[^"]*")[[:space:]]*//g' config.h

    sed -i -E 's/[[:space:]]+/ /g' config.h

    sed -i 's/ "$/"/' config.h

    if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
        log_info "${LOGS_MARK} <<< [AFTER] config.h target line:"
        grep "#define FFMPEG_CONFIGURATION" config.h
    fi
fi

# =======================================
# FFMPEG MAKE & INSTALL
# =======================================

# Building and installing ffmpeg
make -j$(nproc) ${MAKE_V}
make install
make install-doc || log_warn "install-doc failed, but proceeding."

log_info "${DIRS_MARK} Leaving FFmpeg folder..."
popd # Exit ffbuild/ffmpeg

log_info "${BROOM_MARK} Cleaning up potential prefix pollution..."
# Delete empty folders or old logs if they remain
find "${FFBUILD_PREFIX}" -type d -empty -delete || true

# Version detection
if [[ -n "$FFMPEG_API_VERSION" ]]; then
    # Если переменная прилетела из GitHub Actions / Docker ENV, используем её
    log_info "Using FFmpeg version from API: ${FFMPEG_API_VERSION}"
    FFMPEG_VERSION="$FFMPEG_API_VERSION"
elif [[ -f "$FFMPEG_SOURCE_DIR/ffbuild/version.sh" ]]; then
    # Check for the presence of an official version detection script
    log_info "Detecting FFmpeg version using official ffbuild/version.sh..."
    # Run the script, passing it the path to the root of the FFmpeg source code
    FFMPEG_VERSION=$(bash "$FFMPEG_SOURCE_DIR/ffbuild/version.sh" "$FFMPEG_SOURCE_DIR")
else
    # Fallback by date
    log_warn "ffbuild/version.sh not found, falling back to basic date-string."
    FFMPEG_VERSION=$(date +%Y-%m-%d)
fi

# Remove possible spaces or special line break characters from the variable
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

# Download models and assets
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

# Stripping binaries (removing debug symbols)
# --strip-all; --strip-unneeded
if [[ "$SKIP_POST_STRIP" != "1" ]]; then
    if declare -F strip_files >/dev/null; then
        strip_files "${PKG_DIR}/bin" "ffmpeg"
    else
        log_warn "strip_files function not found, falling back to basic strip"
        find "${PKG_DIR}/bin" -type f \( -name "*.exe" -o -name "*.dll" \) -exec "${STRIP}" --strip-unneeded {} \;
    fi
fi

# Go to pkgroot so that there are no extra nested folders inside the archive
pushd "$FFMPEG_PKG_ROOT"

# Package
log_info "${ARCH_MARK} Creating archive: ${BUILD_NAME}.7z"
if [[ "$DEBUG_MODE" == "1" ]]; then
    log_info "${SAVE_MARK} Gathering all generated debug files..."
    # Find all .debug files in the developer prefix and copy them into the release structure to executable files
    find "${FFBUILD_PREFIX}" -type f -name "*.debug" -exec cp {} "./${BUILD_NAME}/bin/" \; 2>/dev/null || true
    log_info "${SAVE_MARK} Packaging external debug symbols separately..."
    # Find all created .debug files and pack them separately
    7z a -mx7 -mmt=on -r "${FFBUILD_DESTDIR}/${BUILD_NAME}-debug-symbols.7z" "./${BUILD_NAME}/*.debug"
    # Exclude .debug files from the main user archive
    7z a -mx7 -mmt=on "${FFBUILD_DESTDIR}/${BUILD_NAME}.7z" "./${BUILD_NAME}/*" -xr!"*.debug"
else
    # Normal pack without debug files
    7z a -mx7 -mmt=on "${FFBUILD_DESTDIR}/${BUILD_NAME}.7z" "./${BUILD_NAME}/*"
fi

popd

# Generating Metadata for GitHub Actions
if [[ -n "$GITHUB_ACTIONS" ]]; then
    echo "build_name=${BUILD_NAME}" >> "$GITHUB_OUTPUT"
    echo "${BUILD_NAME}.7z" > "${FFBUILD_DESTDIR}/${TARGET}-${VARIANT}.txt"
fi

duration=$SECONDS
elapsed=$(printf '%02dh:%02dm:%02ds' $((duration/3600)) $((duration%3600/60)) $((duration%60)))

log_info "${CHECK_MARK} Build finished after ${GREY_B}${elapsed}${NC}"

exit 0