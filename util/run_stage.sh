#!/bin/bash

set -e

STAGE="$1"

# make sure that there is a path to the script at all
if [[ -z "$STAGE" || ! -f "$STAGE" ]]; then
    echo "ERROR: Usage: run_stage <STAGE>" >&2
    exit 1
fi

# Load utilities using absolute path
if ! declare -F log_info >/dev/null; then
    . /builder/util/vars.sh "$TARGET" "$VARIANT" 2>/dev/null \
        || { echo "ERROR: vars.sh failed in run_stage for $TARGET/$VARIANT" >&2; exit 1; }
fi

if ! declare -F default_dl >/dev/null; then
    . "$UTIL_DIR"/dl_functions.sh > /dev/null 2>&1 || true
fi

# Reset statistics
# ccache -z > /dev/null

# Reset the seconds counter at the beginning of the stage
SECONDS=0
STAGE_START_TIME=$(date +%s)
STAGE_LOG="/tmp/stage_build_${STAGENAME}.log"
# Write a timestamp file before $build_cmd runs, then use find -newer to detect which .pc files were created by this build
TIMESTAMP_FILE=$(mktemp)
sleep 1

# Call dynamic STAGE function 
unset STAGE_HASH STAGENAME COMPONENT_NAME STAGE_CACHE_FILE STAGE_LATEST_LINK REAL_CACHE
eval "$(stage_vars "$STAGE")"

if declare -F apply_lto_policy >/dev/null; then
    apply_lto_policy
fi

# generate dynamic cross-build toolchain files
generate_meson_cross && generate_cmake_toolchain

# Cleanup on exit
# Delete old files if they remain from previous launches
stage_cleanup() {
    local exit_code=$?
    local duration=$SECONDS
    local elapsed=$(printf '%02dh:%02dm:%02ds' $((duration/3600)) $((duration%3600/60)) $((duration%60)))
    local BUILD_DIR="/build/${STAGENAME}"

    if [[ $exit_code -eq 0 ]]; then
        # Success: clean everything; NOTE: Should keep "$VARS_DIR" & "$OUTFILE"
        cd /
        [[ -n "$STAGENAME" ]] && rm -rf "$BUILD_DIR"
        rm -f "$STAGE_LOG" "$TIMESTAMP_FILE"
        log_info "${CHECK_MARK} Build ${GREEN}SUCCEEDED${NC} for ${STAGENAME} [Time: ${GREY_B}${elapsed}${NC}]"
    else
        # Failure: dumping logs
        log_error "Build ${LOG_ERROR}FAILED${NC} for ${STAGENAME} after ${GREY_B}${elapsed}${NC}"
        if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
            log_debug "${BUILD_MARK} Current stage file: ${STAGE}"
            log_debug "${DIRS_MARK} Current directory: $(pwd)"
            cd /build
            LOG_FILES=$(find "$BUILD_DIR" -maxdepth 4 \( -name "config.log" -o -name "meson-log.txt" -o -name "CMakeError.log" -o -name "CMakeOutput.log" \) 2>/dev/null)
            if [[ -n "$LOG_FILES" ]]; then
                # Luck: displaying found build system logs
                for logfile in $LOG_FILES; do
                    # Skip if this is the same as STAGE_LOG (already captured)
                    if [[ "$(readlink -f "$logfile")" == "$(readlink -f "$STAGE_LOG")" ]]; then
                        continue
                    fi
                    log_debug "${LOGS_MARK} ▼ CONTENT OF ${logfile} (last ${LOG_SIZES} lines) ▼"
                    tail -n ${LOG_SIZES} "$logfile" >&2
                    log_debug "${LOGS_MARK} ▲ END OF $(basename "$logfile") ▲"
                done
            else
                # Failure: no system logs, looking for a general log
                if [[ -f "$STAGE_LOG" ]]; then
                    log_debug "${LOGS_MARK} ▼ System logs missing. Falling back to STAGE_LOG ($STAGE_LOG) ▼"
                    tail -n ${LOG_SIZES} "$STAGE_LOG" >&2
                else
                    # Found nothing
                    if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
                        log_warn "No logs found.${DIRS_MARK} Listing directory content of $BUILD_DIR:"
                        # 1) use find
                        # -maxdepth 2 to avoid listing thousands of files from subfolders 
                        # sed adds padding to simulate a tree
                        # find "$BUILD_DIR" -maxdepth 2 -not -path '*/.*' | sed -e "s|^$BUILD_DIR||" -e "s|^/||" | sort | while read -r line; do
                            # [[ -z "$line" ]] && continue
                            # full_path="${BUILD_DIR}/${line}"
                            # if [[ -d "$full_path" ]]; then
                                # echo -e "${DIRS_MARK} ${BLUE_B}${line}/${NC}" >&2
                            # elif [[ -x "$full_path" ]]; then
                                # echo -e "${CHECK_MARK} ${GREEN}${line}*${NC}" >&2
                            # else
                                # echo -e " ${line}" >&2
                            # fi
                        # done
                        # 2) or use ls
                        # ls -F -C --color=always --group-directories-first "$BUILD_DIR" >&2
                        # 3) better use tree (need rebuild)
                        # -F adds / to folders, -L 2 limits depth to avoid spamming 
                        # --dirsfirst groups folders at the beginning
                        tree -F -L 2 --dirsfirst "$BUILD_DIR" >&2
                    else
                        log_warn "No logs were found."
                    fi
                fi
            fi
        else
            if [[ -f "$STAGE_LOG" ]]; then
                log_debug "${LOGS_MARK} ▼ CONTENT OF ($STAGE_LOG) ▼"
                tail -n ${LOG_SIZES} "$STAGE_LOG" >&2
                log_debug "${LOGS_MARK} ▲ END OF $STAGE_LOG ▲"
            else
                log_warn "Log file $STAGE_LOG is missing!"
            fi
        fi

        show_patch_summary

        cd /
        # Cleaning after a fail
        rm -rf "$BUILD_DIR" "$VARS_DIR" "$STAGE_LOG" "$TIMESTAMP_FILE" "$OUTFILE" "$LOG_PATCH_ERRORS"
    fi
}
trap stage_cleanup EXIT

