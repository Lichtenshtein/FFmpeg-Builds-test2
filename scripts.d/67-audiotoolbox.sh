#!/bin/bash

SCRIPT_REPO="https://github.com/cynagenautes/AudioToolboxWrapper.git"
SCRIPT_COMMIT="191aa1bf840e093cad48a5d34c961086641bacbd"

# Ссылка на бинарные файлы Apple (CoreAudio)
QTFILES_URL="https://github.com/AnimMouse/QTFiles/releases/download/v12.13.9.1/QTfiles64.7z"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    # echo "git clean -fdx"
    echo "download_file \"$QTFILES_URL\" \"qtfiles64.7z\""
}

ffbuild_dockerbuild() {
    set -e

    # Поднимаем минимальную версию CMake до 3.5, чтобы не злить современный бинарник
    sed -i 's/cmake_minimum_required (VERSION 3.0)/cmake_minimum_required (VERSION 3.5)/' CMakeLists.txt

    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo 1 || echo 0)
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/AudioToolboxWrapper.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: AudioToolboxWrapper
Description: AudioToolbox wrapper for MinGW
Version: 1.0
Libs: -L\${libdir} -lAudioToolboxWrapper
Cflags: -I\${includedir} -I\${includedir}/AudioToolbox
EOF

    cd ..

    # Обработка бинарных DLL Apple
    log_info "Extracting Apple CoreAudio DLLs..."
    # Распаковываем
    7z x qtfiles64.7z -o"apple_dlls"

    # Создаем папку bin в префиксе назначения, если её нет
    mkdir -p "$INSTALL_ROOT/bin"

    # Копируем все DLL из папки QTfiles64 напрямую в bin префикса
    # Согласно инструкции, они должны лежать рядом с ffmpeg.exe
    cp -v apple_dlls/QTfiles64/*.dll "$INSTALL_ROOT/bin/"

    # Удаляем ldwrapper, так как он нужен только для сборки самого враппера
    rm -f "$INSTALL_ROOT/bin/atw_ldwrapper"
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
