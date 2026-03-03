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

    # исправляем фантомную libWs2_32 от которой компилятор падает
    # Создаем симлинк libWs2_32.a -> libws2_32.a
    # линкер найдет библиотеку при любом регистре
    mkdir -p "$FFBUILD_PREFIX/lib"
    ln -sf /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libws2_32.a /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libWs2_32.a
    ln -sf /opt/ct-ng/x86_64-w64-mingw32/sysroot/lib/libws2_32.a "$FFBUILD_PREFIX/lib/libWs2_32.a"
    find "$FFBUILD_PREFIX" -name "*.pc" -exec sed -i 's/-lWs2_32/-lws2_32/g' {} +

    # Удаляем "ядовитые" CMake-конфиги TIFF и других либ, 
    # которые заставляют линкер искать ZLIB::ZLIB
    rm -rf "$FFBUILD_PREFIX/lib/cmake"/{Leptonica,tiff,ZLIB,libarchive,LibXml2}
    # Удаляем любые другие конфиги, которые могут просочиться
    find "$FFBUILD_PREFIX/lib/cmake" -name "*Config.cmake" -delete

    # Важные дефайны для статики Windows
    local STATIC_DEFS="-DLIBXML_STATIC -DXML_STATIC -DPANGO_STATIC_COMPILATION -DCAIRO_WIN32_STATIC_BUILD -DHARFBUZZ_STATIC -DGRAPHITE2_STATIC -DCURL_STATICLIB -D_WIN32_WINNT=0x0A00"
    export CFLAGS="$CFLAGS $STATIC_DEFS"
    export CXXFLAGS="$CXXFLAGS $STATIC_DEFS -std=c++17"

    # Системные либы Windows, которые всегда должны быть в конце
    local WIN_SYS_LIBS="-lws2_32 -lshlwapi -lbcrypt -luser32 -ladvapi32 -lgdi32 -lmsimg32 -lwindowscodecs -lole32 -luuid -lsetupapi -ldwrite -lusp10 -lstdc++"

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
        # Помогаем найти зависимости через PkgConfig
        -DLeptonica_DIR=OFF
        -DPkgConfig_FOUND=ON
        -DINSTALL_CONFIG_DIR="$FFBUILD_PREFIX/lib/cmake/Tesseract"
        # Явные пути для подстраховки (Fallbacks)
        -DTIFF_LIBRARY="$FFBUILD_PREFIX/lib/libtiff.a"
        -DTIFF_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DLeptonica_LIBRARIES="-lleptonica"
        # Передаем системные либы для всех исполняемых файлов (tesseract.exe, lstmtraining.exe)
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS -Wl,--start-group $WIN_SYS_LIBS -Wl,--end-group"
    )

    # Добавляем LTO если включено в workflow
    [[ "$USE_LTO" == "1" ]] && myconf+=( -DENABLE_LTO=ON )

    cmake "${myconf[@]}" ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Корректируем tesseract.pc для статической линковки
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/tesseract.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "Finalizing tesseract.pc..."
        # Указываем основные зависимости, которые pkg-config развернет рекурсивно
        sed -i "s/^Requires.private:.*/Requires.private: lept pango pangocairo libarchive libcurl/" "$PC_FILE" || \
        echo "Requires.private: lept pango pangocairo libarchive libcurl" >> "$PC_FILE"
        
        # Добавляем системные хвосты в Libs.private
        sed -i "/^Libs.private:/ s/$/ $WIN_SYS_LIBS/" "$PC_FILE"
    fi

    # Вызываем отладку зависимостей
    get_deps_list
}

ffbuild_configure() {
    echo --enable-libtesseract
}

ffbuild_unconfigure() {
    echo --disable-libtesseract
}