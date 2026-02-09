#!/bin/bash

SCRIPT_REPO="https://github.com/haasn/libplacebo.git"
SCRIPT_COMMIT="b2ea27dceb6418aabfe9121174c6dbb232942998"

ffbuild_depends() {
    echo base
    echo vulkan
}

ffbuild_enabled() {
    (( $(ffbuild_ffver) > 600 )) || return -1
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
    # —начала клонируем основной репозиторий с историей (глубина 1)
    # echo "git clone --filter=blob:none --depth=1 \"$SCRIPT_REPO\" ."
    # «атем принудительно инициализируем подмодули без лишних фильтров, которые могут не поддерживатьс€ старыми верси€ми git
    # echo "git submodule update --init --recursive --depth=1"
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/libplacebo" ]]; then
        for patch in /builder/patches/libplacebo/*.patch; do
            echo "Applying $patch"
            patch -p1 < "$patch"
        done
    fi

    sed -i 's/DPL_EXPORT/DPL_STATIC/' src/meson.build

    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=static
        -Dvulkan=enabled
        -Dvk-proc-addr=disabled
        -Dvulkan-registry="$FFBUILD_PREFIX"/share/vulkan/registry/vk.xml
        -Dshaderc=enabled
        -Dglslang=disabled
        -Ddemos=false
        -Dtests=false
        -Dbench=false
        -Dfuzz=false
    )

    if [[ $TARGET == win* ]]; then
        myconf+=(
            -Dd3d11=enabled
        )
    fi

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file=/cross.meson
        )
    else
        echo "Unknown target"
        return -1
    fi

    meson "${myconf[@]}" ..
    ninja -j$(nproc)
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    echo "Libs.private: -lstdc++" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/libplacebo.pc
}

ffbuild_configure() {
    echo --enable-libplacebo
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) >= 500 )) || return 0
    echo --disable-libplacebo
}
