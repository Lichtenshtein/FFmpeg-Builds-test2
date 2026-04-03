#!/bin/bash

SCRIPT_REPO="https://gitlab.com/damian101/aom-psy101.git"
SCRIPT_COMMIT="6a3435223b36b29e6cc9815b1f86720dcaba57f6" 

ffbuild_depends() {
    echo vmaf
    echo zlib
}

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    [[ $TARGET == winarm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir cmbuild && cd cmbuild

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DENABLE_EXAMPLES=NO
        -DENABLE_TESTS=NO
        -DENABLE_DOCS=NO
        -DENABLE_TOOLS=NO
        -DENABLE_CCACHE=ON
        -DENABLE_NASM=ON
        -DCONFIG_TUNE_VMAF=1
        -DCONFIG_AV1_DECODER=1
        -DCONFIG_AV1_ENCODER=1
        -DCONFIG_PIC=1
    )

    # Пробрасываем пути к VMAF
    # Это лечит проблемы поиска заголовков при сборке самого AOM
    CFLAGS="$CFLAGS $CPPFLAGS -pthread -I/opt/ffbuild/include/libvmaf" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake "${myconf[@]}" .. || return 1
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Добавляем VMAF в pkg-config, иначе FFmpeg не соберется статикой
    echo "Requires.private: libvmaf" >> "$PC_DIR/aom.pc"

}

ffbuild_configure() {
    echo --enable-libaom
}

ffbuild_unconfigure() {
    echo --disable-libaom
}
