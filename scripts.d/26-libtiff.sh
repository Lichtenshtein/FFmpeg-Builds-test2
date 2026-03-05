#!/bin/bash

SCRIPT_REPO="https://github.com/libsdl-org/libtiff.git"
SCRIPT_COMMIT="f324415f50cb5c90f7712e9dfe69831f5d2ea88d"

ffbuild_depends() {
    echo zlib
    echo xz
    echo libjpeg-turbo
    echo jbigkit
    echo zstd
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    apply_patches

    mkdir tiff_build && cd tiff_build

    local TIFF_DEPS="-ljpeg -lturbojpeg -ljbig -ljbig85 -lzstd -llzma -lz"

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
        -Djbig=ON
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON )

    cmake "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS -DLIBTIFF_STATIC" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS -DLIBTIFF_STATIC" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    clean_la_files

    # Исправляем .pc файл
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libtiff-4.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "${SYNC_MARK} Patching libtiff-4.pc for Leptonica..."
        # Гарантируем макрос статики и полный список либ
        sed -i "/^Cflags:/ s/$/ -DLIBTIFF_STATIC/" "$PC_FILE"
        sed -i "s|^Libs.private:.*|Libs.private: $TIFF_DEPS $LIBS|" "$PC_FILE"
    fi

    # проверить, как называется созданный .pc файл (обычно libtiff-4.pc). Если lcms2 или leptonica его не видят придется сделать симлинк:
    ln -sf libtiff-4.pc "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/tiff.pc"

    get_deps_list
}

ffbuild_cppflags() {
    echo "-DLIBTIFF_STATIC"
}
