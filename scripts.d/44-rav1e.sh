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

    # Исправляем проблему с libgit2-sys: запрещаем использовать системный libgit2
    unset PKG_CONFIG_LIBDIR
    export LIBGIT2_NO_PKG_CONFIG=1
    export LIBSSH2_SYS_USE_PKG_CONFIG=1

    # Cargo при кросс-компиляции использует разные переменные для Хоста и Таргета
    # Превращаем x86_64-pc-windows-gnu в X86_64_PC_WINDOWS_GNU
    local RTARCH="${FFBUILD_RUST_TARGET//-/_}"
    RTARCH="${RTARCH^^}"

    # Принудительно задаем компилятор для ТАРГЕТА
    export "CC_${RTARCH}"="${CC}"
    export "CXX_${RTARCH}"="${CXX}"
    export "AR_${RTARCH}"="${AR}"
    export "RANLIB_${RTARCH}"="${RANLIB}"

    # Флаги для ТАРГЕТА
    export "CFLAGS_${RTARCH}"="$CFLAGS $BASE_CPPFLAGS"
    export "CXXFLAGS_${RTARCH}"="$CXXFLAGS $BASE_CPPFLAGS"
    export "LDFLAGS_${RTARCH}"="$HOST_LDFLAGS"

    # Настройка для хостовой сборки
    # Используем стандартный GCC образа, без лишних инклудов
    export CC_host="gcc"
    export LD_host="${HOST_LD}"
    export CFLAGS_host="$HOST_CFLAGS"
    export CXXFLAGS_host="$HOST_CXXFLAGS"
    export LDFLAGS_host="$HOST_LDFLAGS"

    # Сбрасываем общие переменные, чтобы Cargo использовал 
    # стандартный системный GCC для сборки своих внутренних утилит (build.rs)
    unset CC CXX AS AR RANLIB LD CFLAGS CXXFLAGS LDFLAGS CPPFLAGS

    # Принудительно обновляем зависимости, чтобы избежать багов в старых версиях cc-rs
    cargo update -p cc

    local myconf=(
        --prefix="${FFBUILD_PREFIX}"
        --destdir="${FFBUILD_DESTDIR}"
        --target="${FFBUILD_RUST_TARGET}"
        --release
    )

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        myconf+=(
            --library-type=cdylib
        )
    else
        myconf+=(
            --library-type=staticlib
            --crt-static
        )
    fi

    cargo cinstall $CARGO_V "${myconf[@]}" || return 1

    chmod 644 "${INSTALL_ROOT}"/lib/*rav1e* || true
}

ffbuild_configure() {
    echo --enable-librav1e
}

ffbuild_unconfigure() {
    echo --disable-librav1e
}
