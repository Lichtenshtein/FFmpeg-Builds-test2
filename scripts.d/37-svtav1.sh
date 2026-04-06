#!/bin/bash

# SCRIPT_REPO="https://gitlab.com/AOMediaCodec/SVT-AV1.git"
# SCRIPT_COMMIT="b7328c60c417ede0d3673119eeee305cce82c215"

# SCRIPT_REPO2="https://github.com/juliobbv-p/svt-av1-hdr.git"
# SCRIPT_COMMIT2="16b4c9449883298c87dde012a76e64ec0d8c78da"

SCRIPT_REPO3="https://github.com/Uranite/svt-av1-tritium.git"
SCRIPT_COMMIT3="640901fe04c735099bd4318064f747e8a36e2003"

# SCRIPT_REPO4="https://github.com/BlueSwordM/svt-av1-hdr.git"
# SCRIPT_COMMIT4="f6e65133f2317b996a95f413e964289300d6dbfd"

# SCRIPT_REPO5="https://github.com/Khaoklong51/SVT-AV1-Essential.git"
# SCRIPT_COMMIT5="56b82f6df10809165f29d982b705bf40bce1c880"
# SCRIPT_BRANCH5="ffms2_v3_PSYfeat2"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # ФИКС ВЕРСИИ (SVT-AV1 специфичный)
    # Если нет .git, CMakeLists.txt не сможет определить версию. 
    # Запишем её принудительно в файл, который ожидает система сборки (если он есть)
    # или через параметры CMake.
    local SVT_VER="4.0.1-tritium"

    mkdir build && cd build

    local myconf=(
        -G "Unix Makefiles"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DVERSION="$SVT_VER" # Исправляем проблему с пустой версией в pkg-config
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTING=OFF
        -DBUILD_APPS=OFF
        -DSVT_AV1_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DENABLE_AVX512=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF )
        -DENABLE_NASM=ON
        -DNATIVE=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS $([ "${USE_LTO}" == "1" ] && echo -ffat-lto-objects )" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS $([ "${USE_LTO}" == "1" ] && echo -ffat-lto-objects )" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # SVT-AV1 иногда генерирует SvtAv1Enc.pc вместо svtav1.pc
    cd "$PC_DIR"
    if [[ -f "SvtAv1Enc.pc" ]]; then
        cp SvtAv1Enc.pc svtav1.pc
        sed -i "s|Libs: -L\${libdir} -lSvtAv1Enc|Libs: -L\${libdir} -lSvtAv1Enc|" svtav1.pc
    fi
}

ffbuild_configure() {
    echo --enable-libsvtav1
}

ffbuild_unconfigure() {
    echo --disable-libsvtav1
}
