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
    echo "rm -rf \
quiche/deps/boringssl/.git \
quiche/deps/boringssl/crypto_test_data.cc \
quiche/deps/boringssl/src/fuzz \
quiche/deps/boringssl/src/pki/testdata \
quiche/deps/boringssl/src/ssl/test \
quiche/deps/boringssl/src/third_party/googletest \
quiche/deps/boringssl/src/third_party/wycheproof_testvectors"
}

ffbuild_dockerbuild() {
    set -e

    if [[ -f "Cargo.toml" ]]; then
        log_info "Patching Cargo.toml to disable forced debug symbols in release profile..."

        NEW_RELEASE_PROFILE="[profile.release]
debug = false
strip = \"debuginfo\"
opt-level = 3
lto = $([ "${USE_LTO}" == "1" ] && echo true || echo false)
codegen-units = 1"

        sed -i '/^\[profile\.release\]/,/^\s*$/d' Cargo.toml
        sed -i '/^\[profile\.release\]/,$d' Cargo.toml

        echo -e "\n$NEW_RELEASE_PROFILE" >> Cargo.toml

cat Cargo.toml

    fi

    cd quiche

    # Replace crate-type = ["lib", "staticlib", "cdylib"] with ["staticlib"]
    if [[ "${PREFER_SHARED}" == "1" ]]; then
        sed -i 's/crate-type = \[.*\]/crate-type = ["cdylib"]/' Cargo.toml
    else
        sed -i 's/crate-type = \[.*\]/crate-type = ["staticlib"]/' Cargo.toml
    fi

    # Configuring the environment to use external OpenSSL (via pkg-config)
    export OPENSSL_NO_VENDOR=1
    export OPENSSL_DIR="$FFBUILD_PREFIX"
    export OPENSSL_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo 0 || echo 1)

    # Building with cargo
    # --features ffi: Creates a C-compatible library and headers
    # --features pkg-config: Generates a .pc file
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

    local LIB_FILE=$(find target/${FFBUILD_RUST_TARGET}/release/ -maxdepth 1 \( -name "libquiche.${lib_ext}" -o -name "quiche.lib" \))
    local HEADER_FILE=$(find quiche/include/ -name "quiche.h")

    cp "$HEADER_FILE" "$INSTALL_ROOT/include/quiche.h"
    # Copy BoringSSL headers
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
Version: 0.24.5
Libs: -L\${libdir} -lquiche
Libs.private: -lntdll
Cflags: -I\${includedir}
EOF

    # if has_library "ssl"; then
        # try to resolve future symbol collisions with openssl
        # ${OBJCOPY} --localize-hidden "$INSTALL_ROOT"/lib/libquiche.${lib_ext}
    # fi
}
