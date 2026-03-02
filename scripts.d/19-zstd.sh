#!/bin/bash

SCRIPT_REPO="https://github.com/facebook/zstd.git"
SCRIPT_COMMIT="1168da0e567960d50cba1b58c9b0ba047ece4733"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    # Исправляем CMakeLists.txt ПЕРЕД запуском, чтобы избежать ошибки CXX
    # Добавляем CXX в список языков проекта
    sed -i '/LANGUAGES C/s/C/C CXX/' build/cmake/CMakeLists.txt

    # zstd требует запуска CMake из поддиректории build/cmake
    cd build/cmake
    rm -rf builddir && mkdir builddir && cd builddir

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DZSTD_BUILD_STATIC=ON
        -DZSTD_BUILD_SHARED=OFF
        -DZSTD_BUILD_PROGRAMS=OFF
        -DZSTD_BUILD_TESTS=OFF
        -DZSTD_BUILD_CONTRIB=OFF
        # Принудительно включаем CXX на уровне языков проекта
        -DCMAKE_CXX_COMPILER="$CXX"
        # Включаем многопоточность (важно для FFmpeg)
        -DZSTD_MULTITHREAD_SUPPORT=ON
        # Включаем поддержку старых форматов для совместимости
        -DZSTD_LEGACY_SUPPORT=ON
        # Оптимизация под современные CPU (Xeon Broadwell поддерживает BMI2)
        -DZSTD_SPECIAL_TARGET=OFF
    )

    # Добавляем LTO если включено в workflow
    if [[ "$USE_LTO" == "1" ]]; then
        myconf+=( -DZSTD_USE_LTO=ON )
    fi

    # Добавляем -DCMAKE_CXX_COMPILER, чтобы CMake инициализировал CXX
    # и не падал на проверке флагов AddZstdCompilationFlags
    # Принудительно передаем CXX компилятор
    cmake "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS -DZSTD_MULTITHREAD -DZSTD_STATIC_LINKING" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_CXX_COMPILER="$CXX" \
        ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # --- КОРРЕКЦИЯ PKG-CONFIG (Согласно Readme для MT=1) ---
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libzstd.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "Applying multithreaded flags to libzstd.pc"
        # Для статической линковки в MinGW обязательно нужен -lpthread
        if ! grep -q "\-lpthread" "$PC_FILE"; then
            sed -i 's/Libs.private:/& -lpthread /' "$PC_FILE"
        fi
        # Добавляем макрос многопоточности в флаги компиляции
        if ! grep -q "\-DZSTD_MULTITHREAD" "$PC_FILE"; then
            sed -i 's/Cflags:/& -DZSTD_MULTITHREAD /' "$PC_FILE"
        fi
    fi
}

ffbuild_cppflags() {
    echo "-DZSTD_STATIC_LINKING"
}

ffbuild_configure() {
    # zstd может быть включен в ffmpeg напрямую (для некоторых протоколов)
    echo --enable-zstd
}

ffbuild_unconfigure() {
    echo --disable-zstd
}
