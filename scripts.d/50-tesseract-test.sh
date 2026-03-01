#!/bin/bash

SCRIPT_REPO="https://github.com/tesseract-ocr/tesseract.git"
SCRIPT_COMMIT="397887939a357f166f4674bc1d66bb155795f325"

ffbuild_depends() {
    echo leptonica-test
    echo libarchive
    echo libtensorflow-test
    echo pango
    echo cairo
    echo libtiff
    echo openssl
    echo libicu
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {

    mkdir build && cd build

    # Удаляем "ядовитые" CMake-конфиги TIFF и других либ, 
    # которые заставляют линкер искать ZLIB::ZLIB
    rm -rf "$FFBUILD_PREFIX/lib/cmake/tiff"
    rm -rf "$FFBUILD_PREFIX/lib/cmake/Leptonica"
    rm -rf "$FFBUILD_PREFIX/lib/cmake/ZLIB"
    # Удаляем любые другие конфиги, которые могут просочиться
    find "$FFBUILD_PREFIX/lib/cmake" -name "*Config.cmake" -delete

    # Настройка флагов для C++17 и статики
    export CXXFLAGS="$CXXFLAGS -std=c++17 -D_WIN32"

    # Tesseract должен использовать PkgConfig со всеми зависимостями
    # и успешно пройти тест check_leptonica_tiff_support
    export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1
    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTS=OFF
        # -DBUILD_TRAINING_TOOLS=OFF
        -DBUILD_TRAINING_TOOLS=ON # Disable tools if they cause link errors
        -DCPPAN_BUILD=OFF
        -DENABLE_TERMINAL_REPORTING=OFF
        -DGRAPHICS_OPTIMIZATIONS=ON
        -DOPENMP=ON
        -DSW_BUILD=OFF
        # Явно указываем зависимости, чтобы CMake не искал системные (сломано)
        # -DLeptonica_DIR="$FFBUILD_PREFIX/lib/cmake/leptonica"
        # tell Tesseract NOT to use Leptonica's CMake files
        -DLeptonica_DIR=OFF
        -DTIFF_DIR=OFF
        -DZLIB_DIR=OFF
        # Явные пути для подстраховки (Fallbacks)
        -DTIFF_LIBRARY="$FFBUILD_PREFIX/lib/libtiff.a"
        -DTIFF_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DJPEG_LIBRARY="$FFBUILD_PREFIX/lib/libjpeg.a"
        -DZLIB_LIBRARY="$FFBUILD_PREFIX/lib/libz.a"
        -DZLIB_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DLeptonica_LIBRARIES="-lleptonica"
        # чтобы CMake не игнорировал зависимости из PkgConfig в тестах
        -DCMAKE_REQUIRED_LIBRARIES="leptonica;webp;webpmux;sharpyuv;tiff;jpeg;png16;lzma;zstd;jbig;z;shlwapi;ws2_32;m"
    )

    # Добавляем LTO если включено в workflow
    [[ "$USE_LTO" == "1" ]] && myconf+=( -DENABLE_LTO=ON )

    # Принудительно отключаем поиск Pango (если его нет), если не хотим проблем с линковкой
    # cmake "${myconf[@]}" -DLeptonica_DIR="$FFBUILD_PREFIX/lib/cmake/leptonica" ..

    # Tesseract должен найти Leptonica через pkg-config
    cmake --trace-expand --trace-redirect=cmake_trace.txt "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Корректируем tesseract.pc для статической линковки
    # используем Requires.private, чтобы pkg-config сам вытянул зависимости зависимостей
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/tesseract.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "Patching tesseract.pc for static linking..."
        # Добавляем необходимые системные либы для Windows и зависимости
        sed -i '/Libs.private:/ s/$/ -lws2_32 -lbcrypt -luser32 -ladvapi32/' "$PC_FILE"
        # Убеждаемся, что leptonica в списке зависимостей
        # FFmpeg должен знать, что tesseract требует leptonica, pango и libarchive
        if ! grep -q "Requires.private:" "$PC_FILE"; then
            echo "Requires.private: leptonica pango cairo libarchive" >> "$PC_FILE"
        else
            sed -i '/^Requires.private:/ s/$/ leptonica pango cairo libarchive/' "$PC_FILE"
        fi
    fi

    log_info "################################################################"

    # echo "--- СОДЕРЖИМОЕ linkLibs.rsp ---"
    # find . -name "linkLibs.rsp" -exec cat {} \;
    # echo "--- Ищем упоминания ZLIB::ZLIB в сгенерированных файлах ---"
    # grep -r "ZLIB::ZLIB" .
    # grep -r "JBIG::JBIG" .

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
    echo --enable-libtesseract
}

ffbuild_unconfigure() {
    echo --disable-libtesseract
}