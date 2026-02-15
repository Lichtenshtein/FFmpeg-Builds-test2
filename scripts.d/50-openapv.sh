#!/bin/bash

SCRIPT_REPO="https://github.com/AcademySoftwareFoundation/openapv.git"
SCRIPT_COMMIT="192317a0c848ba6797ef196dad3da3338a0d474f"

ffbuild_enabled() {
    (( $(ffbuild_ffver) > 701 )) || return -1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git fetch --unshallow --filter=blob:none"
}

ffbuild_dockerbuild() {
    # Очищаем CMakeLists для приложений, чтобы не собирать лишний мусор
    echo > app/CMakeLists.txt

    mkdir build && cd build

    cmake -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DOAPV_APP_STATIC_BUILD=ON \
        -DENABLE_TESTS=OFF ..

    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    # Безопасное перемещение библиотеки
    if [[ -f "$FFBUILD_DESTPREFIX/lib/oapv/liboapv.a" ]]; then
        mv "$FFBUILD_DESTPREFIX/lib/oapv/liboapv.a" "$FFBUILD_DESTPREFIX/lib/liboapv.a"
    fi
    
    # Очистка динамических библиотек и мусора
    rm -rf "$FFBUILD_DESTPREFIX"/{bin,lib/oapv,lib/liboapv.so*}

    # Фикс pkg-config для статической линковки
    if [[ -f "$FFBUILD_DESTPREFIX/lib/pkgconfig/oapv.pc" ]]; then
        sed -i 's/Libs: /Libs.private: -lm\nLibs: /' "$FFBUILD_DESTPREFIX/lib/pkgconfig/oapv.pc"
        echo "Cflags.private: -DOAPV_STATIC_DEFINE" >> "$FFBUILD_DESTPREFIX/lib/pkgconfig/oapv.pc"
    fi
}

ffbuild_configure() {
    echo --enable-liboapv
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 701 )) || return 0
    echo --disable-liboapv
}
