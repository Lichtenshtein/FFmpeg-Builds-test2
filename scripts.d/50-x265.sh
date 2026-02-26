#!/bin/bash

SCRIPT_REPO="https://bitbucket.org/multicoreware/x265_git.git"
SCRIPT_COMMIT="afa0028dda3486bce8441473c6c7b99bec2f0961"

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {

    # Определяем реальный корень исходников (там, где папка 'source')
    if [[ -d "source" ]]; then
        X265_ROOT="$PWD/source"
    elif [[ -f "CMakeLists.txt" && "$PWD" == *"/source" ]]; then
        X265_ROOT="$PWD"
        cd ..
    else
        log_error "Could not find x265 source directory"
        return 1
    fi

    # Проверяем, почему пропал .git (для логов отладки)
    if [[ ! -d ".git" ]]; then
        log_warn "DEBUG: .git directory is MISSING in $(pwd). Preservation failed?"
        # Если .git нет, создаем файл версии, чтобы CMake не падал
        echo "3.5" > "$X265_ROOT/x265_version.txt"
    else
        log_info "DEBUG: .git directory found. Version should be detected automatically."
    fi

    # Полностью вырезаем блок определения версии в CMakeLists.txt, 
    # который вызывает ошибку "list GET", если нет .git
    sed -i '/if(X265_LATEST_TAG)/,/endif(X265_LATEST_TAG)/d' "$X265_ROOT/CMakeLists.txt"
    sed -i 's/list(GET /#list(GET /g' "$X265_ROOT/CMakeLists.txt"

    # Фикс заголовка json11
    find "$X265_ROOT" -name "json11.cpp" -exec sed -i '1i#include <cstdint>' {} +

    local common_config=(
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_C_FLAGS="$CFLAGS"
        -DCMAKE_CXX_FLAGS="$CXXFLAGS"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
        -DCMAKE_BUILD_TYPE=Release
        -DENABLE_SHARED=OFF
        -DENABLE_CLI=OFF
        -DCMAKE_ASM_NASM_FLAGS=-w-macro-params-legacy
        -DENABLE_ALPHA=ON
        -DENABLE_PIC=ON
        -DX265_VERSION="3.5"
        -DX265_LATEST_TAG="3.5"
        -DX265_TAG_DISTANCE="0"
        -DCHROME_APP=OFF
        -Wno-dev
    )

    mkdir -p 8bit 10bit 12bit

    if [[ $TARGET != *32 ]]; then

        log_info "Building 12-bit x265..."
        cmake "${common_config[@]}" -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_HDR10_PLUS=ON -DMAIN12=ON -S "$X265_ROOT" -B 12bit
        make -C 12bit -j$(nproc) $MAKE_V

        log_info "Building 10-bit x265..."
        cmake "${common_config[@]}" -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_HDR10_PLUS=ON -S "$X265_ROOT" -B 10bit
        make -C 10bit -j$(nproc) $MAKE_V

        log_info "Building 8-bit x265 (combined)..."
        # Копируем либы для финальной линковки
        cp 12bit/libx265.a 8bit/libx265_main12.a
        cp 10bit/libx265.a 8bit/libx265_main10.a

        cmake "${common_config[@]}" \
            -DEXTRA_LIB="libx265_main10.a;libx265_main12.a" \
            -DLINKED_10BIT=ON -DLINKED_12BIT=ON \
            -S "$X265_ROOT" -B 8bit
        make -C 8bit -j$(nproc) $MAKE_V

        # Объединяем библиотеки через MRI скрипт для ar
        # используем кросс-архивный AR
        cd 8bit
        mv libx265.a libx265_8bit.a
        ${AR} -M <<EOF
CREATE libx265.a
ADDLIB libx265_8bit.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF
        # Возвращаемся в корень билда
        cd ..
    else
        log_info "Building 8-bit x265 (32-bit target)..."
        cmake "${common_config[@]}" -S "$X265_ROOT" -B 8bit
        make -C 8bit -j$(nproc) $MAKE_V
    fi

    # Установка из папки 8bit (которая содержит объединенную либу)
    make -C 8bit install DESTDIR="$FFBUILD_DESTDIR"

    # Гарантируем наличие pkg-config файла
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/x265.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: x265
Description: H.265/HEVC video encoder
Version: 3.5
Libs: -L\${libdir} -lx265
Libs.private: -lstdc++ -lm -lgcc -lmingwex -lmingw32 -luser32 -ladvapi32 -lshell32
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-libx265
}

ffbuild_unconfigure() {
    echo --disable-libx265
}
