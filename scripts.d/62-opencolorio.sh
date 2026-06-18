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
        -DOCIO_BUILD_NUKE=ON # nuke plugins
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
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -include cstdint" \
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
}

ffbuild_configure() {
    echo --enable-libopencolorio
}

ffbuild_unconfigure() {
    echo --disable-libopencolorio
}
