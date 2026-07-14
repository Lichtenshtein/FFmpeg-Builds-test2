#!/bin/bash

SCRIPT_REPO="https://github.com/xiph/rav1e.git"
SCRIPT_COMMIT="564ae3b0007ae2b06893fd7166bf88c5a84c5b63"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf \
doc/quantizer-weight-analysis.ipynb \
doc/structure.png"
}

ffbuild_dockerbuild() {
    set -e

    if [[ -f "Cargo.toml" ]]; then
        log_info "Patching Cargo.toml to disable forced debug symbols in release profile..."
        # Replace debug = true with debug = false (disables debug information generation)
        sed -i 's|debug = true|debug = false|g' Cargo.toml
        # Disable incremental builds for releases to keep object files as monolithic as possible
        sed -i 's|incremental = true|incremental = false|g' Cargo.toml
        # Change lto = "thin" to fair lto = "fat"
        if [[ "$USE_LTO" == "1" ]]; then
            sed -i 's|lto = "thin"|lto = "fat"|g' Cargo.toml
        fi
    fi

    # Force dependencies to be updated to avoid bugs in older versions of cc-rs
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

    env \
      "CC_${RTARCH}=${CC}" \
      "CXX_${RTARCH}=${CXX}" \
      "AR_${RTARCH}=${AR}" \
      "RANLIB_${RTARCH}=${RANLIB}" \
      "CFLAGS_${RTARCH}=${CFLAGS//-mconsole/} $BASE_CPPFLAGS" \
      "CXXFLAGS_${RTARCH}=${CXXFLAGS//-mconsole/} $BASE_CPPFLAGS" \
      "LDFLAGS_${RTARCH}=$HOST_LDFLAGS" \
      "CARGO_TARGET_${RTARCH}_RUSTFLAGS=${RUSTFLAGS}" \
      CC_host="gcc" \
      LD_host="${HOST_LD}" \
      CFLAGS_host="$HOST_CFLAGS" \
      CXXFLAGS_host="$HOST_CXXFLAGS" \
      LDFLAGS_host="$HOST_LDFLAGS" \
      LIBGIT2_NO_PKG_CONFIG=1 \
      LIBSSH2_SYS_USE_PKG_CONFIG=1 \
      cargo cinstall $CARGO_V "${myconf[@]}" || return 1

    chmod 644 "${INSTALL_ROOT}"/lib/*rav1e* || true
}

ffbuild_configure() {
    echo --enable-librav1e
}

ffbuild_unconfigure() {
    echo --disable-librav1e
}
