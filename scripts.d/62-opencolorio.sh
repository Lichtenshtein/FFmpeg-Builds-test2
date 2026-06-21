#!/bin/bash

SCRIPT_REPO="https://github.com/AcademySoftwareFoundation/OpenColorIO.git"
SCRIPT_COMMIT="f660cee6127011fdb03e0d227572901631435d3c"

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
        log_info "Forcing yaml-cpp update to manual commit (v0.9.0)..."
        sed -i 's/set(yaml-cpp_GIT_TAG .*/set(yaml-cpp_GIT_TAG "2decf96e915d2b0c26c68c1659665789dfef2633")/g' "$TARGET_TAG_FILE"
        sed -i 's/set(yaml-cpp_VERSION .*/set(yaml-cpp_VERSION "0.9.0")/g' "$TARGET_TAG_FILE"
    fi

    if [[ -f "$YAML_CPP_FILE" ]]; then
        log_warn "Attempting direct sed on Installyaml-cpp.cmake"
        sed -i 's/set(yaml-cpp_GIT_TAG .*/set(yaml-cpp_GIT_TAG "2decf96e915d2b0c26c68c1659665789dfef2633")/g' "$YAML_CPP_FILE"
        log_info "Injecting -include cstdint directly into yaml-cpp compile flags..."
        sed -i '/string(STRIP "${yaml-cpp_CXX_FLAGS}"/i \        set(yaml-cpp_CXX_FLAGS "${yaml-cpp_CXX_FLAGS} -include cstdint")' "$YAML_CPP_FILE"
    else
        log_warn "Target template file $YAML_CPP_FILE not found for flag injection!"
    fi

    # Патч FileTransform.cpp для совместимости std::wstring
    local FILE_TRANSFORM_SRC="src/OpenColorIO/transforms/FileTransform.cpp"
    if [[ -f "$FILE_TRANSFORM_SRC" ]]; then
        log_info "Patching FileTransform.cpp for MinGW GCC 15 std::wstring compatibility..."

        sed -i 's/Platform::filenameToUTF(filepath)/Platform::filenameToUTF(filepath).c_str()/g' "$FILE_TRANSFORM_SRC"
    else
        log_warn "Could not find $FILE_TRANSFORM_SRC to apply the c_str() patch!"
    fi

    # Отключаем проверки старого opengl (glew/glut) для mingw
    local GL_CHECK_FILE="share/cmake/utils/CheckSupportGL.cmake"
    if [[ -f "$GL_CHECK_FILE" ]]; then
        log_info "Patching CheckSupportGL.cmake to bypass GLEW/GLUT checks for Vulkan/DX12..."
        sed -i 's/set(OCIO_GL_ENABLED ON)/set(OCIO_GL_ENABLED OFF)/g' "$GL_CHECK_FILE"
        sed -i 's/message(WARNING "GPU rendering disabled")/# message(WARNING "GPU rendering disabled")/g' "$GL_CHECK_FILE"
    fi

    # игнорируем флаг OCIO_BUILD_APPS=OFF и заставляем CMake собрать хелперы
    local LIBUTILS_CMAKE="src/libutils/CMakeLists.txt"
    if [[ -f "$LIBUTILS_CMAKE" ]]; then
        log_info "Forcing unconditional activation of oglapphelpers..."
        cat << 'EOF' > "$LIBUTILS_CMAKE"
