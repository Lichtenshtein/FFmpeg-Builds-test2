#!/bin/bash

SCRIPT_REPO="https://bitbucket.org/multicoreware/x265_git.git"
SCRIPT_COMMIT="9e551a994f970a24f0e49bcebe3d43ef08448b01"

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return -1
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
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
    )

    sed -i '1i#include <cstdint>' source/dynamicHDR10/json11/json11.cpp

    if [[ $TARGET != *32 ]]; then
        mkdir -p 8bit 10bit 12bit
        
        # 12-bit core
        cmake "${common_config[@]}" -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_HDR10_PLUS=ON -DMAIN12=ON -S source -B 12bit
        make -C 12bit -j$(nproc)

        # 10-bit core
        cmake "${common_config[@]}" -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_HDR10_PLUS=ON -S source -B 10bit
        make -C 10bit -j$(nproc)

        # 8-bit main (linking to 10 and 12)
        # Копируем либы в корень 8bit, чтобы CMake их увидел через -DEXTRA_LIB
        cp 12bit/libx265.a 8bit/libx265_main12.a
        cp 10bit/libx265.a 8bit/libx265_main10.a
        
        cmake "${common_config[@]}" \
            -DEXTRA_LIB="libx265_main10.a;libx265_main12.a" \
            -DLINKED_10BIT=ON -DLINKED_12BIT=ON \
            -S source -B 8bit
        make -C 8bit -j$(nproc)

        # Объединяем в финальную либу
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
    else
        mkdir 8bit
        cd 8bit
        cmake "${common_config[@]}" ../source
        make -j$(nproc)
    fi

    make install DESTDIR="$FFBUILD_DESTDIR"

    echo "Libs.private: -lstdc++" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/x265.pc
}

ffbuild_configure() {
    echo --enable-libx265
}

ffbuild_unconfigure() {
    echo --disable-libx265
}

ffbuild_cflags() {
    return 0
}

ffbuild_ldflags() {
    return 0
}
