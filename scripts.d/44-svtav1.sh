#!/bin/bash

# SCRIPT_REPO="https://gitlab.com/AOMediaCodec/SVT-AV1.git"
# SCRIPT_COMMIT="b7328c60c417ede0d3673119eeee305cce82c215"

# SCRIPT_REPO2="https://github.com/juliobbv-p/svt-av1-hdr.git"
# SCRIPT_COMMIT2="16b4c9449883298c87dde012a76e64ec0d8c78da"

SCRIPT_REPO3="https://github.com/Uranite/svt-av1-tritium.git"
SCRIPT_COMMIT3="8ee7ff4f017a8a136535308910a8484bcb187d4f"

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

    rm -rf _build && mkdir _build && cd _build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DVERSION_TAG="$SVT_VER"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_TESTING=OFF
        -DBUILD_APPS=OFF
        -DENABLE_AVX512=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF)
        -DNATIVE=OFF
    )

    if [[ "$USE_LTO" == "1" ]]; then
        myconf+=( -DSVT_AV1_LTO=OFF ) # something passes -fno-fat-lto-objects
        export CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}"
        export CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}"
        export LDFLAGS="$LDFLAGS ${USELTO}"
    else
        myconf+=( -DSVT_AV1_LTO=OFF )
        export CFLAGS="$CFLAGS $CPPFLAGS"
        export CXXFLAGS="$CXXFLAGS $CPPFLAGS"
        export LDFLAGS="$LDFLAGS"
    fi

    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # SVT-AV1 иногда генерирует SvtAv1Enc.pc вместо svtav1.pc
    mkdir -p "$PC_DIR"
    if [[ -f "$PC_DIR/SvtAv1Enc.pc" ]]; then
        cp  "$PC_DIR/SvtAv1Enc.pc"  "$PC_DIR/svtav1.pc"
    fi
}

ffbuild_configure() {
    echo --enable-libsvtav1
}

ffbuild_unconfigure() {
    echo --disable-libsvtav1
}
