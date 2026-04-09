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

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DENABLE_TESTS=OFF
        -DOAPV_BUILD_APPS=OFF
        -DENABLE_COVERAGE=OFF
    )

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        myconf+=(
            -DOAPV_BUILD_STATIC_LIB=OFF
            -DOAPV_BUILD_SHARED_LIB=ON
        )
    else
        myconf+=(
            -DOAPV_BUILD_STATIC_LIB=ON
            -DOAPV_BUILD_SHARED_LIB=OFF
            # oapv_app will be statically linked against static oapv library
            #-DOAPV_APP_STATIC_BUILD=ON
        )
    fi

    local static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DOAPV_STATIC_DEFINE"

    CFLAGS="$CFLAGS $CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS $static_flags" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
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
        echo "Cflags: $static_flags" >> "$PC_DIR/oapv.pc"
    fi
}

ffbuild_cflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-liboapv
}

ffbuild_unconfigure() {
    echo --disable-liboapv
}
