#!/bin/bash

SCRIPT_REPO="https://github.com/meganz/mingw-std-threads.git"
SCRIPT_COMMIT="c931bac289dd431f1dd30fc4a5d1a7be36668073"

ffbuild_depends() {
    return 0
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    # Возвращаемся в корень распаковки, если run_stage увел нас в /tests
    # $STAGENAME определена в run_stage.sh
    cd "/build/$STAGENAME"

    log_info "Installing mingw-std-threads headers from $(pwd)..."
    
    mkdir -p "$FFBUILD_DESTPREFIX/include"
    
    # Копируем только существующие .h файлы
    if ls *.h >/dev/null 2>&1; then
        cp *.h "$FFBUILD_DESTPREFIX/include/"
        log_info "Headers installed successfully."
    else
        log_error "No .h files found in $(pwd)!"
        ls -F
        return 1
    fi
}

