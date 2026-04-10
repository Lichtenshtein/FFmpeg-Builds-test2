#!/bin/bash

SCRIPT_REPO="https://github.com/cynagenautes/AudioToolboxWrapper.git"
SCRIPT_COMMIT="191aa1bf840e093cad48a5d34c961086641bacbd"
# Ссылка на бинарные файлы Apple (CoreAudio)
# QTFILES_URL="https://github.com/AnimMouse/QTFiles/releases/download/v12.13.9.1/QTfiles64.7z"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    # echo "git clean -fdx"
    # echo "download_file \"$QTFILES_URL\" \"qtfiles64.7z\""
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo 1 || echo 0)
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # cd ..

    # Обработка бинарных DLL Apple
    # log_info "Extracting Apple CoreAudio DLLs..."
    # Распаковываем
    # 7z x qtfiles64.7z -o"apple_dlls"

    # Создаем папку bin в префиксе назначения, если её нет
    # mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin"

    # Копируем все DLL из папки QTfiles64 напрямую в bin префикса
    # Согласно инструкции, они должны лежать рядом с ffmpeg.exe
    # cp -v apple_dlls/QTfiles64/*.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"

    # Удаляем ldwrapper, так как он нужен только для сборки самого враппера
    # rm -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/atw_ldwrapper"
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
