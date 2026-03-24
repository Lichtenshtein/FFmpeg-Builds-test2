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
    find "$PC_DIR" -name "*.pc" -exec sed -i 's/-lWs2_32/-lws2_32/g; s/-lWinmm/-lwinmm/g' {} +

    # Удаляем "ядовитые" CMake-конфиги TIFF и других либ, 
    # которые заставляют линкер искать ZLIB::ZLIB
    # rm -rf "$FFBUILD_PREFIX/lib/cmake"/{Leptonica,tiff,ZLIB,libarchive,LibXml2}
    # Удаляем любые другие конфиги, которые могут просочиться
    # find "$FFBUILD_PREFIX/lib/cmake" -name "*Config.cmake" -delete

    local TESS_LEPT="-lleptonica -lpangocairo-1.0 -lpangowin32-1.0 -lpangoft2-1.0 -lpango-1.0 -lcairo-gobject -lharfbuzz-icu -lharfbuzz-subset -lharfbuzz-cairo -lcairo"
    local NET_ARCHIVE="-larchive -lcurl -lssh -lssl -lcrypto"
    local IMAGES="-llcms2_fast_float -llcms2_threaded -llcms2 -ltiffxx -ltiff -lopenjp2 -lturbojpeg -ljpeg -lpng16 -lgif -lwebpmux -lwebpdemux -lwebp -lwebpdecoder -lsharpyuv"
    local FONT_GLIB="-lharfbuzz-vector -lharfbuzz-raster -lharfbuzz -lfontconfig -lfreetype -lpixman-1 -lfribidi -lgio-2.0 -lgthread-2.0 -lglib-2.0"
    local LOW_LEVEL="-lxml2 -lpcre2-posix -lpcre2-8 -lffi -ljbig -lzstd -llzma -lbrotlienc -lbrotlidec -lbrotlicommon -lbz2 -lz -lintl -liconv -lcharset -lsicuin -lsicuuc -lsicudt"

    # Системные либы Windows (повторяем ws2_32 для curl)
    local WIN_SYS="-luserenv -lcrypt32 -lnormaliz -luuid -lruntimeobject -lgdi32 -lusp10 -lsetupapi -lole32 -lshlwapi -luser32 -ladvapi32 -ldbghelp -lws2_32 -lwinmm -lbcrypt"

    # Склеиваем всё в ОДНУ огромную группу
    local FINAL_LIBS="-Wl,--start-group $TESS_LEPT $NET_ARCHIVE $IMAGES $FONT_GLIB $LOW_LEVEL $WIN_SYS -Wl,--end-group -lstdc++"

    local LAYER_WIN_FINAL="-lws2_32 -lbcrypt -lcrypt32 -lole32 -luser32 -ladvapi32 -lstdc++"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTS=OFF
        -DBUILD_TRAINING_TOOLS=OFF
        # -DBUILD_TRAINING_TOOLS=ON # Disable tools if they cause link errors
        # -DOPENMP_BUILD=ON # OpenMP в статике Mingw часто дает undefined reference на GOMP
        -DOPENMP_BUILD=OFF
        -DFAST_FLOAT=ON
        -DSW_BUILD=OFF
        -DENABLE_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        # Обманываем упавший тест TIFF (чтобы он не портил логи и не сбивал CMake)
        -DLEPT_TIFF_RESULT=0 
        -DLEPT_TIFF_COMPILE_SUCCESS=ON
        # Помогаем найти зависимости через PkgConfig
        -DLeptonica_DIR=OFF
        -DCMAKE_FIND_LIBRARY_SUFFIXES=".a"
        -DPKG_CONFIG_EXECUTABLE=$(command -v pkg-config)
        # Явные пути для подстраховки (Fallbacks)
        -DTIFF_LIBRARY="$FFBUILD_PREFIX/lib/libtiff.a"
        -DTIFF_INCLUDE_DIR="$FFBUILD_PREFIX/include"
    )

    export CXXFLAGS="$CXXFLAGS -DCURL_STATICLIB -DLIBARCHIVE_STATIC -DPTW32_STATIC_LIB -Wno-narrowing"
    # Переопределяем макрос, который может заставлять систему искать dllimport
    export CPPFLAGS="$CPPFLAGS -DCURL_STATICLIB -DLIBARCHIVE_STATIC -DPTW32_STATIC_LIB -D_WINSOCKAPI_ -D_WINSOCK_DEPRECATED_NO_WARNINGS -Wno-narrowing -Wno-error=format-"

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$RAW_LDFLAGS $FINAL_LIBS $LAYER_WIN_FINAL -Wl,--allow-multiple-definition" \
    cmake "${myconf[@]}" .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/tesseract.pc"
    # if [[ -f "$PC_FILE" ]]; then
        # log_info "${SYNC_MARK} Finalizing tesseract.pc..."
        # sed -i "s|^Libs.private:.*|Libs.private: $TESS_DEPS $WIN_SYS|" "$PC_FILE"
    # fi

}

ffbuild_configure() {
    echo --enable-libtesseract
}

ffbuild_unconfigure() {
    echo --disable-libtesseract
}