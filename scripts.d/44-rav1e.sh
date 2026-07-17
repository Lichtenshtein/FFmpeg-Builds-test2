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

        NEW_RELEASE_PROFILE="[profile.release]
debug = false
strip = \"debuginfo\"
opt-level = 3
lto = $([ "${USE_LTO}" == "1" ] && echo true || echo false)
incremental = false
codegen-units = 1"

        sed -i '/^\[profile\.release\]/,/^\s*$/d' Cargo.toml
        sed -i '/^\[profile\.release\]/,$d' Cargo.toml

        echo -e "\n$NEW_RELEASE_PROFILE" >> Cargo.toml
cat Cargo.toml
    fi

    # Fixing the issue with libgit2-sys: Disabling the use of the system libgit2
    unset PKG_CONFIG_LIBDIR
    export LIBGIT2_NO_PKG_CONFIG=1
    export LIBSSH2_SYS_USE_PKG_CONFIG=1

    # Cargo uses different variables for Host and Target when cross-compiling.
    # Convert x86_64-pc-windows-gnu to X86_64_PC_WINDOWS_GNU
    local RTARCH="${FFBUILD_RUST_TARGET//-/_}"
    RTARCH="${RTARCH^^}"

    # Force the compiler to be used for the TARGET
    export "CC_${RTARCH}"="${CC}"
    export "CXX_${RTARCH}"="${CXX}"
    export "AR_${RTARCH}"="${AR}"
    export "RANLIB_${RTARCH}"="${RANLIB}"

    # Flags for TARGET
    export "CFLAGS_${RTARCH}"="$CFLAGS $BASE_CPPFLAGS"
    export "CXXFLAGS_${RTARCH}"="$CXXFLAGS $BASE_CPPFLAGS"
    export "LDFLAGS_${RTARCH}"="$HOST_LDFLAGS"

    # Setting up for a hosted build
    # Using the standard GCC image, without any extra inclusions
    export CC_host="gcc"
    export LD_host="${HOST_LD}"
    export CFLAGS_host="$HOST_CFLAGS"
    export CXXFLAGS_host="$HOST_CXXFLAGS"
    export LDFLAGS_host="$HOST_LDFLAGS"

    # Reset shared variables so Cargo uses
    # the standard system GCC to build its internal utilities (build.rs)
    unset CC CXX AS AR RANLIB LD CFLAGS CXXFLAGS LDFLAGS CPPFLAGS

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

    cargo cinstall $CARGO_V "${myconf[@]}" || return 1

    chmod 644 "${INSTALL_ROOT}"/lib/*rav1e* || true
}

ffbuild_configure() {
    echo --enable-librav1e
}

ffbuild_unconfigure() {
    echo --disable-librav1e
}
