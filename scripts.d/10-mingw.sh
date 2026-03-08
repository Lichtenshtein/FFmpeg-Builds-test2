#!/bin/bash

SCRIPT_REPO="https://git.code.sf.net/p/mingw-w64/mingw-w64.git"
SCRIPT_COMMIT="3fedac28018c447ccdd9519c9d556340dfa1c87e"

ffbuild_enabled() {
    # [[ $TARGET == win* ]] || return 1
    return 0
}

ffbuild_dockerlayer() {
    # to_df "COPY --link --from=${SELFLAYER} /opt/mingw/. /"
    # Копируем прямо в структуру тулчейна ct-ng
    to_df "COPY --link --from=${SELFLAYER} /opt/mingw/. /opt/ct-ng/x86_64-w64-mingw32/x86_64-w64-mingw32/sysroot/mingw/"
}

ffbuild_dockerfinal() {
    to_df "COPY --link --from=${PREVLAYER} /opt/mingw/. /"
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    local SYSROOT=$(${CC} -print-sysroot)
    [[ -z "$SYSROOT" ]] && log_error "SYSROOT NOT FOUND" && exit 1

    unset CC CXX LD AR CPP LIBS CCAS
    unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS CCASFLAGS
    unset PKG_CONFIG_LIBDIR

    ### 1. mingw-w64-headers
    (
        cd mingw-w64-headers
        ./configure \
            --prefix="$SYSROOT" \
            --host="$FFBUILD_TOOLCHAIN" \
            --with-default-win32-winnt="0x0A00" \
            --with-default-msvcrt=ucrt \
            --enable-idl \
            --enable-sdk=all
        make install
    )

    ### 2. mingw-w64-crt
    (
        cd mingw-w64-crt
        export CPPFLAGS="-I$SYSROOT/include"
        ./configure \
            --prefix="$SYSROOT" \
            --host="$FFBUILD_TOOLCHAIN" \
            --with-default-msvcrt=ucrt \
            --enable-wildcard \
            --disable-lib32 \
            --enable-lib64 \
            --disable-dependency-tracking # удалить про проблемах. Ускоряет и убирает лишние проверки
        make -j$(nproc) $MAKE_V
        make install
    )

    ### 3. winpthreads
    (
        cd mingw-w64-libraries/winpthreads
        ./configure \
            --prefix="$SYSROOT" \
            --host="$FFBUILD_TOOLCHAIN" \
            --with-pic \
            --disable-shared \
            --enable-static

        make -j$(nproc) $MAKE_V
        make install
    )

    mkdir -p /opt/mingw
    cp -a "$SYSROOT/." /opt/mingw/

    clean_la_files

    get_deps_list
}

ffbuild_configure() {
    echo --disable-w32threads --enable-pthreads
}
