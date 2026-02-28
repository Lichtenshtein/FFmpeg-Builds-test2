I'm using a fairly complex third-party build script that utilizes Docker, ccache and uses the shell (bash) to cross-compile FFmpeg with a large list of different components. The build is done on GitHub servers using Github actions with its workflow.yaml. The targeting platform is Win64 with Xeon E5 2690v4 cpu.

Each component is a build script in the scripts.d folder. My goal is to check each of these scripts for correct paths, commands, variables and bugs, and edit them accordingly to ensure successful compilation - first of them — and then the final FFmpeg compilation.

I'll give you an example script for libtesseract: 50-tesseract-test.sh:

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
        -DBUILD_TRAINING_TOOLS=ON
        -DCPPAN_BUILD=OFF
        -DENABLE_TERMINAL_REPORTING=OFF
        -DGRAPHICS_OPTIMIZATIONS=ON
        -DOPENMP=ON
        -DSW_BUILD=OFF
        # Явно указываем зависимости, чтобы CMake не искал системные
        -DLeptonica_DIR="$FFBUILD_PREFIX/lib/cmake/leptonica"
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
}

ffbuild_configure() {
    echo --enable-libtesseract
}

ffbuild_unconfigure() {
    echo --disable-libtesseract
}

Could you help me write some scripts for components that serve as dependencies for other components?

In total I need to write 3 scripts: for libicu, libcurl, jbigkit.

libicu
SCRIPT_REPO="https://github.com/winlibs/icu4c.git"
SCRIPT_COMMIT="25b56cd344f49183b7c20909cb0558bf81d93673"

jbigkit
SCRIPT_REPO="https://github.com/zdenop/jbigkit.git"
SCRIPT_COMMIT="4690140176ddbc3943d2b794d4b31993d7a509e1"

option(BUILD_PROGRAMS "Build programs." ON)
option(BUILD_TOOLS "Build pbm tools." ON)
chdir jbigkit
cmake -Bbuild -DCMAKE_PREFIX_PATH=%INSTALL_DIR% -DCMAKE_INSTALL_PREFIX=%INSTALL_DIR% -DBUILD_PROGRAMS=OFF -DBUILD_TOOLS=OFF -DCMAKE_WARN_DEPRECATED=OFF
cmake --build build --config Release --target install
chdir ..

libcurl