# Create and enter the build directory BEFORE loading the script
log_info "${DIRS_MARK} Creating the base folder structure if it doesn't exist..."
mkdir -p "$VARS_DIR" "$FFBUILD_DESTDIR" "$INSTALL_ROOT"/{include,bin,lib/pkgconfig} "/build/$STAGENAME" && cd "/build/$STAGENAME"

# Load the script in advance to check SCRIPT_SKIP
# Any $(pwd) or relative paths inside the script will point to /build/STAGENAME
# Use the absolute path to the script, since we have already changed the cd
source "$(readlink -f "$STAGE")"

# Check for skipping (now the SCRIPT_SKIP variable is loaded in the context of the desired folder)
if [[ "$SCRIPT_SKIP" == "1" ]]; then
    log_info "Skipping stage $STAGENAME as requested by script."
    exit 0
fi

# Clear the temporary file destination to avoid parasitic copying
# artifacts from previous Docker layers (if they are in the layer cache)
if [[ -d "$FFBUILD_DESTDIR" ]]; then
    log_info "${BROOM_MARK} Cleaning up temporary DESTDIR: $FFBUILD_DESTDIR"
    rm -rf "${FFBUILD_DESTDIR:?}"/*
fi
mkdir -p "$FFBUILD_DESTDIR" "${INSTALL_ROOT}"

log_info "${SEARCH_MARK} Searching source for $STAGENAME"

# Check if the cache folder is writable
if [ ! -w "$CACHE_DIR" ]; then
    # If the cache is Read-Only (BuildKit context), redirect decorative links to /tmp, so that the ln utility does not try to write to protected memory
    STAGE_LATEST_LINK="/tmp/$(basename "$STAGE_LATEST_LINK")"
fi

# Looking for an exact match (Name_Hash)
if [[ -f "$STAGE_CACHE_FILE" ]]; then
    REAL_CACHE="$STAGE_CACHE_FILE"
    log_info "${CHECK_MARK} Exact cache match found: $(basename "$REAL_CACHE")"
    rm -f "$STAGE_LATEST_LINK"
    ln -sf "$(basename "$STAGE_CACHE_FILE")" "$STAGE_LATEST_LINK" || true
# Searching by hash (if the script is renamed, for example 25-glib2 -> 24-glib2)
else
    EXISTING_BY_HASH=$(find "$CACHE_DIR" -maxdepth 1 -name "*_${STAGE_HASH}.tar.zst" -print -quit)
    if [[ -n "$EXISTING_BY_HASH" ]]; then
        REAL_CACHE="$EXISTING_BY_HASH"
        log_info "${CHECK_MARK} Found cache with matching hash but different name: $(basename "$REAL_CACHE")"
        rm -f "$STAGE_LATEST_LINK"
        ln -sf "$(basename "$REAL_CACHE")" "$STAGE_LATEST_LINK" || true
# Fall back to the last link (LATEST) if the exact hash is not found
    elif [[ -L "$STAGE_LATEST_LINK" && -f "$STAGE_LATEST_LINK" ]]; then
        REAL_CACHE=$(readlink -f "$STAGE_LATEST_LINK")
        log_warn "Exact hash $STAGE_HASH not found. Falling back to latest symlink: $(basename "$REAL_CACHE")"
    fi
fi

# Check whether the sources are needed at all for this stage (or is it a meta stage), and exit
DL_COMMANDS=$(ffbuild_dockerdl 2>/dev/null) || {
    log_error "ffbuild_dockerdl failed for $STAGENAME"
    exit 1
}

if [[ -n "$DL_COMMANDS" ]]; then
    # If the cache is not found in any way
    if [[ -z "$REAL_CACHE" || ! -f "$REAL_CACHE" ]]; then
        log_warn "Source cache NOT FOUND for $STAGENAME. Attempting direct download..."
        log_debug "Expected hash: $STAGE_HASH | Target file: $STAGE_CACHE_FILE"

        # Trying to download the sources on the fly
        if eval "$DL_COMMANDS"; then
            log_info "${CHECK_MARK} Direct download successful for $STAGENAME."
            # Clearing before saving to cache
            if [[ -d ".git" ]]; then
                log_debug "${BROOM_MARK} Running git clean -fdx for $STAGENAME..."
                # Exclude folders or files from cleaning, for example. -e "lib/include/*"
                git clean -fdx
            fi
            # immediately create an archive in the cache so that next time it will be picked up instantly
            if [ -w "$CACHE_DIR" ]; then
                log_info "${ARCH_MARK} Creating new cache archive for $STAGENAME..."
                ZSTD_CLEVEL=5 tar --sort=name \
                    --owner=0 --group=0 --numeric-owner \
                -I 'zstd -T0 --long=23' -cf "$STAGE_CACHE_FILE" .
            fi

            rm -f "$STAGE_LATEST_LINK"
            ln -sf "$(basename "$STAGE_CACHE_FILE")" "$STAGE_LATEST_LINK" || true
        else
            # error block, only fires if the download fails
            log_error "No source cache and download failed for $STAGENAME"
            log_info "Expected hash: $STAGE_HASH"
            if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
                log_debug "${DIRS_MARK} Available files in cache for this component:"
                ls -lh "$CACHE_DIR" | grep "$STAGENAME" || log_warn "No files matching $STAGENAME found."
            fi
            exit 1
        fi
    else
        # If REAL_CACHE was found (by one of the 3 methods above)
        log_info "${EXTR_MARK} Unpacking $STAGENAME from $(basename "$REAL_CACHE")..."
        if ! tar -I 'zstd -d -T0' -xaf "$REAL_CACHE" -C . ; then log_error "Failed to unpack $(basename "$REAL_CACHE")"; exit 1; fi
    fi

    # AUTO-SEARCH for the project root (if archive is unpacked into a subfolder)
    if [[ ! -f "Configure" && ! -f "configure" && ! -f "CMakeLists.txt" && ! -f "meson.build" ]]; then
        log_warn "No build file in root. ${SEARCH_MARK} Searching one level deeper..."
        CANDIDATE=$(find . -maxdepth 2 \( -name "Configure" -o -name "configure" -o -name "CMakeLists.txt" -o -name "meson.build" \) -printf '%h\n' | head -n 1)
        if [[ -n "$CANDIDATE" ]]; then
            log_info "${DIRS_MARK} Project root found at $CANDIDATE. Entering..."
            cd "$CANDIDATE"
        fi
    fi

    # Checking that after all manipulations the folder is not empty
    if [[ -z "$(ls -A)" ]]; then
        log_error "Build directory is empty after unpacking/downloading $STAGENAME!"
        exit 1
    fi

    # AUTO-PATCHING
    apply_patches

    if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
        log_debug "${DIRS_MARK} Contents of $(pwd) (current build directory):"
        # Collect the list: first folders (with /), then files
        # -F adds / to folders, -1 outputs to one column 
        # paste concatenates them via tabs so that column understands the delimiter
        paste <(ls -ad .*/ */ 2>/dev/null | grep -v '^\./\?$' | head -n 17) \
              <(ls -AF 2>/dev/null | grep -v / | head -n 17) | \
              column -t -s $'\t' -N "DIRECTORIES","FILES" | \
              sed 's/^/ /' # Add left padding for beauty
    fi

