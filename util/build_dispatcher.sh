#!/bin/bash
set -e

# Load configuration
cd "$(dirname "$0")/.."
source util/vars.sh "$TARGET" "$VARIANT"

# Ensure directories exist
mkdir -p "$FFBUILD_PREFIX" "$FFBUILD_DESTDIR" "$TMP_DIR"

# Define the shared volume paths for mounting
# These must match the paths used inside the Docker container
SHARED_PREFIX="/opt/ffbuild_shared"
SHARED_DESTDIR="/opt/ffdest_shared"

# We will use a host directory to emulate the shared volume behavior
# Since GitHub Actions runners don't support named volumes easily for this,
# we will use a host directory mounted into the container.
HOST_SHARED_PREFIX="$ROOT_DIR/.cache/shared_prefix"
HOST_SHARED_DESTDIR="$ROOT_DIR/.cache/shared_dest"

mkdir -p "$HOST_SHARED_PREFIX" "$HOST_SHARED_DESTDIR"

# Function to calculate cache key for a specific script
get_cache_key() {
    local script_path="$1"
    local script_hash
    script_hash=$(get_stage_hash "$script_path")
    # Include global config hash to invalidate all if vars.sh changes significantly
    local config_hash=$(sha256sum "$UTIL_DIR/vars.sh" | cut -c1-16)
    echo "win64-${TARGET}-${VARIANT}-${CPU_ARCH}-$(basename "$script_path" .sh)-${script_hash}-${config_hash}"
}

# Function to check and restore from GitHub Cache
restore_from_cache() {
    local cache_key="$1"
    local script_name="$2"
    
    log_info "${CACHE_MARK} Checking cache for: $script_name (Key: ${cache_key:0:32}...)"
    
    # Use actions/cache logic manually via gh CLI or check local artifact
    # Since we can't run 'actions/cache' inside a script, we rely on the workflow
    # to handle the download. Instead, we will check if the file exists locally
    # IF the workflow downloaded it as an artifact.
    
    # NOTE: The actual "Download" logic is handled by the workflow step 
    # using actions/cache/restore. We assume if the file exists in .cache/components/, it was restored.
    local cached_file="$ROOT_DIR/.cache/components/${cache_key}.tar.zst"
    
    if [[ -f "$cached_file" ]]; then
        log_info "${CHECK_MARK} Cache HIT for $script_name. Restoring..."
        mkdir -p "$HOST_SHARED_DESTDIR"
        tar -I 'zstd -d -T0' -xf "$cached_file" -C "$HOST_SHARED_DESTDIR"
        
        # Merge into the main prefix
        rsync -a --checksum "$HOST_SHARED_DESTDIR/" "$HOST_SHARED_PREFIX/"
        
        # Reset destdir for next component
        rm -rf "$HOST_SHARED_DESTDIR"/*
        return 0
    else
        log_info "${ARCH_MARK} Cache MISS for $script_name. Building..."
        return 1
    fi
}

# Function to build a single component and save to cache
build_component() {
    local script_path="$1"
    local cache_key="$2"
    
    log_info "${BUILD_MARK} Building: $script_path"
    
    # Ensure destdir is clean
    rm -rf "$HOST_SHARED_DESTDIR"/*
    mkdir -p "$HOST_SHARED_DESTDIR"
    
    # Run the component inside Docker
    # We mount the host shared dirs so the build persists
    docker run --rm \
        --env TARGET="$TARGET" \
        --env VARIANT="$VARIANT" \
        --env CPU_ARCH="$CPU_ARCH" \
        --env CPU_TUNE="$CPU_TUNE" \
        --env FFBUILD_PREFIX="$SHARED_PREFIX" \
        --env FFBUILD_DESTDIR="$SHARED_DESTDIR" \
        --env FFBUILD_VERBOSE="$FFBUILD_VERBOSE" \
        --env SKIP_SYNC=1 \
        --mount type=bind,source="$HOST_SHARED_PREFIX",target="$SHARED_PREFIX" \
        --mount type=bind,source="$HOST_SHARED_DESTDIR",target="$SHARED_DESTDIR" \
        --mount type=bind,source="$ROOT_DIR/scripts.d",target="/builder/scripts.d" \
        --mount type=bind,source="$ROOT_DIR/util",target="/builder/util" \
        --mount type=bind,source="$ROOT_DIR/patches",target="/builder/patches" \
        --mount type=bind,source="$ROOT_DIR/variants",target="/builder/variants" \
        --mount type=bind,source="$ROOT_DIR/addins",target="/builder/addins" \
        --mount type=bind,source="$ROOT_DIR/.cache/downloads",target="/builder/.cache/downloads" \
        ghcr.io/${GITHUB_REPOSITORY,,}/base-win64:latest \
        /bin/bash -c "
            source /builder/util/vars.sh '$TARGET' '$VARIANT' &&
            export FFBUILD_PREFIX='$SHARED_PREFIX' &&
            export FFBUILD_DESTDIR='$SHARED_DESTDIR' &&
            run_stage /builder/scripts.d/$(basename "$script_path")
        "
    
    if [[ $? -eq 0 ]]; then
        log_info "${SAVE_MARK} Saving build result for $script_path"
        mkdir -p "$ROOT_DIR/.cache/components"
        tar -I 'zstd -T0 -3' -cf "$ROOT_DIR/.cache/components/${cache_key}.tar.zst" -C "$HOST_SHARED_DESTDIR" .
        
        # Merge into main prefix
        rsync -a --checksum "$HOST_SHARED_DESTDIR/" "$HOST_SHARED_PREFIX/"
        
        # Reset destdir
        rm -rf "$HOST_SHARED_DESTDIR"/*
    else
        log_error "Build FAILED for $script_path"
        exit 1
    fi
}

# Main Loop
log_info "${START_MARK} Starting Component Build Dispatcher"

# Get the list of active scripts (same logic as generate.sh)
mapfile -t SCRIPTS < <(find scripts.d -name "*.sh" | sort)

active_scripts=()
for STAGE in "${SCRIPTS[@]}"; do
    STAGE_BASE="$(basename "$STAGE" .sh)"
    
    # Check ONLY_STAGE filter
    if [[ -n "$ONLY_STAGE" ]]; then
        matched=0
        IFS='|' read -ra _patterns <<< "$ONLY_STAGE"
        for pattern in "${_patterns[@]}"; do
            if [[ "$STAGE_BASE" == "$pattern" ]] || [[ "$STAGE_BASE" == *"-${pattern}" ]] || [[ "$STAGE_BASE" =~ $pattern ]]; then
                matched=1; break
            fi
        done
        [[ $matched -eq 0 ]] && continue
    fi

    # Check if enabled
    if ( source "$UTIL_DIR/vars.sh" "$TARGET" "$VARIANT" 2>/dev/null; source "$STAGE" 2>/dev/null; ffbuild_enabled ) 2>/dev/null; then
        active_scripts+=("$STAGE")
    else
        log_info "${XCLAM_MARK} Skipping disabled stage: $(basename "$STAGE")"
    fi
done

log_info "Found ${#active_scripts[@]} active components to build."

for STAGE in "${active_scripts[@]}"; do
    CACHE_KEY=$(get_cache_key "$STAGE")
    
    if restore_from_cache "$CACHE_KEY" "$(basename "$STAGE")"; then
        continue
    else
        build_component "$STAGE" "$CACHE_KEY"
    fi
    
    # Optional: Upload to GitHub Cache here if not using file-based cache
    # For now, we assume the workflow handles the upload of the .cache/components folder
done

log_info "${CHECK_MARK} All components built successfully."