#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/libbluray.git"
SCRIPT_COMMIT="71c5324e78dc7a159cad67ea7967300db54ec21c"

ffbuild_depends() {
    echo base
    echo libxml2
    echo fonts
    echo libudfread
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
# Определяем цвета и символы
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color (сброс цвета)
CHECK_MARK='✅'
CROSS_MARK='❌'
    
    if [[ -d "/builder/patches/libbluray" ]]; then
        for patch in /builder/patches/libbluray/*.patch; do
            echo -e "\n-----------------------------------"
            echo "~~~ APPLYING PATCH: $patch"
            # Выполняем патч и проверяем код выхода
            if patch -p1 < "$patch"; then
                echo -e "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
                echo "-----------------------------------"
            else
                echo -e "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                echo "-----------------------------------"
                # exit 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    # stop the static library from exporting symbols when linked into a shared lib
    sed -i 's/-DBLURAY_API_EXPORT/-DBLURAY_API_EXPORT_DISABLED/g' src/meson.build

    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        -Ddefault_library=static
        -Denable_docs=false
        -Denable_tools=false
        -Denable_devtools=false
        -Denable_examples=false
        -Dbdj_jar=disabled
        -Dfontconfig=enabled
        -Dfreetype=enabled
        -Dlibxml2=enabled
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file=/cross.meson
        )
    else
        echo "Unknown target"
        return -1
    fi

    export CPPFLAGS="${CPPFLAGS} -Ddec_init=libbr_dec_init"

    meson setup "${myconf[@]}" ..
    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install
}

ffbuild_configure() {
    echo --enable-libbluray
}

ffbuild_unconfigure() {
    echo --disable-libbluray
}