else
    log_info "No source archive required for $STAGENAME (meta-package)."
fi

[[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]] && log_debug "${STAGENAME}-specific CFLAGS:\n$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" && log_debug "${STAGENAME}-specific LDFLAGS:\n$LDFLAGS ${USELTO}${USELTO_L}" && log_debug "${STAGENAME}-specific RUSTFLAGS:\n$RUSTFLAGS"

# Perform the build ONCE and check the status
build_cmd="ffbuild_dockerbuild"
[[ -n "$2" ]] && build_cmd="$2"

# wine starter
setup_wine_env

# Manually determining the component version
if ! should_skip_version_finder; then
    export VER_FULL=$(get_stage_version)
    log_info "${TARGET_MARK} Stage version initialized: VER_FULL=${LOG_INFO}${VER_FULL}${NC}"
fi

log_info_line
log_info "### ${START_MARK} ${LOG_INFO}STARTING STAGE: $STAGENAME${NC}"
log_info "### DATE: $(date)"
log_info "### Starting build function: $build_cmd"
log_info_line

# Generate the 'configure' file (if it doesn't exist) for Autoconf
conf_finder

if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
    log_debug "Verbose mode active. Build output will be shown in real-time."
    if ! ( set -e -o pipefail; $build_cmd ); then exit 1; fi
