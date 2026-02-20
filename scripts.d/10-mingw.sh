#!/bin/bash

SCRIPT_REPO="https://git.code.sf.net/p/mingw-w64/mingw-w64.git"
SCRIPT_COMMIT="3fedac28018c447ccdd9519c9d556340dfa1c87e"

ffbuild_enabled() {
    # [[ $TARGET == win* ]] || return 1
    return 0
}

ffbuild_dockerlayer() {
    # to_df "COPY --link --from=${SELFLAYER} /opt/mingw/. /"
    # to_df "COPY --link --from=${SELFLAYER} /opt/mingw/. /opt/mingw"
    to_df "COPY --link --from=${SELFLAYER} /opt/mingw/. /"
}

ffbuild_dockerfinal() {
    to_df "COPY --link --from=${PREVLAYER} /opt/mingw/. /"
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    # if [[ -z "$COMPILER_SYSROOT" ]]; then
        # COMPILER_SYSROOT="$(${CC} -print-sysroot)/usr/${FFBUILD_TOOLCHAIN}"
    # fi
    # Определяем sysroot тулчейна (обычно /opt/ct-ng/x86_64-w64-mingw32)
    local SYSROOT=$(${CC} -print-sysroot)
    # Нам нужен относительный путь для DESTDIR
    local REL_SYSROOT=${SYSROOT#/} 
    local TEMP_INSTALL="/tmp/mingw_install"
    
    mkdir -p "$TEMP_INSTALL"

    # Сбрасываем флаги, чтобы системная сборка не подхватила лишнего
    unset CC CXX LD AR CPP LIBS CCAS
    unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS CCASFLAGS
    unset PKG_CONFIG_LIBDIR
    # Важно: используем инструменты тулчейна напрямую
    local HOST_TRIPLET="$FFBUILD_TOOLCHAIN"

    ### 1. mingw-w64-headers
    (
        cd mingw-w64-headers
        ./configure \
            --prefix="$SYSROOT" \
            --host="$HOST_TRIPLET" \
            --with-default-win32-winnt="0x0A00" \
            --with-default-msvcrt=ucrt \
            --enable-idl --enable-sdk=all
        
        make -j$(nproc) $MAKE_V
        make install DESTDIR="$TEMP_INSTALL"
        cp -a "$TEMP_INSTALL/$REL_SYSROOT/." "$SYSROOT/"
    )

    ### 2. mingw-w64-crt
    (
        cd mingw-w64-crt
        # Добавляем CPPFLAGS чтобы принудительно искать в обновленном sysroot
        export CPPFLAGS="-I$SYSROOT/include"
        
        ./configure \
            --prefix="$SYSROOT" \
            --host="$HOST_TRIPLET" \
            --with-default-msvcrt=ucrt \
            --enable-wildcard \
            --disable-lib32 \
            --enable-lib64
            
        make -j$(nproc) $MAKE_V
        make install DESTDIR="$TEMP_INSTALL"
    )

    ### 3. winpthreads
    (
        cd mingw-w64-libraries/winpthreads
        export CPPFLAGS="-I$SYSROOT/include"
        ./configure \
            --prefix="$SYSROOT" \
            --host="$FFBUILD_TOOLCHAIN" \
            --with-pic --disable-shared --enable-static

        make -j$(nproc) $MAKE_V
        make install DESTDIR="$TEMP_INSTALL"
    )

    log_info "Syncing Mingw-w64 headers and CRT to sysroot..."
    # Копируем из временной папки в реальный sysroot компилятора
    cp -a "$TEMP_INSTALL/$REL_SYSROOT/." "$SYSROOT/"

    # Создаем артефакт для Docker-слоя (чтобы ffbuild_dockerlayer подхватил это)
    mkdir -p /opt/mingw
    cp -a "$SYSROOT/." /opt/mingw/
}

ffbuild_configure() {
    echo --disable-w32threads --enable-pthreads
}
