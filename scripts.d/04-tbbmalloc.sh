#!/bin/bash

SCRIPT_REPO="https://github.com/uxlfoundation/oneTBB.git"
SCRIPT_COMMIT="3436ab394421d1390e28ff36d1ef50cb87ecc6b9"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build "$PC_DIR" && cd build

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
        -DCMAKE_CXX_STANDARD=20 # Синхронизируем стандарт C++
        -DCMAKE_CXX_STANDARD_REQUIRED=ON
    )

    if [[ "$USE_LTO" == "1" ]]; then
        myconf+=( -DTBB_ENABLE_IPO=ON )
    else
        myconf+=( -DTBB_ENABLE_IPO=OFF )
    fi

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-D__TBB_DYNAMIC_LOAD_ENABLED=0"

    # oneTBB иногда игнорирует стандартные CFLAGS, прокидываем их через CMAKE
    cmake -G Ninja "${myconf[@]}" \
        -DCMAKE_C_FLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Wno-undef $static_flags" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Wno-undef $static_flags" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS ${USELTO}" \
        .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # Создаем симлинки для совместимости, если их нет
        ln -s libtbb12.a "${INSTALL_ROOT}/lib/libtbb.a" || true
        # Если tbbmalloc тоже имеет суффикс
        if [ -f "${INSTALL_ROOT}/lib/libtbbmalloc12.a" ]; then
            ln -s libtbbmalloc12.a "${INSTALL_ROOT}/lib/libtbbmalloc.a" || true
        fi
    fi

    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s|^Cflags:.*|& -I\${includedir}/oneapi $static_flags|" "$PC_FILE"
            sed -i 's/Libs.private:/& -ltbbmalloc/' "$PC_FILE"
        done
        log_info "Cflags paths have been updated."
    fi
}

# ffbuild_libs() {
    # echo "-ltbb -ltbb12 -ltbbmalloc"
# }
