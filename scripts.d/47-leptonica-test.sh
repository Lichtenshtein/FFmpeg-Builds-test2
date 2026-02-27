#!/bin/bash

SCRIPT_REPO="https://github.com/DanBloomberg/leptonica.git"
SCRIPT_COMMIT="d85e6c31397f13f9860b0789564d25401fec4d24"

ffbuild_depends() {
    echo zlib
    echo libpng
    echo libjpeg-turbo
    echo libtiff
    echo brotli
    echo lcms2
    echo libwebp
    echo giflib
    echo libarchive
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DSW_BUILD=OFF
        # Включаем поддержку всех форматов через системные (ffbuild) либы
        -DENABLE_PNG=ON
        -DENABLE_JPEG=ON
        -DENABLE_TIFF=ON
        -DENABLE_WEBP=ON
        -DENABLE_GIF=ON
        -DENABLE_ZLIB=ON
        -DENABLE_LIBARCHIVE=ON
    )

    # Добавляем LTO если включено в workflow
    [[ "$USE_LTO" == "1" ]] && myconf+=( -DENABLE_LTO=ON )

    cmake "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем pkg-config для статической линковки Tesseract
    # Leptonica иногда не прописывает зависимости в Libs.private
    # sed -i 's/Libs.private:/Libs.private: -lwebp -lsharpyuv -ltiff -ljpeg -lpng16 -lgif -lz -lm -lshlwapi /' "$FFBUILD_DESTPREFIX"/lib/pkgconfig/lept.pc

    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/lept.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Добавляем системные либы Windows
        sed -i 's/Libs.private:/& -lshlwapi -lws2_32 /' "$PC_FILE"
        # Указываем зависимости через Requires.private (предпочтительный способ)
        sed -i '/^Requires.private:/ s/$/ libwebp libsharpyuv libtiff-4 libpng16 zlib /' "$PC_FILE" || \
        echo "Requires.private: libwebp libsharpyuv libtiff-4 libpng16 zlib" >> "$PC_FILE"
    fi

    # Создаем симлинк, если Tesseract ищет leptonica.pc вместо lept.pc
    ln -sf lept.pc "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/leptonica.pc"
}

ffbuild_configure() {
    return 0 # Сама Leptonica не добавляет флаг в ffmpeg, она нужна только для tesseract
}

ffbuild_unconfigure() {
    return 0
}