else
    log_info "Quiet mode active. Output is redirected to ${STAGE_LOG}"
    if ! ( set -e -o pipefail; $build_cmd > "${STAGE_LOG}" 2>&1 ); then exit 1; fi
fi

log_info_line
log_info "### ${SYNC_MARK} POST-BUILD AUDIT AND AUTOMATION: $STAGENAME"
log_info_line

# Each script in scripts.d must install files (make install) to the path starting with $FFBUILD_DESTDIR$FFBUILD_PREFIX (usually /opt/ffdest/opt/ffbuild), otherwise the system will not see the installed library for the next step.

# The key constraint is: strip before sync, clean before strip, patch .pc before sync.
# build_cmd runs
# ▼
# [AUDIT]   Verify INSTALL_ROOT exists and has files
# │         (fail fast — no point running anything else on empty install)
# ▼
# [CLEAN]   clean_la_files          ← remove .la before anything reads them
# │         (.la files can poison pkgconfig and linker lookups)
# ▼
# [CLEAN]   Remove unwanted DLLs / static .a  ← based on PREFER_SHARED + preserve lists
# │         (must happen BEFORE strip — no point stripping files we're about to delete)
# ▼
# [STRIP]   strip_files             ← strip what remains after cleanup
# │         (strip DESTPREFIX, not PREFIX — we haven't synced yet)
# ▼
# [PATCH]   patch_pc_files          ← fix .pc paths AFTER strip (strip doesn't touch .pc)
# │         (paths must be correct before rsync writes them to PREFIX)
# ▼
# [SYNC]    rsync DESTPREFIX → PREFIX  ← only clean, stripped, patched files go to cache
# ▼
# [AUDIT]   get_deps_list           ← audit what landed in PREFIX (verbose only)

