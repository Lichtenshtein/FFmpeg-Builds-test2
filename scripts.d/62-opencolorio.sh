#!/bin/bash

SCRIPT_REPO="https://github.com/AcademySoftwareFoundation/OpenColorIO.git"
SCRIPT_COMMIT="f660cee6127011fdb03e0d227572901631435d3c"

ffbuild_depends() {
    echo zlib
    echo lcms2
    echo vulkan-loader
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
    else
        log_warn "Could not find Installyaml-cpp.cmake dynamically. Attempting direct sed on Installyaml-cpp.cmake"
        if [[ -f "$YAML_CPP_FILE" ]]; then
            sed -i 's/set(yaml-cpp_GIT_TAG .*/set(yaml-cpp_GIT_TAG "2decf96e915d2b0c26c68c1659665789dfef2633")/g' "$YAML_CPP_FILE"

             log_info "Injecting -include cstdint directly into yaml-cpp compile flags..."

             sed -i '/string(STRIP "${yaml-cpp_CXX_FLAGS}"/i \        set(yaml-cpp_CXX_FLAGS "${yaml-cpp_CXX_FLAGS} -include cstdint")' "$YAML_CPP_FILE"
         else
             log_warn "Target template file $YAML_CPP_FILE not found for flag injection!"
         fi
    fi

    local FILE_TRANSFORM_SRC="src/OpenColorIO/transforms/FileTransform.cpp"
    if [[ -f "$FILE_TRANSFORM_SRC" ]]; then
        log_info "Patching FileTransform.cpp for MinGW GCC 15 std::wstring compatibility..."

        sed -i 's/Platform::filenameToUTF(filepath)/Platform::filenameToUTF(filepath).c_str()/g' "$FILE_TRANSFORM_SRC"
    else
        log_warn "Could not find $FILE_TRANSFORM_SRC to apply the c_str() patch!"
    fi

    mkdir build && cd build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
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
        # Отключаем утилиты, тесты, документацию и биндинги
        -DOCIO_BUILD_APPS=OFF
        -DOCIO_BUILD_OPENFX=ON # OpenFX plugins
        -DOCIO_BUILD_NUKE=OFF # nuke plugins
        -DOCIO_BUILD_TESTS=OFF
        -DOCIO_BUILD_GPU_TESTS=OFF
        -DOCIO_BUILD_DOCS=OFF
        -DOCIO_BUILD_PYTHON=OFF
        -DOCIO_BUILD_JAVA=OFF
        -DOCIO_WARNING_AS_ERROR=OFF
        # Аппаратное ускорение графики
        -DOCIO_VULKAN_ENABLED=OFF
        # Интеграция с ZLIB
        -DZLIB_LIBRARY="${FFBUILD_PREFIX}/lib/libz.a"
        -DZLIB_INCLUDE_DIR="${FFBUILD_PREFIX}/include"
        # Интеграция с Little-CMS (lcms2)
        -Dlcms2_LIBRARY="${FFBUILD_PREFIX}/lib/liblcms2.a"
        -Dlcms2_INCLUDE_DIR="${FFBUILD_PREFIX}/include"
    )

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        myconf+=(
            -DBUILD_SHARED_LIBS=OFF
            -DZLIB_USE_STATIC_LIBS=ON
            -Dlcms2_STATIC_LIBRARY=ON
        )
    else
        myconf+=(
            -DBUILD_SHARED_LIBS=ON
            -DOCIO_USE_SOVERSION=ON
            -DZLIB_USE_STATIC_LIBS=OFF
            -Dlcms2_STATIC_LIBRARY=OFF
        )
    fi

    if [[ $TARGET == win64 ]]; then
        myconf+=(
            -DOCIO_USE_WINDOWS_UNICODE=ON
            -DOCIO_DIRECTX_ENABLED=ON # Включаем DX12 рендеринг для Windows
        )
    elif [[ $TARGET == linux64 ]]; then
        myconf+=(
            -DOCIO_DIRECTX_ENABLED=OFF
        )
    fi

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # local PC_FILE="$PC_DIR/OpenColorIO.pc"
    # if [[ -f "$PC_FILE" ]]; then
        # log_info "Fixing and auditing OpenColorIO.pc for static build..."
        # sed -i '/^Cflags:/ s/[[:space:]]*-pthread//g' "$PC_FILE"
        # if grep -q "Libs.private:" "$PC_FILE"; then
            # sed -i '/^Libs.private:/ s/$/ -llcms2_fast_float -llcms2_threaded -lz -lvulkan-1 -lws2_32 -lshlwapi -lgnustl_static/' "$PC_FILE"
        # else
            # echo "Libs.private: -llcms2_fast_float -llcms2_threaded -lz -lvulkan-1 -lws2_32 -lshlwapi -lgnustl_static" >> "$PC_FILE"
        # fi
        # sed -i 's/[[:space:]]\+/ /g' "$PC_FILE"
    # fi

    find /build/62-opencolorio -type f -name "*.a" -printf "%p (%s bytes)\n"
}

ffbuild_configure() {
    echo --enable-libopencolorio
}

ffbuild_unconfigure() {
    echo --disable-libopencolorio
}