add_subdirectory(oglapphelpers)
EOF
    else
        log_warn "Could not find $LIBUTILS_CMAKE to patch!"
    fi

    # Изолируем папку приложений 
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

        # Патч _uuidof
        sed -i 's/_uuidof(ID3D12Device)/IID_ID3D12Device/g' "$DXAPP_SRC"
        # патч для ВСЕХ вызовов GetCPUDescriptorHandleForHeapStart()
        sed -i 's/\([a-zA-Z0-9_]*\)->GetCPUDescriptorHandleForHeapStart()/([\&](){ D3D12_CPU_DESCRIPTOR_HANDLE h; \1->GetCPUDescriptorHandleForHeapStart(\&h); return h; })()/g' "$DXAPP_SRC"

        # патч для вызова GetGPUDescriptorHandleForHeapStart()
        sed -i 's/\([a-zA-Z0-9_]*\)->GetGPUDescriptorHandleForHeapStart()/([\&](){ D3D12_GPU_DESCRIPTOR_HANDLE h; \1->GetGPUDescriptorHandleForHeapStart(\&h); return h; })()/g' "$DXAPP_SRC"
        log_info "dxapp.cpp successfully patched in all 6 locations."
    fi

    mkdir build "${INSTALL_ROOT}"/{lib,include} && cd build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
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
        # Настройки SIMD-оптимизаций
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
            -DVulkan_LIBRARY="${FFBUILD_PREFIX}/lib/libvulkan-1.a"
            -Dglslang_DIR="${FFBUILD_PREFIX}/lib/cmake/glslang"
            -Dglslang_ROOT="${FFBUILD_PREFIX}"
            -Dglslang_INCLUDE_DIR="${FFBUILD_PREFIX}/include/glslang"
        )
        local VULKAN_FLAG="-DOCIO_VULKAN_ENABLED"
    fi

    if has_library "z"; then
        log_info "ZLIB library detected. Using external ZLIB..."
        myconf+=(
            -DZLIB_LIBRARY="${FFBUILD_PREFIX}/lib/libz.a"
            -DZLIB_INCLUDE_DIR="${FFBUILD_PREFIX}/include"
            -DZLIB_USE_STATIC_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        )
        local Z_FLAG="-lz"
    fi

    if has_library "lcms2"; then
        log_info "lcms2 library detected. Using external lcms2..."
        myconf+=(
            -Dlcms2_LIBRARY="${FFBUILD_PREFIX}/lib/liblcms2.a"
            -Dlcms2_INCLUDE_DIR="${FFBUILD_PREFIX}/include"
            -Dlcms2_STATIC_LIBRARY=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        )
    fi

    # -DOpenColorIO_SKIP_IMPORTS (Убирает __imp_ с функций OCIO в FFmpeg)
    # -DXML_STATIC               (статический импорт для expat)
    # -DYAML_CPP_STATIC_DEFINE   (статический импорт для yaml-cpp)
    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DOpenColorIO_SKIP_IMPORTS -DXML_STATIC -DYAML_CPP_STATIC_DEFINE"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
        find /build/$STAGENAME -type f -name "*.a" -printf "%p (%s bytes)\n"
    fi

    log_info "Dynamically collecting and installing OpenColorIO donor libraries..."

    local EXT_DIST_INC="ext/dist/include"
    # Копируем заголовки expat на случай использования другими компонентами
    if [[ -d "${EXT_DIST_INC}" ]]; then
        cp -rf${OP_V} "${EXT_DIST_INC}"/* "${INSTALL_ROOT}/include/"
    fi

    # Находим все статические библиотеки, собранные внутри этой стадии
    # Фильтруем оригинальную libOpenColorIO.a
    local OCIO_STATIC_LIBS=$(find /build/$STAGENAME/build -type f -name "*.a" ! -name "libOpenColorIO.a" -printf "%f\n" | \
                 sed 's/^lib//; s/\.a$//' | sort -u | xargs -I{} echo -l{} | tr '\n' ' ')

    # Переносим все найденные .a библиотеки-доноры в префикс
    find /build/$STAGENAME/build -type f -name "*.a" -exec cp -f${OP_V} {} "${INSTALL_ROOT}/lib/" \;

    local PC_FILE="$PC_DIR/OpenColorIO.pc"
    if [[ "${myconf[@]}" =~ "-DOCIO_DIRECTX_ENABLED=ON" ]]; then
        local WIN_LIBS="-ld3d12 -ldxgi -ldxguid"
    fi
    local DEP_LIBS="${OCIO_STATIC_LIBS} ${Z_FLAG} ${WIN_LIBS} -lshlwapi -lstdc++"
    if [[ -f "$PC_FILE" ]]; then
        log_info "Patching OpenColorIO.pc with dynamic donor list"
        if grep -q "Libs.private:" "$PC_FILE"; then
            sed -i "/^Libs.private:/ s/$/ ${DEP_LIBS}/" "$PC_FILE"
        else
            echo "Libs.private: ${DEP_LIBS} -pthread" >> "$PC_FILE"
        fi
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $static_flags ${VULKAN_FLAG} ${DIRECTX_FLAG}/" "$PC_FILE"
            fi
        fi
        sed -i 's/[[:space:]]\+/ /g' "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libopencolorio
}

ffbuild_unconfigure() {
    echo --disable-libopencolorio
}
