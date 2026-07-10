#!/bin/bash

SCRIPT_REPO="https://github.com/BtbN/Vulkan-Shim-Loader.git"
SCRIPT_COMMIT="65b3936528cd92eb4ea3de485d03f858a3850484"

SCRIPT_REPO2="https://github.com/KhronosGroup/Vulkan-Headers.git"
SCRIPT_COMMIT2="8d6039a455a7ecc7d2a592ff97f62db4e59b70bf"

# original loader
# SCRIPT_REPO3="https://github.com/KhronosGroup/Vulkan-Loader.git"
# SCRIPT_COMMIT3="1a588f1982c14309873f2a86a60cfbfe5fb249f8"

if [[ $TARGET != win64 ]]; then
    # patches will not apply due to folder contains patches for original loader
    export SKIP_PRE_PATCH=1
fi

ffbuild_depends() {
    echo vulkan-headers
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
    SCRIPT_BRANCH="" # Сбрасываем, чтобы не мешала первой загрузке
    echo "git-mini-clone \"$SCRIPT_REPO2\" \"$SCRIPT_COMMIT2\" Vulkan-Headers"
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local myconf=(
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DVULKAN_SHIM_IMPERSONATE=ON
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

if [[ "${PREFER_SHARED}" != "1" ]]; then
    # Путь к скомпилированной статической библиотеке
    local TARGET_LIB="${INSTALL_ROOT}/lib/libvulkan-1.a"

    if [[ -f "$TARGET_LIB" ]]; then
        log_info "${CHECK_MARK} libvulkan-1.a successfully compiled and installed."

        # Массив функций, которые мы обязаны были прокинуть для lcevc
        local LCEVC_CHECK_LIST=(
            "vkGetPhysicalDeviceSurfaceSupportKHR"
            "vkDestroySwapchainKHR"
            "vkDestroySurfaceKHR"
            "vkGetPhysicalDeviceSurfaceCapabilitiesKHR"
            "vkGetPhysicalDeviceSurfaceFormatsKHR"
            "vkGetPhysicalDeviceSurfacePresentModesKHR"
            "vkCreateSwapchainKHR"
            "vkGetSwapchainImagesKHR"
        )

        log_info "${SEARCH_MARK} Verifying required KHR extensions for LCEVC inside library..."
        local found_count=0

        for func in "${LCEVC_CHECK_LIST[@]}"; do
            # Ищем символ указателя или функции через кросс-компиляторный nm
            if ${FFBUILD_CROSS_PREFIX}nm "$TARGET_LIB" | grep -q "ptr_${func}"; then
                log_debug "  ${CHECK_MARK} Found: ${func}"
                ((found_count++))
            else
                log_warn "  Missing required function symbol: ${func}"
            fi
        done

        # Выводим красивый финальный статус сборки патча
        if [[ $found_count -eq ${#LCEVC_CHECK_LIST[@]} ]]; then
            log_info "${SYNC_MARK} Vulkan-Shim patch verification: SUCCESS (${found_count}/${#LCEVC_CHECK_LIST[@]} extensions active)."
        else
            log_warn "Vulkan-Shim patch verification: PARTIAL ($found_count/${#LCEVC_CHECK_LIST[@]} found). Final linking might fail!"
        fi

        # Если включен глубокий дебаг, вываливаем весь список символов 'vk'
        if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
            log_debug "${LOGS_MARK} Detailed library symbols dumping:"
            ${FFBUILD_CROSS_PREFIX}nm "$TARGET_LIB" | grep -i "ptr_vk" || true
        fi
    else
        log_error "Failed to verify library: libvulkan-1.a not found at ${TARGET_LIB}"
        return 1
    fi
fi
}

ffbuild_configure() {
    echo --enable-vulkan
}

ffbuild_unconfigure() {
    echo --disable-vulkan
}
