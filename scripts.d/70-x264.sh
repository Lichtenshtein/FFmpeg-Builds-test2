#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/x264.git"
SCRIPT_COMMIT="0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee"

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    export SKIP_POST_STRIP=1

    # ФИКС ВЕРСИИ (если нет .git)
    # x264 использует скрипт version.sh. Если он не находит git, 
    # мы создадим файл version.gen вручную.
    if [[ ! -d ".git" ]]; then
        log_info "Creating x264 version metadata manually..."
        # 164 — примерное число коммитов для данного хеша
        echo "#define X264_REV 3108" > x264_config.h
        echo "#define X264_REV_DIFF 0" >> x264_config.h
        echo "#define X264_VERSION \" r3108 0480cb0\"" >> x264_config.h
        echo "#define X264_VER \"164\"" >> x264_config.h
    fi

    local myconf=(
        --disable-cli
        --enable-pic
        --enable-strip
        --disable-lavf
        --disable-swscale
        --bit-depth=all
        --chroma-format=all
        --prefix="$FFBUILD_PREFIX"
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )
    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    # Явно указываем инструменты для стабильности
    export AS="nasm"
    export CC="${FFBUILD_CROSS_PREFIX}gcc"

    ./configure "${myconf[@]}" \
        --extra-cflags="$CFLAGS $CPPFLAGS" \
        --extra-ldflags="$LDFLAGS" || return 1

    # если в config.log написано "asm: no", значит nasm не подцепился
    if grep -q "asm: no" config.log; then
        log_error "x264 configured WITHOUT assembly! Check config.log."
        return 1
    fi

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # ФИКС pkg-config для статической линковки
    if [[ -f "$PC_DIR/x264.pc" ]]; then
        # Добавляем -lpthread, так как x264 его использует
        sed -i 's/Libs: /Libs.private: -pthread -lm\nLibs: /' "$PC_DIR/x264.pc"
    fi
}

ffbuild_configure() {
    echo --enable-libx264
}

ffbuild_unconfigure() {
    echo --disable-libx264
}
