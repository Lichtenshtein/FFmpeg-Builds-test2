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
        -DZSTD_MULTITHREAD_SUPPORT=ON
        -DZSTD_LEGACY_SUPPORT=ON
        # Принудительно включаем CXX на уровне языков проекта
        -DCMAKE_CXX_COMPILER="$CXX"
    )

    # Добавляем LTO если включено в workflow
    if [[ "$USE_LTO" == "1" ]]; then
        myconf+=( -DZSTD_USE_LTO=ON )
    fi

    # Добавляем -DCMAKE_CXX_COMPILER, чтобы CMake инициализировал CXX
    # и не падал на проверке флагов AddZstdCompilationFlags
    # Если CMake все еще сопротивляется, добавим явную инициализацию языков
    cmake "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        .. || {
            log_warn "Standard CMake failed, trying with forced languages..."
            # Альтернативный подход: передаем языки через командную строку
            cmake "${myconf[@]}" -DLANGUAGES="C;CXX" ..
        }

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем pkg-config для Windows (добавляем pthread, если включен multithreading)
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libzstd.pc"
    if [[ -f "$PC_FILE" ]]; then
        # В MinGW для мультипоточности нужен pthread
        sed -i 's/Libs.private:/& -lpthread /' "$PC_FILE"
    fi
}

ffbuild_configure() {
    # zstd может быть включен в ffmpeg напрямую (для некоторых протоколов)
    echo --enable-zstd
}

ffbuild_unconfigure() {
    echo --disable-zstd
}
