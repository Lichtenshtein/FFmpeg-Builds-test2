#!/bin/bash

SCRIPT_REPO="https://github.com/cloudflare/quiche.git"
SCRIPT_COMMIT="ffb07b940673383fc29e78f52130ef60f5417c06"

ffbuild_depends() {
    echo zlib
    echo libffi
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Настройка окружения для Rust
    export QUICHE_BSSL_PATH="$FFBUILD_PREFIX"
    # Указываем cargo использовать наш кросс-тулчейн
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="${FFBUILD_CROSS_PREFIX}gcc"

    # Сборка через cargo
    # --features ffi: создаёт C-совместимую библиотеку и заголовки
    # --features pkg-config: генерирует .pc файл
    #  * `boringssl-vendored` (default): Build the vendored BoringSSL library.
    #    --features ffi,pkg-config-meta,http3

    local myconf=(
        --release
        --target="${FFBUILD_RUST_TARGET}"
        --prefix="$FFBUILD_PREFIX"
        --destdir="$FFBUILD_DESTDIR"
        --library-type=$([ "${PREFER_SHARED}" == "1" ] && echo cdylib || echo staticlib)
        --features pkg-config-meta
    )

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    RUSTFLAGS="$RUSTFLAGS" \
    cargo build $CARGO_V "${myconf[@]}" || return 1

    # Ручная установка, так как cargo не имеет "install" в префикс
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include"
    mkdir -p "$PC_DIR"

    cp include/quiche.h "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"
    cp "target/$FFBUILD_RUST_TARGET/release/libquiche.a" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"

    # Генерация или исправление .pc файла
    cat <<EOF > "$PC_DIR/quiche.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: quiche
Description: QUIC and HTTP/3 implementation
Version: 0.20.0
Libs: -L\${libdir} -lquiche
Cflags: -I\${includedir}
EOF
}
