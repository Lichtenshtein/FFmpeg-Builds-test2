#!/bin/bash

SCRIPT_REPO="https://github.com/meganz/mingw-std-threads.git"
SCRIPT_COMMIT="c931bac289dd431f1dd30fc4a5d1a7be36668073"

ffbuild_depends() {
    return 0
}

ffbuild_enabled() {
    [[ $TARGET == win* ]] || return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
mold --version | head -n 1
    cd "/build/$STAGENAME"

    log_info "Installing mingw-std-threads headers from $(pwd)..."

    mkdir -p "$INSTALL_ROOT/include"

    if ls *.h >/dev/null 2>&1; then
        cp *.h "$INSTALL_ROOT/include/"
        log_info "${CHECK_MARK} Headers installed successfully."
    else
        log_error "No .h files found in $(pwd)!"
        ls -F
        return 1
    fi
}
