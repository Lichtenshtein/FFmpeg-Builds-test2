#!/bin/bash

SCRIPT_REPO="https://github.com/google/shaderc.git"
SCRIPT_COMMIT="e0a5092b4b05dbcc448b0883f3575163634f8e86"

ffbuild_enabled() {
    (( $(ffbuild_ffver) > 404 )) || return -1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "./utils/git-sync-deps || exit $?"
}

ffbuild_dockerbuild() {
# Определяем цвета и символы
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color (сброс цвета)
CHECK_MARK='✅'
CROSS_MARK='❌'
    
    if [[ -d "/builder/patches/shaderc" ]]; then
        for patch in /builder/patches/shaderc/*.patch; do
            echo -e "\n-----------------------------------"
            echo "~~~ APPLYING PATCH: $patch"
            # Выполняем патч и проверяем код выхода
            if patch -p1 < "$patch"; then
                echo -e "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
                echo "-----------------------------------"
            else
                echo -e "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                echo "-----------------------------------"
                # exit 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    mkdir build && cd build

        # -DENABLE_EXCEPTIONS=ON 
        # -DENABLE_GLSLANG_BINARIES=OFF
    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DSHADERC_SKIP_TESTS=ON \
        -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
        -DSHADERC_SKIP_EXAMPLES=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DSHADERC_ENABLE_SHARED_CRT=OFF \
        -DSPIRV_SKIP_EXECUTABLES=ON \
        -DSPIRV_TOOLS_BUILD_STATIC=ON \
        -DSPIRV_TOOLS_LIBRARY_TYPE=STATIC \
        -DGLSLANG_ENABLE_INSTALL=ON ..


    export DESTDIR="/tmp/staging$FFBUILD_DESTDIR"
    ninja install

    if [[ $TARGET == win* ]]; then
        rm -r "${DESTDIR}${FFBUILD_PREFIX}"/bin "${DESTDIR}${FFBUILD_PREFIX}"/lib/*.dll.a
    elif [[ $TARGET == linux* ]]; then
        rm -r "${DESTDIR}${FFBUILD_PREFIX}"/bin "${DESTDIR}${FFBUILD_PREFIX}"/lib/*.so*
    else
        echo "Unknown target"
        return -1
    fi

    cp -al "$DESTDIR"/. "$FFBUILD_DESTDIR"
    rm -rf "$DESTDIR"
    unset DESTDIR

    # for some reason, this does not get installed...
    cp libshaderc_util/libshaderc_util.a "$FFBUILD_DESTPREFIX"/lib

    echo "Libs: -lstdc++" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/shaderc_combined.pc
    echo "Libs: -lstdc++" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/shaderc_static.pc

    cp "$FFBUILD_DESTPREFIX"/lib/pkgconfig/{shaderc_combined,shaderc}.pc

    mkdir ../native_build && cd ../native_build

    unset CC CXX CFLAGS CXXFLAGS LD LDFLAGS AR RANLIB NM DLLTOOL PKG_CONFIG_LIBDIR
    cmake -GNinja -DCMAKE_BUILD_TYPE=Release \
        -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
        -DENABLE_EXCEPTIONS=ON -DSPIRV_TOOLS_BUILD_STATIC=ON -DBUILD_SHARED_LIBS=OFF ..
    ninja -j$(nproc) glslc/glslc

    cp glslc/glslc /opt/glslc
}

ffbuild_configure() {
    echo --enable-libshaderc
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 404 )) || return 0
    echo --disable-libshaderc
}
