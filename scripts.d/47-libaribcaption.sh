#!/bin/bash

SCRIPT_REPO="https://github.com/xqq/libaribcaption.git"
SCRIPT_COMMIT="27cf3cab26084d636905335d92c375ecbc3633ea"

ffbuild_depends() {
    echo base
    echo freetype
    echo fontconfig
    echo harfbuzz
    echo openssl
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DARIBCC_SHARED_LIBRARY=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DARIBCC_BUILD_TESTS=OFF
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DARIBCC_USE_FREETYPE=ON
        -DARIBCC_USE_EMBEDDED_FREETYPE=OFF
        -DARIBCC_USE_FONTCONFIG=ON
        -DARIBCC_USE_DIRECTWRITE=ON
        -DARIBCC_USE_GDI_FONT=OFF
        -DARIBCC_NO_RENDERER=OFF
        -DARIBCC_NO_RTTI=OFF
        -DARIBCC_NO_EXCEPTIONS=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -DHAVE_OPENSSL=1" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -DHAVE_OPENSSL=1" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/libaribcaption.pc"
    if [ -f "$PC_FILE" ]; then
        # Вырезаем абсолютный путь к libstdc++.a
        sed -i "s|/opt/ct-ng/[^ ]*libstdc++.a||g" "$PC_FILE"
        # Добавляем необходимые зависимости, если их там нет
        sed -i "/^Libs.private:/ s/$/ -lstdc++ -lcrypto/" "$PC_FILE"
        sed -i 's| -I${includedir}| -I${includedir} -I${includedir}/aribcaption|g' "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libaribcaption
}

ffbuild_unconfigure() {
    echo --disable-libaribcaption
}
