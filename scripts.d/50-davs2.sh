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
    # echo "git fetch --unshallow"
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/davs2" ]]; then
        for patch in "/builder/patches/davs2"/*.patch; do
            log_info "APPLYING PATCH: $patch"
            if patch -p1 -N -r - < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                # return 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    cd build/linux

    # Фикс проверки endianness для современных GCC (уже было у вас, оставляем)
    sed -i -e 's/EGIB/bss/g' -e 's/naidnePF/bss/g' configure

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-cli
        --bit-depth=10
        --enable-pic
        --host="$FFBUILD_TOOLCHAIN"
        --cross-prefix="$FFBUILD_CROSS_PREFIX"
    )

    # Добавляем LTO если включено в workflow
    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    ./configure "${myconf[@]}" \
        EXTRA_CFLAGS="$CFLAGS" \
        EXTRA_LDFLAGS="$LDFLAGS" || { tail -n 100 config.log; exit 1; }

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем pkg-config для статической линковки
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/davs2.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Гарантируем, что префикс внутри .pc корректный
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        # Для статики иногда нужен -lpthread
        if ! grep -q "Libs.private" "$PC_FILE"; then
            echo "Libs.private: -lpthread" >> "$PC_FILE"
        fi
    fi
}

ffbuild_configure() {
    echo --enable-libdavs2
}

ffbuild_unconfigure() {
    echo --disable-libdavs2
}
