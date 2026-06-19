#!/bin/bash

SCRIPT_REPO="https://mirror.yandex.ru/mirrors/msys2/mingw/ucrt64/mingw-w64-ucrt-x86_64-python-pytorch-2.12.0-4-any.pkg.tar.zst"

export SKIP_POST_PC_PATCH=1

ffbuild_depends() {
    echo openssl
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "download_file \"$SCRIPT_REPO\" \"pytorch.tar.zst\""
    echo "mkdir -p extracted"
    echo "tar --use-compress-program=unzstd -xf pytorch.tar.zst -C extracted/ \
        --wildcards \
        \"*/site-packages/torch/include*\" \
        \"*/site-packages/torch/lib*\" "
    echo "mv extracted/ucrt64/lib/python*/site-packages/torch/include ."
    echo "mv extracted/ucrt64/lib/python*/site-packages/torch/lib ."
    echo "rm -rf pytorch.tar.zst extracted"
}

ffbuild_dockerbuild() {
    set -e

    log_info "Preparing LibTorch headers for GCC 15 compatibility..."

    # Прописываем базовые типы в заголовки C10/Torch, чтобы GCC 15 не падал на uint64_t или std::string
    find include/ -name "*.h" -o -name "*.hpp" -exec sed -i '1i #include <cstdint>\n#include <string>\n#include <stdexcept>' {} + 2>/dev/null || true

    # Гарантируем структуру папок в префиксе
    mkdir -p "${INSTALL_ROOT}"/{include,lib,bin}

    # Раскладываем заголовочные файлы
    cp -rf include/* "${INSTALL_ROOT}/include/"

    log_info "Distributing LibTorch libraries..."
    # Копируем динамические .dll (они уйдут в финальный дистрибутив ffmpeg)
    cp -fv lib/*.dll "${INSTALL_ROOT}/bin/" 2>/dev/null || true

    # Копируем библиотеки импорта. 
    # В MSYS2 они называются *.dll.a, копируем их с переименованием в lib*.a, 
    # чтобы ваш пайплайн и конфигуратор FFmpeg сочли их за статические доноры.
    for libfile in lib/*.dll.a; do
        if [[ -f "$libfile" ]]; then
            local name=$(basename "$libfile" .dll.a)
            cp -fv "$libfile" "${INSTALL_ROOT}/lib/${name}.a"
        fi
    done

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/libtorch.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: LibTorch
Description: PyTorch C++ API (MSYS2 MinGW-w64 Build)
Version: 2.12.0
Libs: -L\${libdir} -llibtorch -llibtorch_cpu -llibc10
Libs.private: -lshlwapi -lws2_32 -lstdc++
Cflags: -I\${includedir} -I\${includedir}/torch/csrc/api/include -DNOMINMAX -DNDEBUG
EOF
}

ffbuild_cxxflags() {
    echo "-Wno-deprecated-declarations -Wno-error=deprecated-declarations -fpermissive -I$FFBUILD_PREFIX/include/torch/csrc/api/include -I$FFBUILD_PREFIX/include/torch/csrc/jit -DNOMINMAX -DNDEBUG"
}

ffbuild_configure() {
    echo --enable-libtorch
}

ffbuild_unconfigure() {
    echo --disable-libtorch
}
