#!/bin/bash

# SCRIPT_REPO="https://github.com/stenzek/shaderc.git"
# SCRIPT_COMMIT="d72697bfc353b547efc58421ad54ac0345441bf4"

SCRIPT_REPO="https://github.com/google/shaderc.git"
SCRIPT_COMMIT="cb6f1ef84daaa5e0369e0e6d82008438d42c93b5"

# patch skipper
# export SKIP_PRE_PATCH=1

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .

    if [[ "$SHADERC_UPDATE" == "1" ]]; then
        local STAGENAME COMPONENT_NAME CUSTOM_DEPS
        STAGENAME="$(basename "$STAGE" .sh)"
        COMPONENT_NAME="${STAGENAME#*-}"
        # Replace the DEPS file with the file from the patches folder.
        CUSTOM_DEPS="${PATCHES_DIR}/${COMPONENT_NAME}/DEPS"
        if [[ -f "$CUSTOM_DEPS" ]]; then
            # The destination ./DEPS is relative to WORK_DIR (correct Ч runs after clone)
            # Use cat instead of cp to avoid permission issues on read-only source
            echo "log_info '${SYNC_MARK} Replacing shaderc DEPS with custom version from patches...'"
            echo "cat $(printf '%q' "$CUSTOM_DEPS") > ./DEPS"
        else
            log_warn "Custom DEPS not found at ${CUSTOM_DEPS}, using default."
        fi
    fi

    # Run dependency synchronization.
    # It will now use our updated DEPS file with the new hashes.
    echo "./utils/git-sync-deps || exit $?"

    if [[ -d ".git" ]]; then
        git add .
    fi
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local myconf=(
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_BUILD_TYPE=Release
        -DENABLE_EXCEPTIONS=ON
        -DENABLE_GLSLANG_BINARIES=OFF
        -DENABLE_GLSLANG_JS=OFF
        -DENABLE_HLSL=ON
        -DENABLE_OPT=ON
        -DENABLE_PCH=OFF
        -DENABLE_RTTI=ON
        -DENABLE_SPIRV=ON
        -DGLSLANG_ENABLE_INSTALL=ON
        -DGLSLANG_TESTS=OFF
        -DSHADERC_SKIP_COPYRIGHT_CHECK=ON
        -DSHADERC_SKIP_EXAMPLES=ON
        -DSHADERC_SKIP_TESTS=ON
        -DSKIP_SPIRV_TOOLS_INSTALL=OFF
        -DSPIRV_CHECK_CONTEXT=OFF
        -DSPIRV_HEADERS_ENABLE_INSTALL=ON
        -DSPIRV_HEADERS_ENABLE_TESTS=OFF
        -DSPIRV_SKIP_EXECUTABLES=ON
        -DSPIRV_SKIP_TESTS=ON
        -DSPIRV_WARN_EVERYTHING=OFF
        -DSPIRV_WERROR=OFF
    )

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        myconf+=(
            -DSPIRV_TOOLS_BUILD_SHARED=ON
            -DSPIRV_TOOLS_BUILD_STATIC=OFF
            -DSPIRV_TOOLS_LIBRARY_TYPE=SHARED
            -DSHADERC_ENABLE_SHARED_CRT=ON
            -DBUILD_SHARED_LIBS=ON
        )
    else
        myconf+=(
            -DSPIRV_TOOLS_BUILD_SHARED=OFF
            -DSPIRV_TOOLS_BUILD_STATIC=ON
            -DSPIRV_TOOLS_LIBRARY_TYPE=STATIC
            -DSHADERC_ENABLE_SHARED_CRT=OFF
            -DBUILD_SHARED_LIBS=OFF
        )
    fi

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/shaderc.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: shaderc
Description: Tools and libraries for Vulkan shader compilation (Static Combined)
Version: 2026.1
Libs: -L\${libdir} -lshaderc_combined -lshaderc_util -lglslang -lMachineIndependent -lGenericCodeGen -lOSDependent -lSPIRV -lSPIRV-Tools-opt -lSPIRV-Tools-link -lSPIRV-Tools
Libs.private: -lstdc++ -lgomp -lsetupapi -lm -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lws2_32 -lbcrypt -pthread
Cflags: -I\${includedir} -I\${includedir}/shaderc
EOF

    cat >"$PC_DIR/glslang.pc" <<EOF
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: glslang
Description: glslang library
Version: 16.2.0
Libs: -L\${libdir} -lglslang -lMachineIndependent -lGenericCodeGen -lOSDependent -lSPIRV -lglslang-default-resource-limits
Cflags: -I\${includedir} -I\${includedir}/glslang
EOF

    # дублируем его в shaderc_combined.pc и shaderc_static.pc для совместимости
    cp ${OP_VERB} "$PC_DIR/shaderc.pc" "$PC_DIR/shaderc_combined.pc"
    cp ${OP_VERB} "$PC_DIR/shaderc.pc" "$PC_DIR/shaderc_static.pc"

    sed -i '/^Libs:/ s/$/ -lstdc++/' "$PC_DIR/shaderc_combined.pc"
    sed -i '/^Libs:/ s/$/ -lstdc++/' "$PC_DIR/shaderc_static.pc"

    cp ${OP_VERB} "$PC_DIR"/{shaderc_combined,shaderc}.pc

    # Native build for the glslc tool (Host side)
    log_info "Building native glslang and shaderc tools..."
    mkdir ../native_build && cd ../native_build

    (
        unset CC CXX CFLAGS CXXFLAGS LD LDFLAGS AR RANLIB NM DLLTOOL PKG_CONFIG_LIBDIR PKG_CONFIG_PATH

        # Note: We don't use the toolchain file for native build
        CFLAGS="$HOST_CFLAGS" \
        CXXFLAGS="$HOST_CXXFLAGS" \
        LDFLAGS="$HOST_LDFLAGS" \
        LD="${HOST_LD}"
        cmake -G Ninja \
            -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_C_COMPILER=gcc \
            -DCMAKE_CXX_COMPILER=g++ \
            -DSHADERC_SKIP_TESTS=ON \
            -DSHADERC_SKIP_EXAMPLES=OFF \
            -DENABLE_GLSLANG_BINARIES=ON \
            -DSPIRV_SKIP_EXECUTABLES=OFF \
            .. || exit 1

        # собираем цель glslc_exe в последних версиях бинарник привязан к ней
        log_info "Building native glslc..."
        ninja $NINJA_V glslc glslc_exe || true
        log_info "Building native glslang..."
        ninja $NINJA_V glslang-standalone || true

        # Массив инструментов для проверки и копирования
        # Формат: "имя_бинарника|целевое_имя_в_системе"
        local TOOLS_TO_COPY=("glslc|glslc" "glslang|glslang")
        local FOUND_ANY=0

        for ENTRY in "${TOOLS_TO_COPY[@]}"; do
            local BIN_NAME="${ENTRY%|*}"
            local DEST_NAME="${ENTRY#*|}"
            local BIN_PATH=$(find . -type f -name "$BIN_NAME" -executable | head -n 1)

            if [[ -n "$BIN_PATH" && -f "$BIN_PATH" ]]; then
                log_info "Found $BIN_NAME at $BIN_PATH. Copying..."
                cp ${OP_VERB} "$BIN_PATH" "/usr/local/bin/$DEST_NAME"
                # Дополнительная копия для Whisper
                [[ "$BIN_NAME" == "glslc" ]] && cp ${OP_VERB} "$BIN_PATH" /opt/glslc
                FOUND_ANY=1
                # Создаем критически важный симлинк для LCEVC
                ln -sf /usr/local/bin/glslang /usr/local/bin/glslangValidator
                log_info "Native glslang and glslangValidator (symlink) installed."
            else
                log_warn "Binary $BIN_NAME not found in build directory."
            fi
        done

        if [[ "$FOUND_ANY" -eq 0 ]]; then
            log_error "No native binaries were built! Listing executable files:"
            find . -maxdepth 5 -executable -type f
            return 1
        fi

    ) || return 1

    if [ -d "$PC_DIR" ]; then
        sed -i "s|^Cflags:.*|& -I\${includedir}/spirv-tools|" "$PC_DIR/SPIRV-Tools.pc"
        sed -i "s|^Cflags:.*|& -I\${includedir}/spirv-tools -I\${includedir}/spirv -I\${includedir}/glslang -I\${includedir}/shaderc|" "$PC_DIR/shaderc_static.pc"
        sed -i "s|^Cflags:.*|& -I\${includedir}/spirv-tools -I\${includedir}/spirv -I\${includedir}/glslang -I\${includedir}/shaderc|" "$PC_DIR/shaderc_combined.pc"
        log_info "Cflags paths have been updated."
    fi
}

# --enable-libshaderc or --enable-libglslang not both
ffbuild_configure() {
    echo --enable-libshaderc
}

ffbuild_unconfigure() {
    echo --disable-libshaderc
}
