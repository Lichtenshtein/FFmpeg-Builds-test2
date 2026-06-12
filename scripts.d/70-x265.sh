#!/bin/bash
export USE_VERS_FINDER=1
SCRIPT_REPO="https://github.com/Multicorewareinc/x265.git"
SCRIPT_COMMIT="6fdfffe8d3afe028c24ab8712ce07c90432934cf"

ffbuild_depends() {
    echo svthevc
    echo vmaf
}

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    log_info "Patching x265 to match VMAF Pointer ABI..."
    # Ищем файлы, где встречается vmaf_init, и точечно правим вызов на передачу адреса &cfg
    find . -type f \( -name "encoder.cpp" -o -name "api.cpp" -o -name "*vmaf*" \) -exec sed -i 's/vmaf_init(\&vmafContext, cfg)/vmaf_init(\&vmafContext, \&cfg)/g' {} + || true
    find . -type f \( -name "encoder.cpp" -o -name "api.cpp" -o -name "*vmaf*" \) -exec sed -i 's/vmaf_init(vmaf_context, cfg)/vmaf_init(vmaf_context, \&cfg)/g' {} + || true

    if [[ ! -d "/build/${STAGENAME}/.git" ]]; then
        log_debug ".git directory is MISSING in $(pwd)."
        # Если .git нет, создаем файл версии, чтобы CMake не падал
        echo "${VER_FULL}" > "x265_version.txt"
    else
        log_debug ".git directory found. Version should be detected automatically."
    fi

    # Полностью вырезаем блок определения версии в CMakeLists.txt, 
    # который вызывает ошибку "list GET"
    sed -i '/if(X265_LATEST_TAG)/,/endif(X265_LATEST_TAG)/d' "CMakeLists.txt"
    sed -i 's/list(GET /#list(GET /g' "CMakeLists.txt"

    # Фикс заголовка json11
    find . -name "json11.cpp" -exec sed -i '1i#include <cstdint>' {} +

    # Фикс совместимости x265 с SVT-HEVC 1.5.0+ (изменение EB_SEI_MESSAGE)
    # Заменяем аллокацию на memcpy (так как payload теперь массив)
    sed -i 's/inputData->dolbyVisionRpu.payload = X265_MALLOC(uint8_t, 1024);/memset(inputData->dolbyVisionRpu.payload, 0, 1024);/g' "encoder/api.cpp"

    # Убираем попытки обнуления указателя (статический массив нельзя занулить)
    sed -i 's/inputData->dolbyVisionRpu.payload = NULL;//g' "encoder/api.cpp"

    # Убираем X265_FREE, так как массив не нужно освобождать
    sed -i 's/if (inputData->dolbyVisionRpu.payload) X265_FREE(inputData->dolbyVisionRpu.payload);//g' "encoder/api.cpp"

    # Исправление потенциального крэша в парсинге параметров SVT-HEVC
    # sed -i 's/else { if (!strcmp(temp1, "\*"))/else { temp1 = pools; if (!strcmp(temp1, "\*"))/' "common/param.cpp"

    # Дополнительно исправляем варнинг сравнения типов в threading.h (Win64)
    sed -i 's/rt != WAIT_TIMEOUT \&\& rt != WAIT_FAILED/rt != (DWORD)WAIT_TIMEOUT \&\& rt != (DWORD)WAIT_FAILED/g' "common/threading.h"
    sed -i 's/int32_t rt = WaitForSingleObject/DWORD rt = WaitForSingleObject/g' "common/threading.h"

    local myconf=(
        -G Ninja
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_ASM_NASM_FLAGS=-w-macro-params-legacy
        -DENABLE_ALPHA=ON
        -DENABLE_ASSEMBLY=ON
        -DENABLE_CLI=OFF
        -DENABLE_PIC=ON
        -DENABLE_SHARED=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DNATIVE_BUILD=OFF # Target the build CPU
        -DENABLE_LIBVMAF=ON
        -DENABLE_SCC_EXT=ON # Enable screen content coding extension in HEVC
        -DENABLE_MULTIVIEW=ON # Enable Multi-view encoding in HEVC
        -DENABLE_VTUNE=OFF # Enable Vtune profiling instrumentation
        -DENABLE_TESTS=OFF # Enable Unit Tests
        -Wno-dev
        # SVT_HEVC; see svthevc.rst file
        -DENABLE_SVT_HEVC=ON # use the --svt flag in the x265 CLI to use the SVT-HEVC engine instead of the standard x265 core
        -DSVT_HEVC_INCLUDE_DIR="$FFBUILD_PREFIX/include/svt-hevc"
        -DSVT_HEVC_LIBRARY="$FFBUILD_PREFIX/lib/libSvtHevcEnc.a"
        )

    mkdir -p 8bit 10bit 12bit

    if [[ $TARGET != *32 ]]; then
        log_info "Building 12-bit x265..."
        CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        LDFLAGS="$LDFLAGS ${USELTO}" \
        cmake "${myconf[@]}" -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_HDR10_PLUS=ON -DMAIN12=ON -S . -B 12bit || return 1
        ninja -C 12bit -j$(nproc) $NINJA_V || return 1

        log_info "Building 10-bit x265..."
        CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        LDFLAGS="$LDFLAGS ${USELTO}" \
        cmake "${myconf[@]}" -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_HDR10_PLUS=ON -S . -B 10bit || return 1
        ninja -C 10bit -j$(nproc) $NINJA_V || return 1

        log_info "Building 8-bit x265 (combined)..."
        # Копируем либы для финальной линковки
        cp 12bit/libx265.a 8bit/libx265_main12.a
        cp 10bit/libx265.a 8bit/libx265_main10.a

        CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        LDFLAGS="$LDFLAGS ${USELTO}" \
        cmake "${myconf[@]}" \
            -DEXTRA_LIB="${PWD}/10bit/libx265.a;${PWD}/12bit/libx265.a" \
            -DLINKED_10BIT=ON -DLINKED_12BIT=ON \
            -S . -B 8bit || return 1
        ninja -C 8bit -j$(nproc) $NINJA_V || return 1

        # Объединяем библиотеки через MRI скрипт для ar
        # используем кросс-архивный AR
        cd 8bit
        mv libx265.a libx265_8bit.a
        ${AR} -M <<EOF
CREATE libx265.a
ADDLIB libx265_8bit.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF
        # Возвращаемся в корень билда
        cd ..
    else
        log_info "Building 8-bit x265 (32-bit target)..."
        CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        LDFLAGS="$LDFLAGS ${USELTO}" \
        cmake "${myconf[@]}" -S . -B 8bit || return 1
        ninja -C 8bit -j$(nproc) $NINJA_V || return 1
    fi

    # Установка из папки 8bit (которая содержит объединенную либу)
    DESTDIR="$FFBUILD_DESTDIR" ninja -C 8bit install || return 1

    # I guess this is just a copy
    if [[ "${myconf[@]}" =~ "-DENABLE_SVT_HEVC=ON" ]]; then
        if [[ -f "${INSTALL_ROOT}/lib/libSvtHevcEnc.a" ]]; then
            rm -f "${INSTALL_ROOT}/lib/libSvtHevcEnc.a"
        fi
    fi

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/x265.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: x265
Description: H.265/HEVC video encoder
Version: ${VER_FULL}
Libs: -L\${libdir} -lx265
Libs.private: -lstdc++ -lm -lgcc -lmingwex -lmingw32 -luser32 -ladvapi32 -lshell32
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-libx265
}

ffbuild_unconfigure() {
    echo --disable-libx265
}
