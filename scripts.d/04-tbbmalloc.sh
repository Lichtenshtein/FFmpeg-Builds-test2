#!/bin/bash

SCRIPT_REPO="https://github.com/uxlfoundation/oneTBB.git"
SCRIPT_COMMIT="49c45b1bcbfd4061e199d68044289b88be2e319d"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DTBB_TEST=OFF
        -DTBB_EXAMPLES=OFF
        -DTBB_STRICT=OFF
        -DTBB_NO_APPCONTAINER=ON
        -DTBB4PY_BUILD=OFF
        -DTBB_BUILD=ON
        -DTBBMALLOC_BUILD=ON
        # -DTBBMALLOC_PROXY_BUILD=ON
        -DTBB_INSTALL=ON
        -DTBB_DISABLE_HWLOC_AUTOMATIC_SEARCH=ON
        # Если при сборке самого FFmpeg возникнут ошибки "undefined reference
        # -DTBB_USE_DEBUG_BUILD_FLAGS=OFF
    )

    if [[ "$USE_LTO" == "1" ]]; then
        myconf+=( -DTBB_ENABLE_IPO=ON )
    else
        myconf+=( -DTBB_ENABLE_IPO=OFF )
    fi

    # oneTBB иногда игнорирует стандартные CFLAGS, прокидываем их через CMAKE
    cmake -G Ninja "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS $CPPFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS $CPPFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Создаем симлинки для совместимости, если их нет
    ln -s libtbb12.a "${INSTALL_ROOT}/lib/libtbb.a" || true
    # Если tbbmalloc тоже имеет суффикс
    if [ -f "${INSTALL_ROOT}/lib/libtbbmalloc12.a" ]; then
        ln -s libtbbmalloc12.a "${INSTALL_ROOT}/lib/libtbbmalloc.a" || true
    fi
}

ffbuild_libs() {
    echo "-ltbb -ltbb12 -ltbbmalloc"
}
