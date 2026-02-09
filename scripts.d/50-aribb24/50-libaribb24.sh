#!/bin/bash

SCRIPT_REPO="https://github.com/scimmia9286/aribb24.git"
SCRIPT_COMMIT="add-multi-DRCS-plane"

ffbuild_dockerdl() {
    # Клонируем конкретную ветку
    echo "git clone --filter=blob:none --branch \"$SCRIPT_COMMIT\" \"$SCRIPT_REPO\" ."
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    # Путь к патчам теперь фиксированный из generate.sh
    if [[ -d "/builder/patches/aribb24" ]]; then
        for patch in /builder/patches/aribb24/*.patch; do
            echo "Applying $patch"
            git apply "$patch"
        done
    fi

    # Library switched to LGPL on master, but didn't bump version since.
    # FFmpeg checks for >1.0.3 to allow LGPL builds.
    sed -i 's/1.0.3/1.0.4/' configure.ac

    autoreconf -i

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --with-pic
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libaribb24
}

ffbuild_unconfigure() {
    echo --disable-libaribb24
}
