#!/bin/bash

SCRIPT_REPO="https://github.com/ismailivanov/DeepFilterNetPlus.git"
SCRIPT_COMMIT="c379acf323d3ac7dac26b66a61b13c3a52457502"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf assets \
models/DeepFilterNet.zip \
models/DeepFilterNet2.zip \
models/DeepFilterNet2_onnx.tar.gz \
models/DeepFilterNet2_onnx_ll.tar.gz \
models/DeepFilterNet3.zip
"
# models/DeepFilterNet3_ll_onnx.tar.gz
}

ffbuild_dockerbuild() {
    set -e

    if [[ -f "Cargo.toml" ]]; then
        log_info "Patching root Cargo.toml to enforce project-wide build profile..."
        NEW_RELEASE_PROFILE="[profile.release]
debug = false
strip = \"debuginfo\"
opt-level = 3
lto = $([ "${USE_LTO}" == "1" ] && echo true || echo false)
codegen-units = 1"
        sed -i '/^\[profile\.release\]/,/^\s*$/d' Cargo.toml
        sed -i '/^\[profile\.release-lto\]/,/^\s*$/d' Cargo.toml
        echo -e "\n$NEW_RELEASE_PROFILE" >> Cargo.toml
    fi

    cd libDF

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        sed -i 's/crate-type\s*=\s*\[.*\]/crate-type = ["cdylib"]/' Cargo.toml
    else
        sed -i 's/crate-type\s*=\s*\[.*\]/crate-type = ["staticlib"]/' Cargo.toml
    fi

    local myconf=(
        --release
        -p deep_filter
        --target="${FFBUILD_RUST_TARGET}"
        --features "capi,default-model,tract"
    )

    log_info "Building DeepFilterNet C-API library via Cargo..."
    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    RUSTFLAGS="$RUSTFLAGS" \
    cargo build $CARGO_V "${myconf[@]}" || return 1

    cd ..

    mkdir -p "$INSTALL_ROOT/include" "$INSTALL_ROOT/lib" "$PC_DIR"

    cat << 'EOF' > "$INSTALL_ROOT/include/deep_filter.h"
#ifndef DEEP_FILTER_H
#define DEEP_FILTER_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DFState DFState;

DFState* df_create(const char* path, float atten_lim, const char* log_level);
size_t df_get_frame_length(DFState* st);
float df_process_frame(DFState* st, float* input, float* output);
void df_set_post_filter_beta(DFState* st, float beta);
void df_free(DFState* model);

#ifdef __cplusplus
}
#endif

#endif
EOF

    local LIB_FILE=$(find target/${FFBUILD_RUST_TARGET}/release/ -maxdepth 1 \( -name "libdf.${lib_ext}" -o -name "df.lib" \))

    if [[ "$PREFER_SHARED" == "1" ]]; then
        cp "target/$FFBUILD_RUST_TARGET/release/df.dll" "$INSTALL_ROOT/bin/"
        cp "target/$FFBUILD_RUST_TARGET/release/df.dll.a" "$INSTALL_ROOT/lib/"
    else
        cp "$LIB_FILE" "$INSTALL_ROOT/lib/libdeep_filter.a"
    fi

    if [[ ! -f "${PC_DIR}/deep_filter.p" ]]; then
        cat <<EOF > "$PC_DIR/deep_filter.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: deep_filter
Description: Noise suppression using deep filtering (DeepFilterNet Rust C-API)
Version: 0.5.7
Libs: -L\${libdir} -ldeep_filter
Libs.private: -lntdll -luserenv -lws2_32 -lbcrypt
Cflags: -I\${includedir}
EOF
    fi
}

ffbuild_configure() {
    echo --enable-libdeep_filter
}