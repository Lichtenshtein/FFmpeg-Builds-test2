#!/bin/bash

SCRIPT_REPO="https://git.code.sf.net/p/mingw-w64/mingw-w64.git"
SCRIPT_COMMIT="b45abfec4e116b33620de597b99b1f0af3ab6a6a"

ffbuild_enabled() {
    [[ $TARGET == win* ]] || return -1
    return 0
}

ffbuild_dockerlayer() {
    [[ $TARGET == winarm* ]] && return 0
    # to_df "COPY --link --from=${SELFLAYER} /opt/mingw/. /"
    # to_df "COPY --link --from=${SELFLAYER} /opt/mingw/. /opt/mingw"
    to_df "COPY --link --from=${SELFLAYER} /opt/mingw/. /"
}

ffbuild_dockerfinal() {
    [[ $TARGET == winarm* ]] && return 0
    to_df "COPY --link --from=${PREVLAYER} /opt/mingw/. /"
}

ffbuild_dockerdl() {
    # Клонируем прямо в текущую директорию (.)
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    [[ $TARGET == winarm* ]] && return 0

    # if [[ -z "$COMPILER_SYSROOT" ]]; then
        # COMPILER_SYSROOT="$(${CC} -print-sysroot)/usr/${FFBUILD_TOOLCHAIN}"
    # fi
    # Определяем sysroot тулчейна (обычно /opt/ct-ng/x86_64-w64-mingw32)
    local SYSROOT=$(${CC} -print-sysroot)

    # Сбрасываем флаги, чтобы системная сборка не подхватила лишнего
    unset CC CXX LD AR CPP LIBS CCAS
    unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS CCASFLAGS
    unset PKG_CONFIG_LIBDIR

    ###
    ### mingw-w64-headers
    ###
    (
        cd mingw-w64-headers

            # --prefix="$COMPILER_SYSROOT"
        ./configure \
            --prefix="$SYSROOT" \
            --host="$FFBUILD_TOOLCHAIN" \
            --with-default-win32-winnt="0x601" \
            --with-default-msvcrt=ucrt \
            --enable-idl --enable-sdk=all --enable-secure-api
        
        # Устанавливаем в /opt/mingw, сохраняя структуру относительно корня
        make -j$(nproc) $MAKE_V
        make install DESTDIR="/opt/mingw"
    )

    # Синхронизируем для сборки следующих этапов внутри этого же скрипта
    cp -a /opt/mingw/. /

    ###
    ### mingw-w64-crt
    ###
    (
        cd mingw-w64-crt
        ./configure \
            --prefix="$SYSROOT" \
            --host="$FFBUILD_TOOLCHAIN" \
            --with-default-msvcrt=ucrt \
            --enable-wildcard
        make -j$(nproc) $MAKE_V
        make install DESTDIR="/opt/mingw"
    )
    cp -a /opt/mingw/. /

    ###
    ### mingw-w64-libraries/winpthreads (Важно для FFmpeg)
    ###
    (
        cd mingw-w64-libraries/winpthreads
        ./configure \
            --prefix="$SYSROOT" \
            --host="$FFBUILD_TOOLCHAIN" \
            --with-pic --disable-shared --enable-static
        make -j$(nproc) $MAKE_V
        make install DESTDIR="/opt/mingw"
    )
}

ffbuild_configure() {
    echo --disable-w32threads --enable-pthreads
}
