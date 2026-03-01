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

    # Настройка флагов для C++17 и статики
    export CXXFLAGS="$CXXFLAGS -std=c++17 -D_WIN32"

        # -DBUILD_TRAINING_TOOLS=OFF
    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTS=OFF
        -DBUILD_TRAINING_TOOLS=ON # Disable tools if they cause link errors
        -DCPPAN_BUILD=OFF
        -DENABLE_TERMINAL_REPORTING=OFF
        -DGRAPHICS_OPTIMIZATIONS=ON
        -DOPENMP=ON
        -DSW_BUILD=OFF
        # Явно указываем зависимости, чтобы CMake не искал системные
        # -DLeptonica_DIR="$FFBUILD_PREFIX/lib/cmake/leptonica"
        # tell Tesseract NOT to use Leptonica's CMake files
        -DLeptonica_DIR=OFF
        -DPKG_CONFIG_EXECUTABLE=$(which pkg-config)
    )

    # Добавляем LTO если включено в workflow
    [[ "$USE_LTO" == "1" ]] && myconf+=( -DENABLE_LTO=ON )

    # Принудительно отключаем поиск Pango, если не хотим проблем с линковкой
    # cmake "${myconf[@]}" -DLeptonica_DIR="$FFBUILD_PREFIX/lib/cmake/leptonica" ..

    # Tesseract должен найти Leptonica через pkg-config
    cmake "${myconf[@]}" \
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
    echo --enable-libtesseract
}

ffbuild_unconfigure() {
    echo --disable-libtesseract
}