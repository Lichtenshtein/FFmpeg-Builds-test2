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
    if [[ -d "/builder/patches/svtav1" ]]; then
        for patch in /builder/patches/svtav1/*.patch; do
            log_info "APPLYING PATCH: $patch"
            if patch -p1 -N -r - < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                # return 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    # ФИКС ВЕРСИИ (SVT-AV1 специфичный)
    # Если нет .git, CMakeLists.txt не сможет определить версию. 
    # Запишем её принудительно в файл, который ожидает система сборки (если он есть)
    # или через параметры CMake.
    local SVT_VER="2.1.0-tritium"

    mkdir build && cd build

    local myconf=(
        -G "Unix Makefiles"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_C_FLAGS="$CFLAGS"
        -DCMAKE_CXX_FLAGS="$CXXFLAGS"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTING=OFF
        # -DBUILD_DEC=OFF
        # -DBUILD_ENC=ON
        -DBUILD_APPS=OFF 
        -DENABLE_AVX512=OFF
        -DENABLE_NASM=ON
    )
    # Исправляем проблему с пустой версией в pkg-config
    myconf+=( -DVERSION="$SVT_VER" )

    # Добавляем LTO если включено
    if [[ "$USE_LTO" == "1" ]]; then
        myconf+=( -DSVT_AV1_LTO=ON )
    else
        myconf+=( -DSVT_AV1_LTO=OFF )
    fi

    cmake "${myconf[@]}" ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # ФИКС pkg-config
    # SVT-AV1 иногда генерирует SvtAv1Enc.pc вместо svtav1.pc
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/SvtAv1Enc.pc"
    if [[ -f "$PC_FILE" ]]; then
        # FFmpeg ищет "SvtAv1Enc" (в новых версиях) или "svtav1"
        # Сделаем копию для совместимости
        cp "$PC_FILE" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/svtav1.pc"
        
        # Добавляем системные либы для статической линковки
        echo "Libs.private: -lstdc++ -lm" >> "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/svtav1.pc"
        echo "Libs.private: -lstdc++ -lm" >> "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libsvtav1
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) >= 404 )) || return 0
    echo --disable-libsvtav1
}
