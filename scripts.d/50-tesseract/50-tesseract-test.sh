#!/bin/bash

SCRIPT_REPO="https://github.com/tesseract-ocr/tesseract.git"
SCRIPT_COMMIT="6e1d56a847e697de07b38619356550e5cf4e8633"

ffbuild_depends() {
    echo leptonica # Tesseract не живет без Leptonica
    # echo libarchive
    echo pango # Если нужен качественный рендеринг текста
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    # Tesseract требует C++17 и выше
    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DENABLE_TERMINAL_REPORTING=OFF
        -DOPENMP=ON
        -DCPPAN_BUILD=OFF
        -DGRAPHICS_OPTIMIZATIONS=ON
        -DSW_BUILD=OFF
        -DBUILD_TRAINING_TOOLS=OFF
        -DENABLE_LTO=ON
    )

    # Принудительно отключаем поиск Pango, если не хотим проблем с линковкой
    # cmake "${myconf[@]}" -DLeptonica_DIR="$FFBUILD_PREFIX/lib/cmake/leptonica" ..

    cmake "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем pkg-config для статической линковки в FFmpeg
    # Tesseract часто забывает прописать зависимости leptonica в Requires.private
    if ! grep -q "leptonica" "$FFBUILD_DESTPREFIX"/lib/pkgconfig/tesseract.pc; then
        sed -i 's/Libs.private:/& -lleptonica -larchive -lpng16 -ljpeg -lz -lws2_32 /' "$FFBUILD_DESTPREFIX"/lib/pkgconfig/tesseract.pc
    fi
}

ffbuild_configure() {
    echo --enable-libtesseract
}

ffbuild_unconfigure() {
    echo --disable-libtesseract
}
