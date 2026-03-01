#!/bin/bash

SCRIPT_REPO="https://github.com/DanBloomberg/leptonica.git"
SCRIPT_COMMIT="d85e6c31397f13f9860b0789564d25401fec4d24"

ffbuild_depends() {
    echo zlib
    echo libpng
    echo libjpeg-turbo
    echo openjpeg
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

    # Create a helper to define missing targets that Leptonica/Tiff expect
    # This prevents the "Target JBIG::JBIG not found" error
    cat <<EOF > lept_deps.cmake
add_library(JBIG::JBIG STATIC IMPORTED)
set_target_properties(JBIG::JBIG PROPERTIES IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/libjbig.a"
    INTERFACE_INCLUDE_DIRECTORIES "$FFBUILD_PREFIX/include")

add_library(ZLIB::ZLIB STATIC IMPORTED)
set_target_properties(ZLIB::ZLIB PROPERTIES IMPORTED_LOCATION "$FFBUILD_PREFIX/lib/libz.a"
    INTERFACE_INCLUDE_DIRECTORIES "$FFBUILD_PREFIX/include")
EOF

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
        -DCMAKE_PREFIX_PATH="$FFBUILD_PREFIX"
        -DCMAKE_PROJECT_INCLUDE="${PWD}/lept_deps.cmake" # Inject our fake targets
        -DPKG_CONFIG_EXECUTABLE=$(which pkg-config)
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
        # Ensure all sub-dependencies are listed for static linking
        # libsharpyuv is needed by webp, jbig is needed by tiff
        sed -i 's/Libs.private:/Libs.private: -lshlwapi -lws2_32 -ljbig -lsharpyuv -ltiff -ljpeg -lpng16 -libwebp -lgif -llzma -lzstd -lz -lm /' "$PC_FILE"
    fi

    # Создаем симлинк, если Tesseract ищет leptonica.pc вместо lept.pc
    ln -sf lept.pc "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/leptonica.pc"

    # --- Блок автоматической отладки зависимостей ---
    log_debug "[DEBUG] Dependencies for $STAGENAME: ${0##*/}"
    # Показываем все сгенерированные .pc файлы и их зависимости
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig" -name "*.pc" -exec echo "--- {} ---" \; -exec cat {} \;
    # Показываем внешние символы (Undefined) для каждой собранной .a библиотеки
    # фильтруем только те символы, которые реально ведут к другим библиотекам
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "*.a" -print0 | xargs -0 -I{} sh -c "
        echo '--- Symbols in {} ---';
        ${FFBUILD_TOOLCHAIN}-nm {} | grep ' U ' | awk '{print \$2}' | sort -u | head -n 20
    "
}

ffbuild_configure() {
    return 0 # Сама Leptonica не добавляет флаг в ffmpeg, она нужна только для tesseract
}

ffbuild_unconfigure() {
    return 0
}
