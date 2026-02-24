#!/bin/bash

SCRIPT_REPO="https://github.com/cynagenautes/AudioToolboxWrapper.git"
SCRIPT_COMMIT="191aa1bf840e093cad48a5d34c961086641bacbd"
# Ссылка на бинарные файлы Apple (CoreAudio)
QTFILES_URL="https://github.com/AnimMouse/QTFiles/releases/download/v12.13.9.1/QTfiles64.7z"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
    echo "download_file \"$QTFILES_URL\" \"qtfiles64.7z\""
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" .. -G Ninja
    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install
    cd ..

    # Обработка бинарных DLL Apple
    log_info "Extracting Apple CoreAudio DLLs..."
    # Распаковываем
    7z x qtfiles64.7z -o"apple_dlls"

    # Создаем папку bin в префиксе назначения, если её нет
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin"

    # Копируем все DLL из папки QTfiles64 напрямую в bin префикса
    # Согласно инструкции, они должны лежать рядом с ffmpeg.exe
    cp -v apple_dlls/QTfiles64/*.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"

    # Удаляем ldwrapper, так как он нужен только для сборки самого враппера
    rm -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/atw_ldwrapper"
}

ffbuild_configure() {
    echo --enable-audiotoolbox
}

ffbuild_unconfigure() {
    echo --disable-audiotoolbox
}

ffbuild_libs() {
    echo -lAudioToolboxWrapper
}
