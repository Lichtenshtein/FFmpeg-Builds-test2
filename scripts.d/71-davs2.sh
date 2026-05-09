#!/bin/bash

SCRIPT_REPO="https://github.com/netony/davs2.git"
SCRIPT_COMMIT="0a9f952f09343156575e75a2d733d95529ba2d8a"

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    [[ $TARGET == win32 ]] && return 1
    # davs2 aarch64 support is broken
    [[ $TARGET == *arm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    export SKIP_POST_STRIP=1

    cd build/linux

    # Фикс проверки endianness для современных GCC (уже было у вас, оставляем)
    sed -i -e 's/EGIB/bss/g' -e 's/naidnePF/bss/g' configure

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-cli
        --bit-depth=10
        --enable-pic
        --enable-strip
        --chroma-format=all
        --host="$FFBUILD_TOOLCHAIN"
        --cross-prefix="$FFBUILD_CROSS_PREFIX"
        # other existing options
        #--system-libdavs2 #use system libdavs2 instead of internal
        #--disable-opencl  # disable OpenCL features
        #--disable-gpl     # disable GPL-only features
        #--disable-thread  # disable multithreaded encoding
        #--disable-win32thread # disable win32threads (windows only)
        #--disable-interlaced  # disable interlaced encoding support
        #--disable-asm         # disable platform-specific assembly optimizations
    )

    if command -v nasm >/dev/null 2>&1; then
        # Если есть nasm, подставляем его явно
        myconf+=( --as=nasm )
    else
        log_warn "NASM not found! Compiling davs2 without ASM optimizations."
        myconf+=( --disable-asm )
    fi

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --enable-shared --disable-static )
    # [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    ./configure "${myconf[@]}" \
        --extra-cflags="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        --extra-ldflags="$LDFLAGS ${USELTO}" || {
            cat config.log
            return 1 }

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Исправляем pkg-config для статической линковки
    local PC_FILE="$PC_DIR/davs2.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Гарантируем, что префикс внутри .pc корректный
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        # Для статики иногда нужен -lpthread
        if ! grep -q "Libs.private" "$PC_FILE"; then
            sed -i '/^Libs.private:/ s/$/ -pthread/' "$PC_FILE"
        fi
    fi
}

ffbuild_configure() {
    echo --enable-libdavs2
}

ffbuild_unconfigure() {
    echo --disable-libdavs2
}
