#!/bin/bash

SCRIPT_REPO="https://bitbucket.org/multicoreware/x265_git.git"
SCRIPT_COMMIT="e444744c03978c1fb4e037168967020cf2648427"

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
    # Определяем реальный корень исходников (там, где папка 'source')
    if [[ -d "source" ]]; then
        X265_ROOT="$PWD/source"
    elif [[ -f "CMakeLists.txt" && "$PWD" == *"/source" ]]; then
        X265_ROOT="$PWD"
        cd ..
    else
        log_error "Could not find x265 source directory"
        return 1
    fi

    # Проверяем, почему пропал .git (для логов отладки)
    if [[ ! -d ".git" ]]; then
        log_warn "DEBUG: .git directory is MISSING in $(pwd). Preservation failed?"
        # Если .git нет, создаем файл версии, чтобы CMake не падал
        echo "3.5" > "$X265_ROOT/x265_version.txt"
    else
        log_info "DEBUG: .git directory found. Version should be detected automatically."
    fi

    # Полностью вырезаем блок определения версии в CMakeLists.txt, 
    # который вызывает ошибку "list GET", если нет .git
    sed -i '/if(X265_LATEST_TAG)/,/endif(X265_LATEST_TAG)/d' "$X265_ROOT/CMakeLists.txt"
    sed -i 's/list(GET /#list(GET /g' "$X265_ROOT/CMakeLists.txt"

    # Фикс заголовка json11
    find "$X265_ROOT" -name "json11.cpp" -exec sed -i '1i#include <cstdint>' {} +

    local myconf=(
        -G Ninja
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_ASM_NASM_FLAGS=-w-macro-params-legacy
        -DENABLE_ALPHA=ON
        -DENABLE_ASSEMBLY=ON
        -DENABLE_CLI=OFF
        -DENABLE_PIC=ON
        -DENABLE_SHARED=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF) # Для multilib статика обязательна
        -DNATIVE_BUILD=OFF # Target the build CPU
        -DENABLE_LIBVMAF=ON
        -DENABLE_SCC_EXT=ON # Enable screen content coding extension in HEVC
        -DENABLE_MULTIVIEW=ON # Enable Multi-view encoding in HEVC
        -DENABLE_VTUNE=OFF # Enable Vtune profiling instrumentation
        -DENABLE_TESTS=OFF # Enable Unit Tests
        -DX265_LATEST_TAG="3.5"
        -DX265_TAG_DISTANCE="0"
        -DX265_VERSION="3.5"
        -Wno-dev
        # SVT_HEVC
        -DENABLE_SVT_HEVC=ON # use the --svt flag in the x265 CLI to use the SVT-HEVC engine instead of the standard x265 core
        -DSVT_HEVC_INCLUDE_DIR="$FFBUILD_PREFIX/include/svt-hevc"
        -DSVT_HEVC_LIBRARY="$FFBUILD_PREFIX/lib/libSvtHevcEnc.a"
        )

    mkdir -p 8bit 10bit 12bit

    if [[ $TARGET != *32 ]]; then
        log_info "Building 12-bit x265..."
        CFLAGS="$CFLAGS $CPPFLAGS" \
        CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
        LDFLAGS="$LDFLAGS" \
        cmake "${myconf[@]}" -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_HDR10_PLUS=ON -DMAIN12=ON -S "$X265_ROOT" -B 12bit || return 1
        ninja -C 12bit -j$(nproc) $NINJA_V || return 1

        log_info "Building 10-bit x265..."
        CFLAGS="$CFLAGS $CPPFLAGS" \
        CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
        LDFLAGS="$LDFLAGS" \
        cmake "${myconf[@]}" -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_HDR10_PLUS=ON -S "$X265_ROOT" -B 10bit || return 1
        ninja -C 10bit -j$(nproc) $NINJA_V || return 1

        log_info "Building 8-bit x265 (combined)..."
        # Копируем либы для финальной линковки
        cp 12bit/libx265.a 8bit/libx265_main12.a
        cp 10bit/libx265.a 8bit/libx265_main10.a

        CFLAGS="$CFLAGS $CPPFLAGS" \
        CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
        LDFLAGS="$LDFLAGS" \
        cmake "${myconf[@]}" \
            -DEXTRA_LIB="${PWD}/10bit/libx265.a;${PWD}/12bit/libx265.a" \
            -DLINKED_10BIT=ON -DLINKED_12BIT=ON \
            -S "$X265_ROOT" -B 8bit || return 1
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
        CFLAGS="$CFLAGS $CPPFLAGS" \
        CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
        LDFLAGS="$LDFLAGS" \
        cmake "${myconf[@]}" -S "$X265_ROOT" -B 8bit || return 1
        ninja -C 8bit -j$(nproc) $NINJA_V || return 1
    fi

    # Установка из папки 8bit (которая содержит объединенную либу)
    DESTDIR="$FFBUILD_DESTDIR" ninja -C 8bit install || return 1

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/x265.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: x265
Description: H.265/HEVC video encoder
Version: 4.2
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
