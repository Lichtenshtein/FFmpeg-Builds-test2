#!/bin/bash

SCRIPT_REPO="https://github.com/AcademySoftwareFoundation/openapv.git"
SCRIPT_COMMIT="3e87fa5101c3fe4038035b562cf552755fcf2060"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    # echo "git fetch --unshallow --filter=blob:none"
}

ffbuild_dockerbuild() {
    set -e
    # Очищаем CMakeLists для приложений, чтобы не собирать лишний мусор
    echo > app/CMakeLists.txt

    mkdir build && cd build

    CFLAGS="$CFLAGS $CPPFLAGS -DOAPV_STATIC_DEFINE" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -DOAPV_STATIC_DEFINE" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DOAPV_APP_STATIC_BUILD=ON \
        -DENABLE_TESTS=OFF .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Безопасное перемещение библиотеки
    if [[ -f "$FFBUILD_DESTPREFIX/lib/oapv/liboapv.a" ]]; then
        mv "$FFBUILD_DESTPREFIX/lib/oapv/liboapv.a" "$FFBUILD_DESTPREFIX/lib/liboapv.a"
    fi
    
    # Очистка динамических библиотек и мусора
    rm -rf "$FFBUILD_DESTPREFIX"/{bin,lib/oapv,lib/liboapv.so*}

    # Фикс pkg-config для статической линковки
    if [[ -f "$PC_DIR/oapv.pc" ]]; then
        sed -i 's/Libs: /Libs.private: -lm\nLibs: /' "$PC_DIR/oapv.pc"
        echo "Cflags: -DOAPV_STATIC_DEFINE" >> "$PC_DIR/oapv.pc"
    fi

}

ffbuild_cflags() {
    echo "-DOAPV_STATIC_DEFINE"
}

ffbuild_configure() {
    echo --enable-liboapv
}

ffbuild_unconfigure() {
    echo --disable-liboapv
}
