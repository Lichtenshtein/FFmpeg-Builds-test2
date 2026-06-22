#!/bin/bash

SCRIPT_REPO="https://github.com/mingw-w64/mingw-w64.git"
SCRIPT_COMMIT="b536c4fdb038a9c59a7e5fb36e7d1293c4dc61d6"

ffbuild_enabled() {
    [[ $TARGET == win* ]] || return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Use the toolchain's internal sysroot as the target, but install to a temp dir first
    local SYSROOT=$(${FFBUILD_TOOLCHAIN}-gcc -print-sysroot)

    unset CC CXX LD AR CPP LIBS CCAS
    # unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS CCASFLAGS
    unset PKG_CONFIG_LIBDIR

    # Force use of cross-tools
    export CC="${FFBUILD_TOOLCHAIN}-gcc"
    export CXX="${FFBUILD_TOOLCHAIN}-g++"

    local CRT_CFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -pipe -g0 -fno-lto"

    # 1. Headers
    cd mingw-w64-headers
        CFLAGS="" CPPFLAGS="" ./configure \
          --prefix="$SYSROOT" \
          --host="$FFBUILD_TOOLCHAIN" \
          --with-default-win32-winnt="0x0A00" \
          --with-default-msvcrt=ucrt \
          --enable-idl \
          --enable-sdk=all || return 1
        make install DESTDIR="/opt/mingw" || return 1
        # Копируем из DESTDIR в реальный SYSROOT тулчейна
        cp -a /opt/mingw/"$SYSROOT"/. "$SYSROOT/"
    cd ..

    # 2. CRT
    cd mingw-w64-crt
        export AR="${FFBUILD_TOOLCHAIN}-ar"
        export RANLIB="${FFBUILD_TOOLCHAIN}-ranlib"
        local CLEAN_CPPFLAGS=$(echo "$BASE_CPPFLAGS" | sed 's/-D__USE_MINGW_ANSI_STDIO=1//g')

        CFLAGS="$CRT_CFLAGS" CPPFLAGS="$CLEAN_CPPFLAGS" ./configure \
          --prefix="$SYSROOT" \
          --host="$FFBUILD_TOOLCHAIN" \
          --with-default-msvcrt=ucrt \
          --enable-wildcard \
          --disable-lib32 \
          --enable-lib64 || return 1
        make -j$(nproc) $MAKE_V || return 1
        make install DESTDIR="/opt/mingw" || return 1
        # Копируем из DESTDIR в реальный SYSROOT тулчейна
        cp -a /opt/mingw/"$SYSROOT"/. "$SYSROOT/"
    cd ..

    # 3. Winpthreads
    cd mingw-w64-libraries/winpthreads
        if [[ "$USE_LTO" == "1" ]]; then
            export AR="${FFBUILD_CROSS_PREFIX}gcc-ar"
            export NM="${FFBUILD_CROSS_PREFIX}gcc-nm"
            export RANLIB="${FFBUILD_CROSS_PREFIX}gcc-ranlib"
            local PTHREAD_CFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -pipe -g0 ${USELTO}${USELTO_C}"
        else
            export AR="${FFBUILD_TOOLCHAIN}-ar"
            export RANLIB="${FFBUILD_TOOLCHAIN}-ranlib"
            local PTHREAD_CFLAGS="$CRT_CFLAGS"
        fi

        CFLAGS="$PTHREAD_CFLAGS" CPPFLAGS="$CLEAN_CPPFLAGS" ./configure \
          --prefix="$SYSROOT" \
          --host="$FFBUILD_TOOLCHAIN" \
          --with-pic \
          --enable-$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static) \
          --disable-$([ "${PREFER_SHARED}" == "1" ] && echo static || echo shared) || return 1
        make -j$(nproc) $MAKE_V || return 1
        make install DESTDIR="/opt/mingw" || return 1
        cp -a /opt/mingw/"$SYSROOT"/. "$SYSROOT/"

        # Создаем необходимые директории в persistent storage
        mkdir -p "$INSTALL_ROOT/include" "$INSTALL_ROOT/lib"

        # Копируем заголовки и библиотеки во внешний префикс ffbuild для сборки ffmpeg
        cp -a "$SYSROOT/include/pthread"* "$INSTALL_ROOT/include/"
        cp -a "$SYSROOT/include/sched.h" "$INSTALL_ROOT/include/"

    cd ../..

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # Копируем libwinpthread.a и делаем алиас libpthread.a
        cp -a "$SYSROOT/lib/libwinpthread.a" "$INSTALL_ROOT/lib/"
        ln -sf libwinpthread.a "$INSTALL_ROOT/lib/libpthread.a"

        log_info "Isolating compiler runtime static libraries for FFmpeg..."
        # Находим, где в недрах вашего ct-ng GCC спрятана оригинальная статическая libssp.a
        local COMPILER_LIB_DIR=$(${FFBUILD_TOOLCHAIN}-gcc -print-file-name=libssp.a)
        if [ -f "$COMPILER_LIB_DIR" ]; then
            local COMPILER_DIR=$(dirname "$COMPILER_LIB_DIR")
            log_info "Found compiler runtime directory at: ${COMPILER_DIR}"
            # Копируем ssp статику во внешний префикс ffbuild
            cp -a "${COMPILER_DIR}/libssp.a" "$INSTALL_ROOT/lib/"
            cp -a "${COMPILER_DIR}/libssp_nonshared.a" "$INSTALL_ROOT/lib/" 2>/dev/null || true
        else
            log_warn "Could not pinpoint libssp.a path via GCC wrapper."
        fi

        # в sysroot не должно быть копий, мешающих линковке
        log_info "Purging conflicting runtime DLL references from target folders..."
        # удаляем случайные .dll winpthread/ssp из $SYSROOT/lib $INSTALL_ROOT/lib
        rm -f "$INSTALL_ROOT/lib/libwinpthread.dll.a" "$INSTALL_ROOT/lib/libwinpthread-1.dll"
        rm -f "$INSTALL_ROOT/lib/libssp.dll.a" "$INSTALL_ROOT/lib/libssp-0.dll"
        log_info "Runtime static isolation complete."
    fi

    # Объектные файлы (Нужны для финальной линковки .exe)
    # crt2.o это точка входа для консольных приложений Windows
    # cp -a "$SYSROOT/lib/crt2.o" "$INSTALL_ROOT/lib/"

    # Копируем заголовки полностью
    # cp -a "$SYSROOT/include/." "$INSTALL_ROOT/include/"

    # Удаляем конфликтные файлы, если они случайно попали
    # (GCC должен использовать свои встроенные версии)
    # for f in stddef.h stdint.h float.h stdarg.h stdbool.h varargs.h; do
        # rm -f "$INSTALL_ROOT/include/$f"
    # done

    # Копируем объекты инициализации CRT (crt2.o и т.д.)
    # Они нужны для финальной стадии линковки .exe в статике
    # cp -f "$SYSROOT/lib/"*.o "$INSTALL_ROOT/lib/" 2>/dev/null || true

    # Копируем только статические библиотеки
    # Исключаем .dll.a (библиотеки импорта) и .la (метаданные libtool)
    # find "$SYSROOT/lib" -maxdepth 1 -name "*.a" ! -name "*.dll.a" -exec cp -a {} "$INSTALL_ROOT/lib/" \;

    # Очистка динамики внутри префикса
    # find "$INSTALL_ROOT/lib" -name "*.la" -delete
    # find "$INSTALL_ROOT/lib" -name "*.dll.a" -delete
}

# ffbuild_configure() {
    # echo "--disable-w32threads --enable-pthreads"
# }
