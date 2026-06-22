#!/bin/bash

SCRIPT_REPO="https://github.com/tesseract-ocr/tesseract.git"
SCRIPT_COMMIT="f4afb2cc9545f622a07812b09e1b72fc78f85a64"

ffbuild_depends() {
    echo leptonica
    echo libarchive
    echo pango
    echo cairo
    echo libtiff
    echo openssl
    echo libicu
    echo libcurl
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    log_debug "Patching CMakeLists.txt to fix case-sensitivity and disable executable..."
    # Fix Ws2_32 case
    find . -type f -name "CMakeLists.txt" -exec sed -i 's/Ws2_32/ws2_32/g' {} +
    # Disable the tesseract executable target and its links
    sed -i 's/.*add_executable(tesseract.*/# REMOVED EXE/g' CMakeLists.txt
    sed -i 's/.*target_link_libraries(tesseract.*/# REMOVED LINK/g' CMakeLists.txt
    sed -i 's/.*install(TARGETS tesseract.*/# REMOVED INSTALL/g' CMakeLists.txt

    # Patch CMakeLists.txt to control AVX-512 builds based on an external variable
    if [ "${USE_AVX512:-0}" == "0" ]; then
        log_info "Patching Tesseract CMake to enforce disabling AVX-512..."
        # Find the -mavx512f check block and forcibly disable the HAVE_AVX512F variable
        sed -i 's/check_cxx_compiler_flag("-mavx512f" HAVE_AVX512F)/set(HAVE_AVX512F FALSE)/g' CMakeLists.txt
    fi

    # Backing up "poisoned" CMake-конфиги TIFF и других либ, 
    # которые заставляют линкер искать ZLIB::ZLIB
    # This prevents CMake from appending its own -l flags OUTSIDE our group.
    local cmake_backup="/tmp/cmake_backup_tesseract"
    mkdir -p "$cmake_backup"
    log_debug "Backing up existing CMake configs to prevent interference..."
    find "$FFBUILD_PREFIX/lib/cmake" \
        \( -name "*Config.cmake" \
           -o -name "*-config.cmake" \
           -o -name "*Targets*.cmake" \
           -o -name "*targets*.cmake" \) \
        -exec mv -t "$cmake_backup" {} + 2>/dev/null || true

    # Восстанавливаем cmake файлы
    restore() {
        log_debug "Executing absolute fallback config restoration..."
        if [ -d "$cmake_backup" ]; then
            cp -n "$cmake_backup"/* "$FFBUILD_PREFIX/lib/cmake/" 2>/dev/null || true
            rm -rf "$cmake_backup"
        fi
        if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
            ls -lh "$FFBUILD_PREFIX/lib/cmake/"
        fi
    }
    trap restore EXIT

    # Create a LOCAL wrapper script
    local WRAPPER_DIR="${TMP_DIR}/tesseract_wrapper"
    mkdir -p "$WRAPPER_DIR"
    local LOCAL_GXX="${WRAPPER_DIR}/g++"
    local REAL_GXX="${FFBUILD_TOOLCHAIN}-g++"

    # Create wrapper
    cat > "$LOCAL_GXX" << 'WRAPPER_EOF'
#!/bin/bash
REAL_GXX="${0}.bak"
args=()
for arg in "$@"; do
    if [[ "$arg" == @* ]]; then
        rsp="${arg#@}"
        if [[ -f "$rsp" ]]; then
            while IFS= read -r token || [[ -n "$token" ]]; do
                for t in $token; do args+=("$t"); done
            done < "$rsp"
        else
            args+=("$arg")
        fi
    else
        args+=("$arg")
    fi
done

if printf '%s\n' "${args[@]}" | grep -q "\.exe" || printf '%s\n' "${args[@]}" | grep -q "\.dll"; then
    exec "$REAL_GXX" "${args[@]}"
else
    exec "$REAL_GXX" "${args[@]}"
fi
WRAPPER_EOF

    # Fix the REAL_GXX path inside the wrapper
    # We inject the actual path at runtime
    sed -i "s|REAL_GXX=\"\${0}.bak\"|REAL_GXX=\"$(command -v ${REAL_GXX})\"|" "$LOCAL_GXX"
    chmod +x "$LOCAL_GXX"

    mkdir -p build && cd build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_TESTS=OFF
        -DBUILD_TRAINING_TOOLS=OFF # causes strange pgp path '=/include' errors
        -DOPENMP_BUILD=$([[ $target != "win64" && "${USE_OPENMP}" == "1" ]] && echo ON || echo OFF) # DO NOT enable it for Win64
        -DFAST_FLOAT=ON
        -DSW_BUILD=OFF
        # -DENABLE_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DLeptonica_DIR=OFF # Leptonica use our manual path, not CMake target
        # Explicit library paths so CMake's try_compile doesn't fail
        -DCMAKE_CXX_COMPILER="$LOCAL_GXX" # <--- Use local wrapper
        -DCMAKE_C_COMPILER="${FFBUILD_TOOLCHAIN}-gcc"
        -DCMAKE_FIND_ROOT_PATH="$FFBUILD_PREFIX" # <--- Isolate search paths
        -DCMAKE_PREFIX_PATH="$FFBUILD_PREFIX"
        -DCMAKE_FIND_LIBRARY_SUFFIXES=".a"
        -DPKG_CONFIG_EXECUTABLE="$(command -v ${PKG_CONFIG})"
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DCURL_STATICLIB -DLIBARCHIVE_STATIC -DPTW32_STATIC_LIB"

    if has_library "curl"; then
        log_info "curl library detected. Building with curl support..."
        myconf+=(
            -DDISABLE_CURL=OFF
        )
        local CURL_LIBS="-lcurl"
        local CURL_PC="libcurl"
    else
        myconf+=(
            -DDISABLE_CURL=ON
        )
    fi

    if has_library "tiff"; then
        log_info "TIFF library detected. Building with TIFF support..."
        myconf+=(
            -DDISABLE_TIFF=OFF
            -DLEPT_TIFF_RESULT=0
            -DLEPT_TIFF_COMPILE_SUCCESS=ON
        )
        local TIFF_PC="tiff"
    else
        myconf+=(
            -DDISABLE_TIFF=ON
        )
    fi

    if has_library "archive"; then
        log_info "Libarchive library detected. Building with Libarchive support..."
        myconf+=(
            -DDISABLE_ARCHIVE=OFF
        )
        local ARCHIVE_LIBS="-larchive"
        local ARCHIVE_PC="libarchive"
    else
        myconf+=(
            -DDISABLE_ARCHIVE=ON
        )
    fi

    if [[ "${myconf[@]}" =~ "-DBUILD_TRAINING_TOOLS=ON" ]]; then
        local DEP_LIBS=$(get_pc_libs lept pangocairo ${ARCHIVE_PC} ${CURL_PC} icu-i18n)
        myconf+=(
            -DUSE_SYSTEM_ICU=ON
        )
    else
        local DEP_LIBS=$(get_pc_libs lept ${ARCHIVE_PC} ${CURL_PC})
    fi

    local C_FLAGS="-DWIN32_LEAN_AND_MEAN -D_WINSOCK_DEPRECATED_NO_WARNINGS"
    local LINKER_GROUP="-Wl,--start-group ${DEP_LIBS} ${LIBS} -Wl,--end-group"

    cmake -G Ninja "${myconf[@]}"  \
        -DCMAKE_C_FLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} ${C_FLAGS} $static_flags" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} ${C_FLAGS} $static_flags" \
        -DCMAKE_C_STANDARD_LIBRARIES="${LINKER_GROUP}" \
        -DCMAKE_CXX_STANDARD_LIBRARIES="${LINKER_GROUP}" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS ${USELTO} -Wl,--allow-multiple-definition" \
        -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS ${USELTO} -Wl,--allow-multiple-definition" \
        .. || return 1

    # Clear INTERFACE_LINK_LIBRARIES (belt and suspenders)
    # find . -name "TesseractTargets.cmake" -o -name "*Targets*.cmake" 2>/dev/null \
    # | xargs grep -l "INTERFACE_LINK_LIBRARIES" 2>/dev/null \
    # | while read -r f; do
        # log_debug "Clearing INTERFACE_LINK_LIBRARIES in $f"
        # sed -i 's/INTERFACE_LINK_LIBRARIES "[^"]*"/INTERFACE_LINK_LIBRARIES ""/g' "$f"
    # done

    # Собираем только библиотеку
    ninja $NINJA_V libtesseract || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/tesseract.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "/^Libs.private:/ s/$/ ${ARCHIVE_LIBS} ${CURL_LIBS}/" "$PC_FILE"
        sed -i "s|^Cflags:.*|& -I\${includedir}/tesseract|" "$PC_FILE"
        sed -i "s|^Requires.private:.*|Requires.private: lept ${TIFF_PC}|" "$PC_FILE"
        if [[ "${myconf[@]}" =~ "-DBUILD_TRAINING_TOOLS=ON" ]]; then
            sed -i '/^Requires.private:.*/ s/$/ pangocairo icu-uc/' "$PC_FILE"
        fi
    fi

    # log_debug "=== linkLibs.rsp full content ==="
    # cd ..
    # find . -name "linkLibs.rsp" -exec echo "FILE: {}" \; -exec cat {} \; >&2
}

ffbuild_configure() {
    echo --enable-libtesseract
}

ffbuild_unconfigure() {
    echo --disable-libtesseract
}