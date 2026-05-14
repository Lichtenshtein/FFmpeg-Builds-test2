#!/bin/bash

SCRIPT_REPO="https://github.com/mingw-w64/mingw-w64.git"
SCRIPT_COMMIT="5d04f8f791c97255f53771888fff55924c62332a"

ffbuild_enabled() {
    [[ $TARGET == win* ]] || return 1
    return 0
}

ffbuild_dockerlayer() {
    to_df "COPY --link --from=${SELFLAYER} /opt/mingw/. /"
    to_df "COPY --link --from=${SELFLAYER} /opt/mingw/. /opt/mingw"
    # Копируем прямо в структуру тулчейна ct-ng
    # to_df "COPY --link --from=${SELFLAYER} /opt/mingw/. /opt/ct-ng/x86_64-w64-mingw32/x86_64-w64-mingw32/sysroot/mingw/"
}

ffbuild_dockerfinal() {
    to_df "COPY --link --from=${PREVLAYER} /opt/mingw/. /"
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Use the toolchain's internal sysroot as the target, but install to a temp dir first
    local SYSROOT=$(${FFBUILD_TOOLCHAIN}-gcc -print-sysroot)

    unset CC CXX LD AR CPP LIBS CCAS
    unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS CCASFLAGS
    unset PKG_CONFIG_LIBDIR
    # Force use of cross-tools
    export CC="${FFBUILD_TOOLCHAIN}-gcc"
    export CXX="${FFBUILD_TOOLCHAIN}-g++"
    export AR="${FFBUILD_TOOLCHAIN}-gcc-ar"
    export RANLIB="${FFBUILD_TOOLCHAIN}-gcc-ranlib"

    # 1. Headers
    cd mingw-w64-headers
        ./configure \
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
        ./configure \
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
        ./configure \
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

        # Копируем libwinpthread.a и делаем алиас libpthread.a
        cp -a "$SYSROOT/lib/libwinpthread.a" "$INSTALL_ROOT/lib/"
        ln -sf libwinpthread.a "$INSTALL_ROOT/lib/libpthread.a"

    cd ../..

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
