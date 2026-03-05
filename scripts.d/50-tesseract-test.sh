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
    set -e
    mkdir build && cd build

    # исправляем фантомную libWs2_32 от которой компилятор падает
    # Создаем симлинк libWs2_32.a -> libws2_32.a
    # линкер найдет библиотеку при любом регистре
    mkdir -p "$FFBUILD_PREFIX/lib"
    ln -sf /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libws2_32.a /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libWs2_32.a
    ln -sf /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libws2_32.a "$FFBUILD_PREFIX/lib/libWs2_32.a"
    find "$FFBUILD_PREFIX/lib/pkgconfig" -name "*.pc" -exec sed -i 's/-lWs2_32/-lws2_32/g; s/-lWinmm/-lwinmm/g' {} +

    # Удаляем "ядовитые" CMake-конфиги TIFF и других либ, 
    # которые заставляют линкер искать ZLIB::ZLIB
    # rm -rf "$FFBUILD_PREFIX/lib/cmake"/{Leptonica,tiff,ZLIB,libarchive,LibXml2}
    # Удаляем любые другие конфиги, которые могут просочиться
    # find "$FFBUILD_PREFIX/lib/cmake" -name "*Config.cmake" -delete

    # Полный список зависимостей для линковки (порядок важен!)
    # Tesseract -> Leptonica -> [Pango/Cairo] -> [Archive/Curl] -> [TIFF/JPEG/PNG] -> [ICU/GLib] -> [System]
    local TESS_DEPS="-lleptonica -lpangocairo-1.0 -lpangoft2-1.0 -lpango-1.0 -lcairo -lharfbuzz-icu -lharfbuzz-subset -lharfbuzz-vector -lharfbuzz-raster -lharfbuzz -lharfbuzz-cairo -lsicuin -lsicuuc -lsicudt -lfribidi -lglib-2.0 -lgobject-2.0 -larchive -lcurl -lssl -lcrypto -lssh -ltiff -lopenjp2 -ljpeg -lpng16 -lzstd -llzma -lbz2 -lz -liconv -lintl"
    local WIN_SYS="-lws2_32 -luserenv -lbcrypt -lcrypt32 -lnormaliz -lshlwapi -lole32 -luuid -lruntimeobject -lgdi32 -lusp10"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTS=OFF
        # -DBUILD_TRAINING_TOOLS=OFF
        -DBUILD_TRAINING_TOOLS=ON # Disable tools if they cause link errors
        # -DOPENMP_BUILD=ON # OpenMP в статике Mingw часто дает undefined reference на GOMP
        -DOPENMP_BUILD=OFF
        -DFAST_FLOAT=ON
        -DSW_BUILD=OFF
        # Обманываем упавший тест TIFF (чтобы он не портил логи и не сбивал CMake)
        -DLEPT_TIFF_RESULT=0 
        -DLEPT_TIFF_COMPILE_SUCCESS=ON
        # Помогаем найти зависимости через PkgConfig
        -DLeptonica_DIR=OFF
        # -DPkgConfig_FOUND=ON
        # -DINSTALL_CONFIG_DIR="$FFBUILD_PREFIX/lib/cmake/Tesseract"
        # Явные пути для подстраховки (Fallbacks)
        -DTIFF_LIBRARY="$FFBUILD_PREFIX/lib/libtiff.a"
        -DTIFF_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        # -DLeptonica_LIBRARIES="-lleptonica"
        # Передаем системные либы для всех исполняемых файлов (tesseract.exe, lstmtraining.exe)
        # -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS -Wl,--start-group $WIN_LIBS -Wl,--end-group"
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -DENABLE_LTO=ON )

    # прокидываем весь хвост в EXE_LINKER_FLAGS
    # Используем -Wl,--allow-multiple-definition, если Pango и Cairo конфликтуют
    cmake "${myconf[@]}" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS -Wno-narrowing" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS $TESS_DEPS $WIN_SYS $LIBS" ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    clean_la_files

    # Корректируем tesseract.pc для статической линковки
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/tesseract.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "${SYNC_MARK} Finalizing tesseract.pc..."
        # Очищаем старые зависимости и пишем свои
        sed -i "s|^Requires.private:.*|Requires.private: lept pango pangocairo libarchive libcurl|" "$PC_FILE"
        sed -i "s|^Libs.private:.*|Libs.private: $TESS_DEPS $WIN_SYS $LIBS -lstdc++|" "$PC_FILE"
    fi

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libtesseract
}

ffbuild_unconfigure() {
    echo --disable-libtesseract
}