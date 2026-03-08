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
    to_df "COPY --link --from=${SELFLAYER} /opt/mingw/. ${FFBUILD_SYSROOT}/"
}

ffbuild_dockerfinal() {
    to_df "COPY --link --from=${PREVLAYER} /opt/mingw/. /"
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    local COMP_SYS="$FFBUILD_SYSROOT"

    unset CC CXX LD AR AS CPP CFLAGS CXXFLAGS LDFLAGS CPPFLAGS LIBS PKG_CONFIG_LIBDIR

    mkdir -p /opt/mingw

    # 1. Headers
    (
        cd mingw-w64-headers
        ./configure \
            --host="$FFBUILD_TOOLCHAIN" \
            --prefix="$COMP_SYS" \
            --with-default-win32-winnt="0x0A00" \
            --with-default-msvcrt=ucrt \
            --enable-idl \
            --enable-sdk=all
        make -j$(nproc) $MAKE_V
        make install DESTDIR="/opt/mingw"
    )

    # 2. CRT
    (
        cd mingw-w64-crt
        ./configure \
            --host="$FFBUILD_TOOLCHAIN" \
            --prefix="$COMP_SYS" \
            --with-default-msvcrt=ucrt \
            --enable-lib64 \
            --disable-lib32 \
            --enable-wildcard \
            --disable-dependency-tracking # удалить про проблемах. Ускоряет и убирает лишние проверки
        make -j$(nproc) $MAKE_V
        make install DESTDIR="/opt/mingw"
    )

    # 3. Winpthreads
    (
        cd mingw-w64-libraries/winpthreads
        ./configure \
            --host="$FFBUILD_TOOLCHAIN" \
            --prefix="$COMP_SYS" \
            --with-pic \
            --disable-shared \
            --enable-static
        make -j$(nproc) $MAKE_V
        make install DESTDIR="$TEMP_INSTALL"
    )

    log_info "Syncing Mingw-w64 headers and CRT to sysroot..."
    # Копируем из временной папки в реальный sysroot компилятора
    cp -av /opt/mingw"$COMP_SYS"/. "$COMP_SYS/"

    clean_la_files

    get_deps_list
}

ffbuild_configure() {
    echo --disable-w32threads --enable-pthreads
}
