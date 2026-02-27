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
    # if [[ -d "/builder/patches/flite-test" ]]; then
        # for patch in /builder/patches/flite-test/*.patch; do
            # log_info "APPLYING PATCH: $patch"
            # if patch -p1 -N -r - < "$patch"; then
                # log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            # else
                # log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
            # fi
        # done
    # fi

    ./configure \
        --host="$FFBUILD_TOOLCHAIN" \
        --prefix="$FFBUILD_PREFIX" \
        --with-audio=none \
        --with-mmap=win32 \
        --with-lang=usenglish \
        --with-lex=cmulex \
        --with-vox=all \
        --enable-shared=no \
        --enable-static=yes \
        --with-pic \
        --disable-sockets \
        CFLAGS="$CFLAGS -D_WIN32 -DWAIT_ANY=-1" \
        LDFLAGS="$LDFLAGS"

    # В оригинальном flite make install часто не создает папки, создадим их заранее
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/{lib,include/flite,lib/pkgconfig}

    make -j$(nproc) $MAKE_V
    # make install DESTDIR="$FFBUILD_DESTDIR"

    # Ручная установка (так надежнее для кросс-компиляции flite)
    # Копируем основную библиотеку и библиотеки голосов
    find build/x86_64-w64-mingw32/lib -name "*.a" -exec cp -v {} "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/" \;

    # Копируем заголовки
    cp -v include/*.h "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/flite/"

    # Чтобы FFmpeg увидел все возможности, нужно перечислить основные библиотеки
    # Мы добавляем -lflite_cmu_us_kal (стандарт) и другие найденные при сборке $VOX_LIBS
    local VOX_LIBS=$(find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "libflite_*.a" | sed 's/.*lib\/\(lib\)\(.*\)\.a/-l\2/' | xargs)

    # Генерация правильного pkg-config (добавляем все необходимые части либы)
    # Flite после сборки CMake часто разбивается на несколько .a файлов, 
    # но нам нужен основной flite
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/flite.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include/flite

Name: flite
Description: Festival Lite Speech Synthesis System
Version: 2.3.0
Libs: -L\${libdir} -lflite -lflite_cmu_grapheme_lang -lflite_cmu_grapheme_lex -lflite_cmu_indic_lang -lflite_cmu_indic_lex -lflite_cmulex -lflite_cmu_time_awb -lflite_cmu_us_awb -lflite_cmu_us_kal16 -lflite_cmu_us_kal -lflite_cmu_us_rms -lflite_cmu_us_slt -lflite_usenglish -lm -lws2_32 
Libs.private: -lm
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-libflite
}

ffbuild_unconfigure() {
    echo --disable-libflite
}
