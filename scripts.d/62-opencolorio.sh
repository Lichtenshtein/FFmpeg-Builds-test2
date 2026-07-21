#!/bin/bash

SCRIPT_REPO="https://github.com/AcademySoftwareFoundation/OpenColorIO.git"
SCRIPT_COMMIT="5a808fb57a94c7229640a97835c420c9a1fbd1fe"

ffbuild_depends() {
    echo zlib
    echo lcms2
    echo vulkan-loader
    echo shaderc # needs glslang
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf tests docs"
}

ffbuild_dockerbuild() {
    set -e

    # update YAML-CPP to 0.9.0 ---
    local TARGET_TAG_FILE=$(find . -name "Installyaml-cpp.cmake" -o -name "yaml-cpp.cmake" | head -n 1)
    local YAML_CPP_FILE="share/cmake/modules/install/Installyaml-cpp.cmake"

    if [[ -n "$TARGET_TAG_FILE" ]]; then
        log_info "Found yaml-cpp installer configuration at: ${TARGET_TAG_FILE}"
        log_info "Forcing yaml-cpp update to manual commit (v0.9.0) and disabling shallow clone..."
        # write the commit into the tag variable
        sed -i 's/set(yaml-cpp_GIT_TAG .*/set(yaml-cpp_GIT_TAG "2decf96e915d2b0c26c68c1659665789dfef2633")/g' "$TARGET_TAG_FILE"
        sed -i 's/set(yaml-cpp_VERSION .*/set(yaml-cpp_VERSION "0.9.0")/g' "$TARGET_TAG_FILE"
        # allow Git to download deep commit history
        sed -i '/GIT_SHALLOW/d' "$TARGET_TAG_FILE"
    fi

    if [[ -f "$YAML_CPP_FILE" ]]; then
        log_warn "Attempting direct sed on Installyaml-cpp.cmake"
        sed -i 's/set(yaml-cpp_GIT_TAG .*/set(yaml-cpp_GIT_TAG "2decf96e915d2b0c26c68c1659665789dfef2633")/g' "$YAML_CPP_FILE"
        # cut out shallow clone in case this path works
        sed -i '/GIT_SHALLOW/d' "$YAML_CPP_FILE"

        log_info "Injecting -include cstdint directly into yaml-cpp compile flags..."
        sed -i '/string(STRIP "${yaml-cpp_CXX_FLAGS}"/i \        set(yaml-cpp_CXX_FLAGS "${yaml-cpp_CXX_FLAGS} -include cstdint")' "$YAML_CPP_FILE"
    else
        log_warn "Target template file $YAML_CPP_FILE not found for flag injection!"
    fi

    # Patch FileTransform.cpp for std::wstring compatibility
    local FILE_TRANSFORM_SRC="src/OpenColorIO/transforms/FileTransform.cpp"
    if [[ -f "$FILE_TRANSFORM_SRC" ]]; then
        log_info "Patching FileTransform.cpp for MinGW GCC 15 std::wstring compatibility..."

        sed -i 's/Platform::filenameToUTF(filepath)/Platform::filenameToUTF(filepath).c_str()/g' "$FILE_TRANSFORM_SRC"
    else
        log_warn "Could not find $FILE_TRANSFORM_SRC to apply the c_str() patch!"
    fi

    # Disable old opengl (glew/glut) checks for mingw
    local GL_CHECK_FILE="share/cmake/utils/CheckSupportGL.cmake"
    if [[ -f "$GL_CHECK_FILE" ]]; then
        log_info "Patching CheckSupportGL.cmake to bypass GLEW/GLUT checks for Vulkan/DX12..."
        sed -i 's/set(OCIO_GL_ENABLED ON)/set(OCIO_GL_ENABLED OFF)/g' "$GL_CHECK_FILE"
        sed -i 's/message(WARNING "GPU rendering disabled")/# message(WARNING "GPU rendering disabled")/g' "$GL_CHECK_FILE"
    fi

    # ignore the OCIO_BUILD_APPS=OFF flag and force CMake to build helpers
    local LIBUTILS_CMAKE="src/libutils/CMakeLists.txt"
    if [[ -f "$LIBUTILS_CMAKE" ]]; then
        log_info "Forcing unconditional activation of oglapphelpers..."
        cat << 'EOF' > "$LIBUTILS_CMAKE"
add_subdirectory(oglapphelpers)
EOF
    else
        log_warn "Could not find $LIBUTILS_CMAKE to patch!"
    fi

    # Isolate the application folder
    local SRC_CMAKE_FILE="src/CMakeLists.txt"
    if [[ -f "$SRC_CMAKE_FILE" ]]; then
        log_info "Disabling the apps subdirectory to isolate oglapphelpers compilation..."
        sed -i 's/add_subdirectory(apps)/# add_subdirectory(apps)/g' "$SRC_CMAKE_FILE"
    else
        log_warn "Could not find $SRC_CMAKE_FILE to patch apps directory out!"
    fi

    local DXAPP_SRC="src/libutils/oglapphelpers/dxapp.cpp"
    if [[ -f "$DXAPP_SRC" ]]; then
        log_info "Applying deep MinGW compatibility patches to dxapp.cpp..."

        # Patch _uuidof
        sed -i 's/_uuidof(ID3D12Device)/IID_ID3D12Device/g' "$DXAPP_SRC"
        # patch for ALL calls to GetCPUDescriptorHandleForHeapStart()
        sed -i 's/\([a-zA-Z0-9_]*\)->GetCPUDescriptorHandleForHeapStart()/([\&](){ D3D12_CPU_DESCRIPTOR_HANDLE h; \1->GetCPUDescriptorHandleForHeapStart(\&h); return h; })()/g' "$DXAPP_SRC"

        # patch to GetGPUDescriptorHandleForHeapStart() call
        sed -i 's/\([a-zA-Z0-9_]*\)->GetGPUDescriptorHandleForHeapStart()/([\&](){ D3D12_GPU_DESCRIPTOR_HANDLE h; \1->GetGPUDescriptorHandleForHeapStart(\&h); return h; })()/g' "$DXAPP_SRC"
        log_info "dxapp.cpp successfully patched in all 6 locations."
    fi

    # glslang search patch with emulation of internal CMake targets
    local OGL_HELPERS_CMAKE="src/libutils/oglapphelpers/CMakeLists.txt"
    if [[ -f "$OGL_HELPERS_CMAKE" ]]; then
        log_info "Injecting bulletproof glslang PkgConfig emulator into ${OGL_HELPERS_CMAKE}..."

        # Create a temporary file with new content for the Vulkan block
        cat << 'EOF' > /tmp/vulkan_patch.cmake
if(OCIO_VULKAN_ENABLED)
    find_package(Vulkan REQUIRED)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(GLSLANG REQUIRED IMPORTED_TARGET glslang)
    
    if(TARGET PkgConfig::GLSLANG AND NOT TARGET glslang::glslang)
        add_library(glslang::glslang INTERFACE IMPORTED)
        target_link_libraries(glslang::glslang INTERFACE PkgConfig::GLSLANG)
    endif()

    if(NOT TARGET glslang::glslang-default-resource-limits)
        add_library(glslang::glslang-default-resource-limits INTERFACE IMPORTED)
        target_link_libraries(glslang::glslang-default-resource-limits INTERFACE "${FFBUILD_PREFIX}/lib/libglslang-default-resource-limits.@LIB_EXT@")
    endif()

    if(NOT TARGET glslang::SPIRV)
        add_library(glslang::SPIRV INTERFACE IMPORTED)
        target_link_libraries(glslang::SPIRV INTERFACE "${FFBUILD_PREFIX}/lib/libSPIRV.@LIB_EXT@")
    endif()

    list(APPEND SOURCES vulkanapp.cpp)
    list(APPEND INCLUDES vulkanapp.h)
endif()
EOF

        # change the placeholder to the actual value of the variable
        sed -i "s|@LIB_EXT@|${lib_ext}|g" /tmp/vulkan_patch.cmake

        awk '
        /if\(OCIO_VULKAN_ENABLED\)/ {
            print "include(/tmp/vulkan_patch.cmake)"
            skip=1
            next
        }
        /endif\(\)/ && skip {
            skip=0
            next
        }
        !skip { print }
        ' "$OGL_HELPERS_CMAKE" > "${OGL_HELPERS_CMAKE}.tmp" && mv "${OGL_HELPERS_CMAKE}.tmp" "$OGL_HELPERS_CMAKE"

        log_info "glslang PkgConfig emulator successfully integrated via awk bridge."
    else
        log_warn "Could not find ${OGL_HELPERS_CMAKE} to apply glslang emulator!"
    fi

    MINIZIP_PATCH_FILE="share/cmake/modules/install/Installminizip-ng.cmake"
    if [ -f "$MINIZIP_PATCH_FILE" ]; then
        log_info "Injecting hardcoded static ZLIB paths into OpenColorIO minizip-ng installer..."

        sed -i 's|-DZLIB_LIBRARY=${ZLIB_LIBRARIES}|-DZLIB_LIBRARY=/opt/ffbuild/lib/libz.a|g' "$MINIZIP_PATCH_FILE"
        sed -i 's|-DZLIB_INCLUDE_DIR=${ZLIB_INCLUDE_DIRS}|-DZLIB_INCLUDE_DIR=/opt/ffbuild/include|g' "$MINIZIP_PATCH_FILE"

        sed -i '/-DBUILD_SHARED_LIBS=OFF/a \\            -DCMAKE_C_FLAGS="-I/opt/ffbuild/include"\n            -DCMAKE_CXX_FLAGS="-I/opt/ffbuild/include"' "$MINIZIP_PATCH_FILE"
    fi

    mkdir build "${INSTALL_ROOT}"/{lib,include} && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DOCIO_USE_WINDOWS_UNICODE=$([ "${TARGET}" == "win64" ] && echo ON || echo OFF)
        -DOCIO_USE_SOVERSION=ON
        -DOCIO_BUILD_APPS=OFF
        -DOCIO_USE_OIIO_FOR_APPS=OFF
        -DOCIO_GL_ENABLED=OFF
        -DOCIO_DIRECTX_ENABLED=$([ "${TARGET}" == "win64" ] && echo ON || echo OFF)
        -DOCIO_BUILD_OPENFX=ON # OpenFX plugins
        -DOCIO_BUILD_NUKE=OFF # nuke plugins
        -DOCIO_BUILD_TESTS=OFF
        -DOCIO_BUILD_GPU_TESTS=OFF
        -DOCIO_BUILD_DOCS=OFF
        -DOCIO_BUILD_PYTHON=OFF
        -DOCIO_BUILD_JAVA=OFF
        -DOCIO_WARNING_AS_ERROR=OFF
        # SIMD optimization settings
        -DOCIO_USE_SIMD=ON
        -DOCIO_USE_SSE2=ON
        -DOCIO_USE_SSE3=ON
        -DOCIO_USE_SSSE3=ON
        -DOCIO_USE_SSE4=ON
        -DOCIO_USE_SSE42=ON
        -DOCIO_USE_AVX=ON
        -DOCIO_USE_AVX2=ON
        -DOCIO_USE_F16C=ON
        -DOCIO_USE_AVX512=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF)
    )

    if has_library "vulkan-1"; then
        log_info "Vulkan library detected. Building with Vulkan support..."
        myconf+=(
            -DOCIO_VULKAN_ENABLED=ON
            -DCMAKE_PREFIX_PATH="${FFBUILD_PREFIX}"
            -DVulkan_INCLUDE_DIR="${FFBUILD_PREFIX}/include"
            -DVulkan_LIBRARY="${FFBUILD_PREFIX}/lib/libvulkan-1.${lib_ext}"
            -Dglslang_DIR="${FFBUILD_PREFIX}/lib/cmake/glslang"
            -Dglslang_ROOT="${FFBUILD_PREFIX}"
            -Dglslang_INCLUDE_DIR="${FFBUILD_PREFIX}/include/glslang"
        )
        local VULKAN_FLAG="-DOCIO_VULKAN_ENABLED"
    fi

    if has_library "z"; then
        log_info "ZLIB library detected. Using external ZLIB..."
        myconf+=(
            -DZLIB_LIBRARY="${FFBUILD_PREFIX}/lib/libz.${lib_ext}"
            -DZLIB_INCLUDE_DIR="${FFBUILD_PREFIX}/include"
            -DZLIB_USE_STATIC_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        )
        local Z_FLAG="-lz"
    fi

    if has_library "lcms2"; then
        log_info "lcms2 library detected. Using external lcms2..."
        myconf+=(
            -Dlcms2_LIBRARY="${FFBUILD_PREFIX}/lib/liblcms2.${lib_ext}"
            -Dlcms2_INCLUDE_DIR="${FFBUILD_PREFIX}/include"
            -Dlcms2_STATIC_LIBRARY=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        )
    fi

    # -DOpenColorIO_SKIP_IMPORTS (Removes __imp_ from OCIO functions in FFmpeg)
    # -DXML_STATIC (static import for expat)
    # -DYAML_CPP_STATIC_DEFINE (static import for yaml-cpp)
    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DOpenColorIO_SKIP_IMPORTS -DXML_STATIC -DYAML_CPP_STATIC_DEFINE"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
        find /build/$STAGENAME -type f -name "*.${lib_ext}" -printf "%p (%s bytes)\n"
    fi

    log_info "Dynamically collecting and installing OpenColorIO donor libraries..."

    local EXT_DIST_INC="ext/dist/include"
    # Copy expat headers in case they are used by other components
    if [[ -d "${EXT_DIST_INC}" ]]; then
        cp -rf${OP_V} "${EXT_DIST_INC}"/* "${INSTALL_ROOT}/include/"
    fi

    # Find all static libraries built within this stage
    # Filter the original libOpenColorIO.a
    local OCIO_STATIC_LIBS=$(find /build/$STAGENAME -type f -name "*.${lib_ext}" ! -name "libOpenColorIO.${lib_ext}" -printf "%f\n" | \
                 sed "s/^lib//; s/\.${lib_ext}$//" | sort -u | xargs -I{} echo -l{} | tr '\n' ' ')

    # Move all found .a donor libraries to the prefix
    find /build/$STAGENAME -type f -name "*.${lib_ext}" -exec cp -f${OP_V} {} "${INSTALL_ROOT}/lib/" \;

    local PC_FILE="$PC_DIR/OpenColorIO.pc"
    if [[ "${myconf[@]}" =~ "-DOCIO_DIRECTX_ENABLED=ON" ]]; then
        local DIRECTX_LIBS="-ld3d12 -ldxgi -ldxguid"
        local DIRECTX_FLAG="-DOCIO_DIRECTX_ENABLED"
    fi
    local DEP_LIBS="${OCIO_STATIC_LIBS} ${Z_FLAG} ${DIRECTX_LIBS} -lshlwapi -lstdc++"
    if [[ -f "$PC_FILE" ]]; then
        log_info "Patching OpenColorIO.pc with dynamic donor list"
        # cut out any .a extensions
        sed -i 's/\.a\b//g' "$PC_FILE"
        # Add system dependencies
        if grep -q "Libs.private:" "$PC_FILE"; then
            sed -i "/^Libs.private:/ s/$/ ${DEP_LIBS}/" "$PC_FILE"
        else
            echo "Libs.private: ${DEP_LIBS} -pthread" >> "$PC_FILE"
        fi

        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
            fi
        fi

        if [[ -n "${VULKAN_FLAG}" ]]; then
            for flag in ${VULKAN_FLAG}; do
                if ! grep -qF -- "$flag" "$PC_FILE"; then
                    sed -i "/^Cflags:/ s/$/ $flag/" "$PC_FILE"
                fi
            done
        fi

        if [[ -n "${DIRECTX_FLAG}" ]]; then
            for flag in ${DIRECTX_FLAG}; do
                if ! grep -qF -- "$flag" "$PC_FILE"; then
                    sed -i "/^Cflags:/ s/$/ $flag/" "$PC_FILE"
                fi
            done
        fi

        # Final cleaning of double .a.a extensions
        sed -i -E 's/\.a([[:space:]]|$)/\1/g' "$PC_FILE"
        sed -i -E 's/\.a\b//g' "$PC_FILE"
        sed -i 's/[[:space:]]\+/ /g' "$PC_FILE"
        log_info "Sanitized OpenColorIO.pc successfully."
    fi
}

ffbuild_configure() {
    echo --enable-libopencolorio
}

ffbuild_unconfigure() {
    echo --disable-libopencolorio
}
