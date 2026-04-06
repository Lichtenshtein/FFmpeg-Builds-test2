#!/bin/bash

SCRIPT_REPO="https://github.com/xiph/rav1e.git"
SCRIPT_COMMIT="564ae3b0007ae2b06893fd7166bf88c5a84c5b63"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # 1. Полностью очищаем переменные, которые могут подсунуть MinGW-пути хостовому компилятору
    # local saved_CFLAGS="$CFLAGS"
    # local saved_CXXFLAGS="$CXXFLAGS"
    # local saved_LDFLAGS="$LDFLAGS"
    # local saved_CPPFLAGS="$CPPFLAGS"

    # Исправляем проблему с libgit2-sys: запрещаем использовать системный libgit2
    unset PKG_CONFIG_LIBDIR
    export LIBGIT2_NO_PKG_CONFIG=1
    export LIBSSH2_SYS_USE_PKG_CONFIG=1

    # Cargo при кросс-компиляции использует разные переменные для Хоста и Таргета
    # Превращаем x86_64-pc-windows-gnu в X86_64_PC_WINDOWS_GNU
    local RTARCH="${FFBUILD_RUST_TARGET//-/_}"
    RTARCH="${RTARCH^^}"

    # Принудительно задаем компилятор для ТАРГЕТА
    export "CC_${RTARCH}"="${FFBUILD_CROSS_PREFIX}gcc"
    export "CXX_${RTARCH}"="${FFBUILD_CROSS_PREFIX}g++"
    export "AR_${RTARCH}"="${FFBUILD_CROSS_PREFIX}gcc-ar"
    export "RANLIB_${RTARCH}"="${FFBUILD_CROSS_PREFIX}gcc-ranlib"

    # Флаги для ТАРГЕТА
    export "CFLAGS_${RTARCH}"="$CFLAGS ${CPPLAGS//-I\/opt\/ffbuild\/include/}"
    export "CXXFLAGS_${RTARCH}"="$CXXFLAGS ${CPPLAGS//-I\/opt\/ffbuild\/include/}"
    export "LDFLAGS_${RTARCH}"="${LDFLAGS//-L\/opt\/ffbuild\/lib/}"
    export RUSTFLAGS="$RUSTFLAGS"

    # 2. Передаем MinGW-пути ТОЛЬКО для таргета
    # export "CFLAGS_${RTARCH}"="$saved_CFLAGS $saved_CPPFLAGS"
    # export "CXXFLAGS_${RTARCH}"="$saved_CXXFLAGS $saved_CPPFLAGS"
    # export "LDFLAGS_${RTARCH}"="$saved_LDFLAGS"

    # Настройка для хостовой сборки
    # Используем стандартный GCC образа, без лишних инклудов
    export CC_host="gcc"
    export CFLAGS_host="-march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe"
    export CXXFLAGS_host="-march=${CPU_ARCH} -mtune=${CPU_TUNE} -O3 -pipe"

    # ОЧЕНЬ ВАЖНО: Сбрасываем общие переменные, чтобы Cargo использовал 
    # стандартный системный GCC для сборки своих внутренних утилит (build.rs)
    unset CC CXX AS AR RANLIB LD CFLAGS CXXFLAGS LDFLAGS CPPFLAGS

    # Принудительно обновляем зависимости, чтобы избежать багов в старых версиях cc-rs
    cargo update -p cc

    local myconf=(
        --prefix="${FFBUILD_PREFIX}"
        --destdir="${FFBUILD_DESTDIR}"
        --target="${FFBUILD_RUST_TARGET}"
        --library-type=staticlib
        --crt-static
        --release
    )

    cargo cinstall $CARGO_V "${myconf[@]}" || return 1

    # 3. Возвращаем переменные назад для следующих скриптов
    # export CFLAGS="$saved_CFLAGS"
    # export CXXFLAGS="$saved_CXXFLAGS"
    # export LDFLAGS="$saved_LDFLAGS"
    # export CPPFLAGS="$saved_CPPFLAGS"

    chmod 644 "${FFBUILD_DESTPREFIX}"/lib/*rav1e* || true
}

ffbuild_configure() {
    echo --enable-librav1e
}

ffbuild_unconfigure() {
    echo --disable-librav1e
}
