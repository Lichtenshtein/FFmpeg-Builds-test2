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
    set -e

    # Flite не понимает --enable-static, он делает её по умолчанию при --enable-shared=no
    local myconf=(
        --host="$FFBUILD_TOOLCHAIN"
        --prefix="$FFBUILD_PREFIX"
        --with-audio=none # specific audio support (none linux freebsd etc)
        --with-mmap=win32 # mmap support (none posix win32)
        --with-lang=usenglish
        --with-lex=cmulex
        --with-vox=all
        # --with-langvox # with subsets of lang, lex and voices
        --with-pic
        --disable-sockets
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --enable-shared=yes ) || \
        myconf+=( --enable-shared=no --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS -DWAIT_ANY=-1" \
    CXXFLAGS="$CXXFLAGS ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    # Предварительное создание структуры
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/{lib/pkgconfig,include/flite}

    make -j$(nproc) $MAKE_V || return 1
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

    cat <<EOF > "$PC_DIR/flite.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include/flite

Name: flite
Description: a text to speech library
Version: $VER_FULL
Libs: -L\${libdir} $VOX_LIBS -lflite
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo "--enable-libflite"
}

ffbuild_unconfigure() {
    echo "--disable-libflite"
}

ffbuild_libs() {
    echo "-lflite"
}
