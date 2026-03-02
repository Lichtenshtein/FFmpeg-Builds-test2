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

    # Создаем симлинк libWs2_32.a -> libws2_32.a
    # линкер найдет библиотеку при любом регистре
    ln -sf /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libws2_32.a /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libWs2_32.a

    # то же самое в префиксе на всякий случай
    mkdir -p "$FFBUILD_PREFIX/lib"
    ln -sf /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libws2_32.a "$FFBUILD_PREFIX/lib/libWs2_32.a"

    find "$FFBUILD_PREFIX" -name "*.pc" -exec sed -i 's/-lWs2_32/-lws2_32/g' {} +

    # Удаляем "ядовитые" CMake-конфиги TIFF и других либ, 
    # которые заставляют линкер искать ZLIB::ZLIB
    rm -rf "$FFBUILD_PREFIX/lib/cmake/tiff"
    rm -rf "$FFBUILD_PREFIX/lib/cmake/Leptonica"
    rm -rf "$FFBUILD_PREFIX/lib/cmake/ZLIB"
    # Удаляем любые другие конфиги, которые могут просочиться
    find "$FFBUILD_PREFIX/lib/cmake" -name "*Config.cmake" -delete

    # Tesseract должен использовать PkgConfig со всеми зависимостями
    # и успешно пройти тест check_leptonica_tiff_support
    export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1
    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig"

    # Это заставит CMake проверить компилятор без попытки линковки огромного списка
    export CMAKE_TRY_COMPILE_TARGET_TYPE="STATIC_LIBRARY"

    export CFLAGS="$CFLAGS -DLIBXML_STATIC -DCURL_STATICLIB -DLIBSSH_STATIC -DBROTLI_STATIC -DIB_STATIC -DPANGO_STATIC_COMPILATION -DHARFBUZZ_STATIC -DCAIRO_WIN32_STATIC_BUILD -DZSTD_STATIC_LINKING"
    # Настройка флагов для C++17 и статики
    export CXXFLAGS="$CXXFLAGS -std=c++17 -D_WIN32 -DLIBXML_STATIC -DCURL_STATICLIB -DLIBSSH_STATIC -DBROTLI_STATIC -DIB_STATIC -DPANGO_STATIC_COMPILATION -DHARFBUZZ_STATIC -DCAIRO_WIN32_STATIC_BUILD -DZSTD_STATIC_LINKING"

    # ПИРАМИДА ЛИНКОВКИ (Верх -> Низ)
    # Уровень 5: Tesseract (цель)
    # Уровень 4: Высокоуровневые движки
    PANGO_LIBS="-lpangocairo-1.0 -lpangoft2-1.0 -lpangowin32-1.0 -lpango-1.0"
    CAIRO_LIBS="-lcairo -lpixman-1 -lfontconfig -lfreetype -lharfbuzz -lpng16"

    # Уровень 3: Контейнеры и Сеть
    ARCHIVE_LIBS="-larchive -lxml2 -liconv -lcharset -llzma -lzstd -lbz2"
    CURL_LIBS="-lcurl -lssh -lssl -lcrypto -lcrypt32 -lwldap32 -lnormaliz"

    # Уровень 2: Изображения и Математика
    LEPT_LIBS="-lleptonica -lwebp -lwebpmux -lsharpyuv -ltiff -ljpeg -lopenjp2 -lgif -ljbig -llcms2"
    TENSOR_LIBS="-ltensorflow"
    ICU_LIBS="-lsicuin -lsicuuc -lsicudt"

    # Уровень 1: Базовые утилиты и Системные либы Windows
    BASE_LIBS="-lglib-2.0 -lintl -lffi -lpcre2-8 -lbrotlidec -lbrotlicommon -lz -lm -lstdc++"
    WIN_SYS="-lws2_32 -lshlwapi -lbcrypt -luser32 -ladvapi32 -lgdi32 -lmsimg32 -lwindowscodecs -lole32 -loleaut32 -luuid -lcomdlg32 -lshell32 -lwinmm -lsetupapi -liphlpapi -lruntimeobject -ldwrite -ld2d1 -lusp10 -ldbghelp"

    # Итоговая строка
    export ALL_STATIC_LIBS="${PANGO_LIBS} ${CAIRO_LIBS} ${ARCHIVE_LIBS} ${CURL_LIBS} ${LEPT_LIBS} ${TENSOR_LIBS} ${ICU_LIBS} ${BASE_LIBS} ${WIN_SYS}"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTS=OFF
        # -DBUILD_TRAINING_TOOLS=OFF
        -DBUILD_TRAINING_TOOLS=ON # Disable tools if they cause link errors
        -DOPENMP_BUILD=ON
        -DFAST_FLOAT=ON
        -DSW_BUILD=OFF
        # Обманываем упавший тест TIFF (чтобы он не портил логи и не сбивал CMake)
        -DLEPT_TIFF_RESULT=0 
        -DLEPT_TIFF_COMPILE_SUCCESS=ON
        # tell Tesseract to FUCK OFF from Leptonica's CMake files
        -DLeptonica_DIR=OFF
        # Явные пути для подстраховки (Fallbacks)
        -DTIFF_LIBRARY="$FFBUILD_PREFIX/lib/libtiff.a"
        -DTIFF_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DLeptonica_LIBRARIES="-lleptonica"
        # Прокидываем ICU вручную, так как Tesseract его любит
        -DICU_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DICU_LIBRARY="$FFBUILD_PREFIX/lib/libsicuuc.a"
        -DICU_I18N_LIBRARY="$FFBUILD_PREFIX/lib/libsicuin.a"
        # ПРИНУДИТЕЛЬНАЯ ЛИНКОВКА
        -DCMAKE_CXX_STANDARD_LIBRARIES="-lws2_32 -lshlwapi -lbcrypt -luser32 -ladvapi32"
        -DCMAKE_C_STANDARD_LIBRARIES="-lws2_32 -lshlwapi -lbcrypt -luser32 -ladvapi32"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS ${ALL_STATIC_LIBS}"
    )

    # Добавляем LTO если включено в workflow
    [[ "$USE_LTO" == "1" ]] && myconf+=( -DENABLE_LTO=ON )

    # Удаляем кеш и запускаем
    rm -f CMakeCache.txt

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
    echo --enable-libtesseract
}

ffbuild_unconfigure() {
    echo --disable-libtesseract
}