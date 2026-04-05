#!/bin/bash

SCRIPT_REPO="https://github.com/KhronosGroup/OpenCL-Headers.git"
SCRIPT_COMMIT="e55138572c81dce15ffe402bd1142d9652ec5cb5"

SCRIPT_REPO2="https://github.com/KhronosGroup/OpenCL-ICD-Loader.git"
SCRIPT_COMMIT2="b1c57534df7ac82519b04606f51b71fb5d4053c3"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" headers"
    echo "git-mini-clone \"$SCRIPT_REPO2\" \"$SCRIPT_COMMIT2\" loader"
}

ffbuild_dockerbuild() {
    set -e

    # Возвращаемся в реальный корень этапа, если "умный поиск" зашел в /loader
    if [[ "$(basename "$PWD")" == "loader" ]]; then
        cd ..
    fi

    # Установка хедеров
    mkdir -p "$FFBUILD_DESTPREFIX/include/CL"
    # Используем относительный путь от корня этапа
    cp -r headers/CL/* "$FFBUILD_DESTPREFIX/include/CL/."

    cd loader
    # Удаляем старый build если остался, и создаем чистый
    rm -rf build && mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        # Указываем путь к только что скопированным хедерам
        -DOPENCL_ICD_LOADER_HEADERS_DIR="$FFBUILD_DESTPREFIX/include"
        -DOPENCL_ICD_LOADER_BUILD_SHARED_LIBS=OFF
        -DOPENCL_ICD_LOADER_DISABLE_OPENCLON12=ON
        -DOPENCL_ICD_LOADER_PIC=ON
        -DOPENCL_ICD_LOADER_BUILD_TESTING=OFF
        -DOPENCL_HEADERS_BUILD_CXX_TESTS=OFF
        -DOPENCL_HEADERS_BUILD_TESTING=OFF
        -DBUILD_TESTING=OFF 
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1
    
    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/OpenCL.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: OpenCL
Description: OpenCL ICD Loader
Version: 3.0
Libs: -L\${libdir} -lOpenCL
Cflags: -I\${includedir}
EOF

    if [[ $TARGET == linux* ]]; then
        echo "Libs.private: -ldl" >> "$PC_DIR/OpenCL.pc"
    elif [[ $TARGET == win* ]]; then
        echo "Libs.private: -lole32 -lshlwapi -lcfgmgr32" >> "$PC_DIR/OpenCL.pc"
    fi

}

ffbuild_configure() {
    echo --enable-opencl
}

ffbuild_unconfigure() {
    echo --disable-opencl
}
