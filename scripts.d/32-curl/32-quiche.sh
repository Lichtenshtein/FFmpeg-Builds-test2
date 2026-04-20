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
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    cd quiche

    # Заменяем crate-type = ["lib", "staticlib", "cdylib"] на ["staticlib"]
    if [[ "${PREFER_SHARED}" == "1" ]]; then
        sed -i 's/crate-type = \[.*\]/crate-type = ["cdylib"]/' Cargo.toml
    else
        sed -i 's/crate-type = \[.*\]/crate-type = ["staticlib"]/' Cargo.toml
    fi

    # Настройка окружения для использования внешнего OpenSSL (через pkg-config)
    export OPENSSL_NO_VENDOR=1
    export OPENSSL_DIR="$FFBUILD_PREFIX"
    export OPENSSL_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo 0 || echo 1)

    # Сборка через cargo
    # --features ffi: создаёт C-совместимую библиотеку и заголовки
    # --features pkg-config: генерирует .pc файл
    #  * `boringssl-vendored` (default): Build the vendored BoringSSL library.
    #    --features ffi,pkg-config-meta,http3

    local myconf=(
        --release
        --target="${FFBUILD_RUST_TARGET}"
        # --no-default-features
        --features ffi,pkg-config-meta
    )

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    RUSTFLAGS="$RUSTFLAGS" \
    cargo build $CARGO_V "${myconf[@]}" || return 1

    cd ..

    mkdir -p "$INSTALL_ROOT/include/boringssl" "$INSTALL_ROOT/lib" "$PC_DIR"

    local LIB_FILE=$(find target/${FFBUILD_RUST_TARGET}/release/ -maxdepth 1 \( -name "libquiche.a" -o -name "quiche.lib" \))
    local HEADER_FILE=$(find quiche/include/ -name "quiche.h")

    cp "$HEADER_FILE" "$INSTALL_ROOT/include/quiche.h"
    # Копируем заголовки BoringSSL
    # cp -r quiche/deps/boringssl/src/include/openssl/* "$INSTALL_ROOT/include/boringssl/"

    if [[ "$PREFER_SHARED" == "1" ]]; then
        cp "target/$FFBUILD_RUST_TARGET/release/quiche.dll" "$INSTALL_ROOT/bin/"
        cp "target/$FFBUILD_RUST_TARGET/release/quiche.dll.a" "$INSTALL_ROOT/lib/"
    else
        cp "$LIB_FILE" "$INSTALL_ROOT/lib/libquiche.a"
    fi

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
