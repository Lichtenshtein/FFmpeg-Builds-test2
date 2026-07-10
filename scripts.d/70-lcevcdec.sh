#!/bin/bash

SCRIPT_REPO="https://github.com/v-novaltd/LCEVCdec.git"
SCRIPT_COMMIT="a254bd474649e5dcd8182689ac414420bfe8d8c3"

ffbuild_depends() {
    echo vulkan-headers
    echo vulkan-loader
    echo shaderc
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DVN_SDK_BENCHMARK=OFF
        -DVN_SDK_DIAGNOSTICS_ASYNC=OFF
        -DVN_SDK_DOCS=OFF
        -DVN_SDK_EXECUTABLES=OFF
        # -DVN_SDK_FORCE_OVERLAY=OFF # old
        -DVN_SDK_GENERATE_PGO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF) # this is NOT LTO
        -DVN_SDK_JSON_CONFIG=OFF
        # -DVN_SDK_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DVN_SDK_METRICS=OFF
        -DVN_SDK_PIPELINE_CPU=ON
        # -DVN_SDK_PIPELINE_LEGACY=ON # ON; old
        -DVN_SDK_PIPELINE_VULKAN=$([ "${TARGET}" == "win64" ] && echo ON || echo OFF) # OFF; experimental Vulkan GPU pipeline for decoding LCEVC stream
        -DVN_SDK_SAMPLE_SOURCE=OFF
        -DVN_SDK_SIMD=ON
        -DVN_SDK_SYSTEM_INSTALL=ON
        -DVN_SDK_THREADING=ON
        -DVN_SDK_TRACING=OFF
        -DVN_SDK_UNIT_TESTS=OFF
        -DVN_STRIP_RELEASE=OFF
        )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DBUILD_SHARED_LIBS=ON VN_MSVC_RUNTIME_STATIC=OFF ) || \
        myconf+=( -DBUILD_SHARED_LIBS=OFF VN_MSVC_RUNTIME_STATIC=ON )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

# ===========================================================
# Automatic insurance (fail-safe) for Vulkan KHR WSI symbols
# ===========================================================
# We don't need to compile the heavy Khronos loader. We can generate the correct C code directly, which will use built-in Windows functions to directly open vulkan-1.dll and extract the necessary KHR symbols. When FFmpeg reaches LCEVC Vulkan decoding, the function call will fall into our wrapper, which will load vulkan-1.dll from the Windows system.
if [[ "${myconf[@]}" =~ "-DVN_SDK_PIPELINE_VULKAN=ON" ]]; then
    if [[ "${TARGET}" == "win64" && "${PREFER_SHARED}" != "1" ]]; then
        TARGET_SHIM_LIB="${FFBUILD_PREFIX}/lib/libvulkan-1.a"
        if [[ -f "$TARGET_SHIM_LIB" ]]; then
            # We are looking for a critical function required for the LCEVC Vulkan Pipeline to work
            log_info "${SEARCH_MARK} Checking libvulkan-1.a for KHR WSI extensions..."

            if ! "${FFBUILD_CROSS_PREFIX}nm" "$TARGET_SHIM_LIB" | grep -q "vkCreateSwapchainKHR"; then

                log_warn "Critical KHR symbols not found in stub! Generating a native proxy for Vulkan KHR functions..."

                cat << 'EOF' > /tmp/vulkan_khr_fix.c
#include <windows.h>

