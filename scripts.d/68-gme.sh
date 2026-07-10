#!/bin/bash

SCRIPT_REPO="https://github.com/libgme/game-music-emu.git"
SCRIPT_COMMIT="ae10a8f05479e3c8f80429e7a59759fed06f8c13"

ffbuild_depends() {
    echo zlib
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
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DGME_BUILD_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DGME_BUILD_FRAMEWORK=OFF
        -DGME_BUILD_TESTING=OFF
        -DGME_BUILD_EXAMPLES=OFF
        -DGME_SPC_ISOLATED_ECHO_BUFFER=ON
        -DGME_ZLIB=ON
        -DENABLE_UBSAN=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/libgme.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Удаляем существующую строку Libs.private целиком
        sed -i '/^[Ll]ibs\.[Pp]rivate:/d' "$PC_FILE"
        # Записываем новую чистую строку
        sed -i '/^Libs:/a Libs.private: -lssp -lmingwthrd -lgcc -lstdc++' "$PC_FILE"
        sed -i "s|^Cflags:.*|& -I\${includedir}/gme|" "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libgme
}

ffbuild_unconfigure() {
    echo --disable-libgme
}
