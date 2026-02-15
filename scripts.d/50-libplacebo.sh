#!/bin/bash

SCRIPT_REPO="https://github.com/haasn/libplacebo.git"
SCRIPT_COMMIT="b2ea27dceb6418aabfe9121174c6dbb232942998"

ffbuild_depends() {
    echo base
    echo vulkan
    echo shaderc
}

ffbuild_enabled() {
    (( $(ffbuild_ffver) > 600 )) || return -1
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/libplacebo" ]]; then
        for patch in /builder/patches/libplacebo/*.patch; do
            log_info "\n-----------------------------------"
            log_info "~~~ APPLYING PATCH: $patch"
            if patch -p1 < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
                log_info "-----------------------------------"
            else
                log_info "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                log_info "-----------------------------------"
                # exit 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    sed -i 's/DPL_EXPORT/DPL_STATIC/' src/meson.build

    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=static
        --cross-file=/cross.meson
        -Dvulkan=enabled
        -Dshaderc=enabled
        -Dglslang=enabled     # Включить, если 56-glslang собрался
        -Dlcms2=enabled       # Обычно есть в 45-lcms2.sh
        -Dvk-proc-addr=disabled
        -Dvulkan-registry="$FFBUILD_PREFIX"/share/vulkan/registry/vk.xml
        -Ddemos=false
        -Dtests=false
        -Dbench=false
        -Dfuzz=false
        -Dlibdovi=disabled    # Отключить, если нет отдельного скрипта
        -Dxxhash=disabled     # Мезон найдет системный, если он есть
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
    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    # Принудительно добавляем зависимости в pkg-config для статической линковки
    sed -i 's/Libs:/Libs: -lshaderc_combined -lspirv-cross-c -lspirv-cross-glsl -lspirv-cross-core /' "$FFBUILD_DESTPREFIX"/lib/pkgconfig/libplacebo.pc
    echo "Libs.private: -lstdc++ -lm -lshlwapi" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/libplacebo.pc
}

ffbuild_configure() {
    echo --enable-libplacebo
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) >= 500 )) || return 0
    echo --disable-libplacebo
}
