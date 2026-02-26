#!/bin/bash

SCRIPT_REPO="https://svn.code.sf.net/p/xavs/code/trunk"
SCRIPT_REV="55"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/xavs" ]]; then
        for patch in /builder/patches/xavs/*.patch; do
            log_info "APPLYING PATCH: $patch"
            if patch -p1 -N -r - < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                # return 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    # Исправляем configure, чтобы он не игнорировал внешние CFLAGS (частая беда xavs)
    sed -i 's/CFLAGS="$CFLAGS -Wall/CFLAGS="$CFLAGS -Wall $EXTRA_CFLAGS/' configure

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --enable-pic
        --enable-static
        --disable-shared
    )

    if [[ $TARGET == win* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
            --cross-prefix="$FFBUILD_CROSS_PREFIX"
        )
        # Форсируем использование правильного компилятора через переменные окружения
        export CC="${FFBUILD_CROSS_PREFIX}gcc"
        export AR="${FFBUILD_CROSS_PREFIX}ar"
        export RANLIB="${FFBUILD_CROSS_PREFIX}ranlib"
    fi

    # xavs требует явного указания архитектуры в некоторых случаях
    ./configure "${myconf[@]}" --extra-cflags="$CFLAGS" --extra-ldflags="$LDFLAGS"

    make -j$(nproc) $MAKE_V
    
    # Установка
    make install DESTDIR="$FFBUILD_DESTDIR"

    # xavs часто не создает корректный pkg-config файл или ставит его не туда.
    # Если xavs.pc отсутствует, FFmpeg его не найдет.
    if [[ ! -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/xavs.pc" ]]; then
        log_info "Creating missing xavs.pc manually..."
        mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
        cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/xavs.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: xavs
Description: AVS (Audio Video Standard) encoder library
Version: r$SCRIPT_REV
Libs: -L\${libdir} -lxavs -lm
Cflags: -I\${includedir}
EOF
    fi
}

ffbuild_configure() {
    echo --enable-libxavs
}

ffbuild_unconfigure() {
    echo --disable-libxavs
}