// Dynamically obtain function pointers directly from the Windows system library
static void* get_vulkan_proc(const char* name) {
    static HMODULE hVulkan = NULL;
    if (!hVulkan) {
        // Load the system dll, just like the original loader does
        hVulkan = LoadLibraryExA("vulkan-1.dll", NULL, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    }
    if (!hVulkan) return NULL;
    return (void*)GetProcAddress(hVulkan, name);
}

// Macro for generating wrappers with the correct calling convention for __stdcall (VKAPI_CALL)
#define IMPLEMENT_KHR_FUNC(ret, name, params, args, err_ret) \
    __declspec(dllexport) ret __stdcall name params { \
        typedef ret (__stdcall *PFN_##name) params; \
        static PFN_##name ptr = NULL; \
        if (!ptr) ptr = (PFN_##name)get_vulkan_proc(#name); \
        if (ptr) return ptr args; \
        return err_ret; \
    }

#define IMPLEMENT_KHR_VOID(name, params, args) \
    __declspec(dllexport) void __stdcall name params { \
        typedef void (__stdcall *PFN_##name) params; \
        static PFN_##name ptr = NULL; \
        if (!ptr) ptr = (PFN_##name)get_vulkan_proc(#name); \
        if (ptr) ptr args; \
    }

// Implement all the functions that the linker requested for LCEVC
IMPLEMENT_KHR_FUNC(int, vkGetPhysicalDeviceSurfaceSupportKHR, (void* pd, unsigned int qf, void* sf, unsigned int* pS), (pd, qf, sf, pS), -13)
IMPLEMENT_KHR_VOID(vkDestroySwapchainKHR, (void* dev, void* sc, void* pAl), (dev, sc, pAl))
IMPLEMENT_KHR_VOID(vkDestroySurfaceKHR, (void* inst, void* sf, void* pAl), (inst, sf, pAl))
IMPLEMENT_KHR_FUNC(int, vkGetPhysicalDeviceSurfaceCapabilitiesKHR, (void* pd, void* sf, void* pCp), (pd, sf, pCp), -13)
IMPLEMENT_KHR_FUNC(int, vkGetPhysicalDeviceSurfaceFormatsKHR, (void* pd, void* sf, unsigned int* pCount, void* pF), (pd, sf, pCount, pF), -13)
IMPLEMENT_KHR_FUNC(int, vkGetPhysicalDeviceSurfacePresentModesKHR, (void* pd, void* sf, unsigned int* pCount, int* pM), (pd, sf, pCount, pM), -13)
IMPLEMENT_KHR_FUNC(int, vkCreateSwapchainKHR, (void* dev, void* pCi, void* pAl, void* pSc), (dev, pCi, pAl, pSc), -13)
IMPLEMENT_KHR_FUNC(int, vkGetSwapchainImagesKHR, (void* dev, void* sc, unsigned int* pCount, void* pIm), (dev, sc, pCount, pIm), -13)
EOF

            log_info "${BUILD_MARK} Compilable micro-proxy /tmp/vulkan_khr_fail_safe.c..."

            $CC $CFLAGS -c /tmp/vulkan_khr_fix.c -o /tmp/vulkan_khr_fix.o

            # We embed the object file directly into the existing static archive in the cache
            log_info "${SAVE_MARK} Embedding KHR symbols into the existing libvulkan-1.a archive..."

            $AR rcs "$TARGET_SHIM_LIB" /tmp/vulkan_khr_fix.o
            $RANLIB "$TARGET_SHIM_LIB"

            log_info "${CHECK_MARK} The libvulkan-1.a library has been successfully modified and is ready for use."

            rm -f /tmp/vulkan_khr_fix.c /tmp/vulkan_khr_fix.o

            else
                log_info "${CHECK_MARK} The libvulkan-1.a library contains all necessary KHR symbols. No patch is required."
            fi
        fi
    fi
fi
# ==============================================================================

    # if [[ "${myconf[@]}" =~ "-DVN_SDK_PIPELINE_LEGACY=ON" ]]; then
        # local SDK_PIPELINE_LEGACY="-llcevc_dec_legacy"
    # fi

    # local PC_FILE="$PC_DIR/lcevc_dec.pc"
    # cat <<EOF > "$PC_FILE"
# prefix=$FFBUILD_PREFIX
# exec_prefix=\${prefix}
# libdir=\${prefix}/lib
# includedir=\${prefix}/include

# Name: lcevc_dec
# Description: LCEVC Decoder SDK (Static Combined)
# Version: ${VER_FULL}
# Libs: -L\${libdir} -llcevc_dec_api -llcevc_dec_api_utility -llcevc_dec_common -llcevc_dec_enhancement -llcevc_dec_extract $SDK_PIPELINE_LEGACY -llcevc_dec_overlay_images -llcevc_dec_pipeline -llcevc_dec_pipeline_cpu -llcevc_dec_pipeline_legacy -llcevc_dec_pipeline_vulkan -llcevc_dec_pixel_processing -llcevc_dec_sequencer
# Libs.private: -lstdc++ -lm
# Cflags: -I\${includedir} -I\${includedir}/LCEVC -DVNEnablePublicAPIExport
# EOF

    local PC_FILE="$PC_DIR/lcevc_dec.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i 's|^Libs.private:.*|& -llcevc_dec_extract|' "$PC_FILE"
        sed -i "s|^Cflags:.*|& -I\${includedir}/LCEVC|" "$PC_FILE"

        # Вырезаем glfw3 из строки Requires.private
        sed -i 's/glfw3//g' "$PC_FILE"

        # Подчищаем возможные висячие пробелы, чтобы строка осталась валидной
        sed -i 's/Requires.private:  /Requires.private: /g' "$PC_FILE"

        if [[ "${myconf[@]}" =~ "-DVN_SDK_PIPELINE_VULKAN=ON" ]]; then
            sed -i 's/Requires.private: *$/Requires.private: vulkan/g' "$PC_FILE"
        fi
    fi

    # Удаляем лишние/кривые .pc файлы, чтобы pkg-config не путался
    rm -f "$PC_DIR"/lcevc_dec_utility.pc "$PC_DIR"/lcevc_dec_extract.pc

    rm -rf "${INSTALL_ROOT}"/share
}

ffbuild_configure() {
    echo --enable-liblcevc_dec
}

ffbuild_unconfigure() {
    echo --disable-liblcevc_dec
}
