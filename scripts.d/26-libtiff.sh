#!/bin/bash

SCRIPT_REPO="https://github.com/libsdl-org/libtiff.git"
SCRIPT_COMMIT="f324415f50cb5c90f7712e9dfe69831f5d2ea88d"

ffbuild_depends() {
    echo zlib
    echo xz
    echo libjpeg-turbo
    echo jbigkit
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/libtiff" ]]; then
        for patch in /builder/patches/libtiff/*.patch; do
            log_info "APPLYING PATCH: $patch"
            if patch -p1 -N -r - < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                # return 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    rm -rf tiff_build
    mkdir tiff_build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -Dtiff-static=ON
        -Dtiff-tools=OFF
        -Dtiff-tests=OFF
        -Dtiff-docs=OFF
        -Dtiff-opengl=ON
        -Djpeg=ON
        -Dzstd=ON
        -Dzlib=ON
        -Dlzma=ON
        -Dwebp=OFF
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON )

    cmake "${myconf[@]}" -DCMAKE_C_FLAGS="$CFLAGS" -S . -B tiff_build
    make -C tiff_build -j$(nproc) $MAKE_V
    make -C tiff_build install DESTDIR="$FFBUILD_DESTDIR"

    # проверить, как называется созданный .pc файл (обычно libtiff-4.pc). Если lcms2 или leptonica его не видят придется сделать симлинк:
    ln -sf libtiff-4.pc "$FFBUILD_DESTPREFIX"/lib/pkgconfig/tiff.pc

    log_info "################################################################"
    log_debug "Dependencies for $STAGENAME: ${0##*/}"
    # Показываем все сгенерированные .pc файлы и их зависимости
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig" -name "*.pc" -exec echo "--- {} ---" \; -exec cat {} \;
    # Показываем внешние символы (Undefined) для каждой собранной .a библиотеки
    # фильтруем только те символы, которые реально ведут к другим библиотекам
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "*.a" -print0 | xargs -0 -I{} sh -c "
        echo '--- Symbols in {} ---';
        ${FFBUILD_TOOLCHAIN}-nm {} | grep ' U ' | awk '{print \$2}' | sort -u | head -n 20
    "
    log_info "################################################################"
}

ffbuild_configure() {
    return 0
}
