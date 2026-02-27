#!/bin/bash

SCRIPT_REPO="https://github.com/Tomotz/flite.git"
SCRIPT_COMMIT="6ff94c999339a26281180c8b4ba3c89f2e1fcdf9"
SCRIPT_BRANCH="tomm-dump-ipa"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/flite-test" ]]; then
        for patch in /builder/patches/flite-test/*.patch; do
            log_info "APPLYING PATCH: $patch"
            if patch -p1 -N -r - -l < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
            fi
        done
    fi

    local myconf=(
        --host="$FFBUILD_TOOLCHAIN"
        --prefix="$FFBUILD_PREFIX"
        --with-audio=none
        --with-mmap=win32
        --with-lang=usenglish
        --with-lex=cmulex
        --with-vox=all
        --enable-shared=no
        --with-pic
        --disable-sockets
    )

    # Добавляем LTO если включено в workflow
    if [[ "$USE_LTO" == "1" ]]; then
        log_info "LTO is enabled for $STAGENAME"
        export CFLAGS="$CFLAGS -flto"
        export LDFLAGS="$LDFLAGS -flto"
    fi

    # Flite не понимает --enable-static, он делает её по умолчанию при --enable-shared=no
    ./configure "${myconf[@]}" CFLAGS="$CFLAGS -D_WIN32 -DWAIT_ANY=-1" LDFLAGS="$LDFLAGS"

    # Предварительное создание структуры
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/{lib/pkgconfig,include/flite}

    make -j$(nproc) $MAKE_V
    # make install DESTDIR="$FFBUILD_DESTDIR"

    # Динамический поиск папки с либами (fix для x86_64-mingw32 vs x86_64-w64-mingw32)
    local BUILDIR=$(find build -maxdepth 2 -type d -name "lib" | head -n 1)
    if [[ -d "$BUILDIR" ]]; then
        log_info "Found build libraries in $BUILDIR"
        cp -v "$BUILDIR"/*.a "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
    else
        log_error "Could not find compiled libraries in build/ folder!"
        return 1
    fi

    # Копируем заголовки
    cp -v include/*.h "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/flite/"

    # Собираем список всех библиотек для Libs (согласно flite.pc.in и реальности)
    # Порядок важен: сначала голоса и лексиконы, в конце -lflite
    local VOX_LIBS=$(find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "libflite_*.a" | sed "s|.*/lib\(flite_.*\)\.a|-l\1|" | xargs)

    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/flite.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include/flite

Name: flite
Description: a text to speech library
Version: 2.3.0
Libs: -L\${libdir} $VOX_LIBS -lflite -lm -lws2_32
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-libflite
}

ffbuild_unconfigure() {
    echo --disable-libflite
}
