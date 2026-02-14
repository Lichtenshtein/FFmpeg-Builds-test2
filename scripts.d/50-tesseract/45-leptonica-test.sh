#!/bin/bash

SCRIPT_REPO="https://github.com/DanBloomberg/leptonica.git"
SCRIPT_COMMIT="1.84.1" # Стабильная версия

ffbuild_depends() {
    echo zlib
    echo libpng
    echo libjpeg-turbo # Убедитесь, что у вас есть скрипт для jpeg (например, libjpeg-turbo)
    echo libtiff
    echo libwebp
    echo giflib
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
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
    )

    cmake "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем pkg-config для статической линковки Tesseract
    # Leptonica иногда не прописывает зависимости в Libs.private
    sed -i 's/Libs.private:/Libs.private: -lwebp -lsharpyuv -ltiff -ljpeg -lpng16 -lgif -lz -lm -lshlwapi /' "$FFBUILD_DESTPREFIX"/lib/pkgconfig/lept.pc
    
    # Создаем симлинк, если Tesseract ищет leptonica.pc вместо lept.pc
    ln -sf lept.pc "$FFBUILD_DESTPREFIX"/lib/pkgconfig/leptonica.pc
}

ffbuild_configure() {
    return 0 # Сама Leptonica не добавляет флаг в ffmpeg, она нужна только для tesseract
}

ffbuild_unconfigure() {
    return 0
}