if [[ -d "$INSTALL_ROOT" ]]; then
    # Identify what was actually built
    mapfile -t NEW_FILES < <(find "$INSTALL_ROOT" -type f -o -type l)

    if [[ ${#NEW_FILES[@]} -eq 0 ]]; then
        log_warn "Stage $STAGENAME finished but no files were found in DESTDIR."
    else
        if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
            # Show everything that was installed in a pretty way
            log_debug "${DIRS_MARK} Installed ${#NEW_FILES[@]} files to prefix:"
            # Clearing paths from DESTDIR; can also try with "grep -Po"
            CLEAN_LIST=$(printf "%s\n" "${NEW_FILES[@]}" | sed "s|^$FFBUILD_DESTDIR||")
            (
                echo "$CLEAN_LIST" | grep -E "/lib/pkgconfig/|/lib/cmake/|/lib/[^/]+\.a$" | sort
                echo "$CLEAN_LIST" | grep -vE "/lib/pkgconfig/|/lib/cmake/|/lib/[^/]+\.a$" | sort
            ) | head -n ${LOG_INSTALLED} >&2
            # stripping the long DESTDIR prefix for readability
            [[ ${#NEW_FILES[@]} -gt ${LOG_INSTALLED} ]] && log_debug "  ... (and $((${#NEW_FILES[@]} - ${LOG_INSTALLED} )) more)"
        fi

        # clean .la files (libtool archives)
        clean_la_files

        # remove unwanted DLLs or static libs
        # list of STAGES that are ALLOWED to have DLLs - imported from workflow.yaml 
        # MinGW libraries create libname.dll.a (implib) even for static ones
        # added .exe files for clean-up
        if [[ "$TARGET" == "win64" ]]; then
            if [[ "$PREFER_SHARED" != "1" ]]; then
                if [[ ! "$STAGENAME" =~ $DLL_PRESERVE_LIST ]]; then
                    # Remove DLLs, MinGW import libs (.dll.a), MSVC import/static (.lib) and .exe
                    clean_unwanted_libs "dynamic .dll, .exe, MSVC libs" "\( -name '*.dll' -o -name '*.dll.a' -o -name '*.lib' -o -name '*.def' -o -name '*.exp' -o -name '*.exe' \)"
                else
                    log_info "${LOCK_MARK} Preserving dynamic DLLs and generating import libs for $STAGENAME"
                    # First we deal with .lib, if they came from archives (as in TF) 
                    # If there is .lib, but not .a, create a symlink/copy so that MinGW sees them as .a
                    find "$INSTALL_ROOT" -name "*.lib" -type f | while read -r lib_file; do
                        lib_dir=$(dirname "$lib_file")
                        lib_name=$(basename "$lib_file")
                        # Convert to libname.a if it is not an import library (a simple rename often helps for statics)
                        if [[ ! -f "$lib_dir/lib${lib_name%.lib}.a" ]]; then
                            cp "$lib_file" "$lib_dir/lib${lib_name%.lib}.a"
                        fi
                    done
                    # Generate .a from .dll (for those where .lib is not suitable or missing)
                    generate_implibs "$INSTALL_ROOT"
                    # clean up garbage .def/.exp if they are created
                    clean_unwanted_libs "temporary definition files" "\( -name '*.def' -o -name '*.exp' \)"
                fi
            else
                # PREFER_SHARED=1
                if [[ -n "$LIB_PRESERVE_LIST" && ! "$STAGENAME" =~ $LIB_PRESERVE_LIST ]]; then
                    # Clean static .a and .lib, leaving .dll.a (imported libs)
                    clean_unwanted_libs "static libs" "\( -name '*.a' -o -name '*.lib' -o -name '*.def' -o -name '*.exp' -o -name '*.exe' \) ! -name '*.dll.a'"
                else
                    log_info "${LOCK_MARK} Preserving static libs for $STAGENAME"
                fi
            fi
        elif [[ "$TARGET" == "linux64" ]]; then
            # For Linux .lib and .dll are always garbage
            if [[ "$PREFER_SHARED" != "1" ]]; then
                clean_unwanted_libs "non-linux libs" "\( -name '*.dll' -o -name '*.dll.a' -o -name '*.lib' -o -name '*.def' -o -name '*.exp' -o -name '*.exe' \)"
            fi
        fi

        # strip debug symbols
        strip_files "$INSTALL_ROOT" "$STAGENAME"

        # patch .pc files (paths, dependencies, Requires)
        patch_pc_files

        # sync to persistent prefix (So the next script sees them)
        # Using -u (update) to avoid overwriting newer files if layers run out of order
        rsync -a --checksum "$INSTALL_ROOT/" "$FFBUILD_PREFIX/" && log_info "${CHECK_MARK} Sync completed and $STAGENAME is now available for dependencies."

        # audit dependencies (verbose only)
        get_deps_list
    fi
else
    log_debug "${DIRS_MARK} No standard prefix directory found for $STAGENAME"
fi

# Save variables for the current layer to a file
OUTFILE="$VARS_DIR/${STAGENAME}.vars"

# Completely isolated subshell, no inherited FF_* state
# The subshell is the critical isolation mechanism, no FF_* state can leak in from the parent environment.
log_info "${SAVE_MARK} Saving build variables for $STAGENAME..."
(
    export PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR"
    export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
    # Re-source vars.sh clean so ffbuild_* accumulator functions are defined
    # but FF_* variables are empty
    unset FF_CONFIGURE FF_CFLAGS FF_CXXFLAGS FF_CPPFLAGS FF_LDFLAGS FF_LDEXEFLAGS FF_LIBS
    . "$UTIL_DIR/vars.sh" "$TARGET" "$VARIANT" > /dev/null 2>&1

    # Re-source the component script so its ffbuild_* functions are available
    # Load component - overrides ffbuild_* with its own implementations
    . "$STAGE"

    # Call the component's own ffbuild_* functions
    # These are the ONLY authoritative source of what this component needs.
    _conf=$(ffbuild_configure 2>/dev/null || true)
    _cf=$(ffbuild_cflags 2>/dev/null || true)
    _cpp=$(ffbuild_cppflags 2>/dev/null || true)
    _cxx=$(ffbuild_cxxflags 2>/dev/null || true)
    _ld=$(ffbuild_ldflags 2>/dev/null || true)
    _ldexe=$(ffbuild_ldexeflags 2>/dev/null || true)
    _libs=$(ffbuild_libs 2>/dev/null || true)

    # Collect flags from this component's own .pc files only
    # (files newer than the pre-build timestamp)
    _pc_cflags=""
    _pc_libs=""
    declare -A _seen_pc_cflags
    declare -A _seen_pc_libs

    # This is much more reliable than name matching, it doesn't matter what the library calls its .pc file. Only .pc files newer than the pre-build timestamp

    while IFS= read -r -d '' pc; do
        [[ -e "$pc" ]] || continue
        [[ "$pc" -nt "$TIMESTAMP_FILE" ]] || continue

        # Add the folder where this .pc is located to PKG_CONFIG_PATH for the current call
        export PKG_CONFIG_PATH="$(dirname "$pc"):$PKG_CONFIG_LIBDIR"
        # Collect only if the name of the .pc file matches or is associated with the component
        pc_name="$(basename "$pc" .pc)"

        # Extracting the path to includes directly from the module
        actual_inc=$(pkg-config --variable=includedir "$pc_name" 2>/dev/null)
        # If the path exists and it is "deeper" than the standard one (contains a subfolder)
        if [[ -n "$actual_inc" && "$actual_inc" != "$FFBUILD_PREFIX/include" ]]; then
            # Add it to CFLAGS if haven't seen it yet
            if [[ -z "${_seen_pc_cflags["-I$actual_inc"]:-}" ]]; then
                _seen_pc_cflags["-I$actual_inc"]=1
                _pc_cflags="$_pc_cflags -I$actual_inc"
            fi
        fi

        # Deduplicate per-flag across multiple .pc files
        while IFS= read -r flag; do
            [[ -z "$flag" ]] && continue
            if [[ -z "${_seen_pc_cflags[$flag]:-}" ]]; then
                _seen_pc_cflags["$flag"]=1
                _pc_cflags="$_pc_cflags $flag"
            fi
        # just pkg-config --cflags saves with paths
        done < <(pkg-config $PKG_CONFIG_CFLAGS "$pc_name" 2>/dev/null | tr ' ' '\n' | grep -v '^$')

        # First, collect the libraries themselves (-l)
        # while IFS= read -r flag; do
            # [[ -z "$flag" ]] && continue
            # if [[ -z "${_seen_pc_libs[$flag]:-}" ]]; then
                # _seen_pc_libs["$flag"]=1
                # _pc_libs="$_pc_libs $flag"
            # fi
        # done < <(pkg-config $PKG_CONFIG_LIBS "$pc_name" 2>/dev/null | tr ' ' '\n' | grep -v '^$')

        # Then collect system flags (-pthread, etc.)
        while IFS= read -r flag; do
            [[ -z "$flag" ]] && continue
            if [[ -z "${_seen_pc_libs[$flag]:-}" ]]; then
                _seen_pc_libs["$flag"]=1
                _pc_libs="$_pc_libs $flag"
            fi
        done < <(pkg-config $PKG_CONFIG_ALL_LIBS "$pc_name" 2>/dev/null | tr ' ' '\n' | grep -v '^$')

    done < <(find "$FFBUILD_PREFIX/lib" "$FFBUILD_PREFIX/lib64" "$FFBUILD_PREFIX/share" -maxdepth 3 -name "*.pc" -print0 2>/dev/null)

    # Merge script output with .pc output, then deduplicate the combined result
    FF_CONFIGURE=$(smart_dedupe "$_conf")
    FF_CFLAGS=$(smart_dedupe "$_cf $_pc_cflags")
    FF_CPPFLAGS=$(smart_dedupe "$_cpp")
    FF_CXXFLAGS=$(smart_dedupe "$_cxx")
    FF_LDFLAGS=$(smart_dedupe "$_ld")
    FF_LDEXEFLAGS=$(smart_dedupe "$_ldexe")
    FF_LIBS=$(smart_libs_dedupe "$_libs $_pc_libs")

    VARS_CONTENT=""
    [[ -n "$FF_CONFIGURE" ]]  && VARS_CONTENT+="export FF_CONFIGURE='${FF_CONFIGURE}'\n"
    [[ -n "$FF_CFLAGS" ]]     && VARS_CONTENT+="export FF_CFLAGS='${FF_CFLAGS}'\n"
    [[ -n "$FF_CPPFLAGS" ]]   && VARS_CONTENT+="export FF_CPPFLAGS='${FF_CPPFLAGS}'\n"
    [[ -n "$FF_CXXFLAGS" ]]   && VARS_CONTENT+="export FF_CXXFLAGS='${FF_CXXFLAGS}'\n"
    [[ -n "$FF_LDFLAGS" ]]    && VARS_CONTENT+="export FF_LDFLAGS='${FF_LDFLAGS}'\n"
    [[ -n "$FF_LDEXEFLAGS" ]] && VARS_CONTENT+="export FF_LDEXEFLAGS='${FF_LDEXEFLAGS}'\n"
    [[ -n "$FF_LIBS" ]]       && VARS_CONTENT+="export FF_LIBS='${FF_LIBS}'\n"

    # Write only non-empty values to .vars
    # If there is at least one export, write it to a file
    if [[ -n "$VARS_CONTENT" ]]; then
        # printf '%b' is safe — no format string injection
        printf '%b' "$VARS_CONTENT" | tr -d '\r' > "$OUTFILE"
        log_debug "${CACHE_MARK} Saved $(wc -c < "$OUTFILE") bytes to $OUTFILE"
    else
        log_info "${CHECK_MARK} No build variables for $STAGENAME (meta/header-only)."
    fi

    # Verbose output - inside subshell where FF_* are populated
    if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
        [[ -n "$FF_CONFIGURE" ]]  && log_debug "Final $STAGENAME FF_CONFIGURE:\n$FF_CONFIGURE"
        [[ -n "$FF_CFLAGS" ]]     && log_debug "Final $STAGENAME FF_CFLAGS:\n$FF_CFLAGS"
        [[ -n "$FF_CPPFLAGS" ]]   && log_debug "Final $STAGENAME FF_CPPFLAGS:\n$FF_CPPFLAGS"
        [[ -n "$FF_CXXFLAGS" ]]   && log_debug "Final $STAGENAME FF_CXXFLAGS:\n$FF_CXXFLAGS"
        [[ -n "$FF_LDFLAGS" ]]    && log_debug "Final $STAGENAME FF_LDFLAGS:\n$FF_LDFLAGS"
        [[ -n "$FF_LDEXEFLAGS" ]] && log_debug "Final $STAGENAME FF_LDEXEFLAGS:\n$FF_LDEXEFLAGS"
        [[ -n "$FF_LIBS" ]]       && log_debug "Final $STAGENAME FF_LIBS:\n$FF_LIBS"
    fi
)

if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
    # Diagnostics of created files
    log_debug "${DIRS_MARK} Current files in $VARS_DIR:"
    ls -1 "$VARS_DIR" | grep ".vars" || log_warn "No .vars files created in this stage."
fi

# Display statistics at the end of each stage
# This will show the Hit Rate directly in the GitHub logs
log_info "${CACHE_MARK} CCACHE STATISTICS:"
ccache -s "${OP_VERB2}"

log_info_line
log_info "### ${CHECK_MARK} Post-build automation completed."
log_info_line

exit 0