#!/bin/bash

SCRIPT_REPO="https://github.com/KhronosGroup/OpenCL-Headers.git"
SCRIPT_COMMIT="6137cfbbc7938cd43069d45c622022572fb87113"

SCRIPT_REPO2="https://github.com/KhronosGroup/OpenCL-ICD-Loader.git"
SCRIPT_COMMIT2="634ef470035f3fadf46ee48fa91886f155f788f5"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" headers"
    echo "git-mini-clone \"$SCRIPT_REPO2\" \"$SCRIPT_COMMIT2\" loader"
}

ffbuild_dockerbuild() {
    mkdir -p "$FFBUILD_DESTPREFIX/include/CL"
    cp -r headers/CL/* "$FFBUILD_DESTPREFIX/include/CL/."

    cd loader
    mkdir build && cd build

    # Собираем лоадер статически
    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DOPENCL_ICD_LOADER_HEADERS_DIR="$FFBUILD_DESTPREFIX/include" \
        -DOPENCL_ICD_LOADER_BUILD_SHARED_LIBS=OFF \
        -DOPENCL_ICD_LOADER_DISABLE_OPENCLON12=ON \
        -DOPENCL_ICD_LOADER_PIC=ON \
        -DOPENCL_ICD_LOADER_BUILD_TESTING=OFF \
        -DBUILD_TESTING=OFF ..
    
    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    # Генерация .pc файла (исправлено цитирование)
    cat <<EOF > OpenCL.pc
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: OpenCL
Description: OpenCL ICD Loader
Version: 3.0
Cflags: -I\${includedir}
EOF

    if [[ $TARGET == linux* ]]; then
        echo "Libs: -L\${libdir} -lOpenCL" >> OpenCL.pc
        echo "Libs.private: -ldl" >> OpenCL.pc
    elif [[ $TARGET == win* ]]; then
        # Важно для Broadwell/Win64: форсируем статическую линку
        echo "Libs: -L\${libdir} -lOpenCL" >> OpenCL.pc
        echo "Libs.private: -lole32 -lshlwapi -lcfgmgr32" >> OpenCL.pc
    fi

    mkdir -p "$FFBUILD_DESTPREFIX/lib/pkgconfig"
    mv OpenCL.pc "$FFBUILD_DESTPREFIX/lib/pkgconfig/OpenCL.pc"
}

ffbuild_configure() {
    echo --enable-opencl
}

ffbuild_unconfigure() {
    echo --disable-opencl
}
