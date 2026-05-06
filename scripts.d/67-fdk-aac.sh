#!/bin/bash

SCRIPT_REPO="https://github.com/mstorsjo/fdk-aac.git"
SCRIPT_COMMIT="d8e6b1a3aa606c450241632b64b703f21ea31ce3"

ffbuild_enabled() {
    [[ $VARIANT == nonfree* ]] || return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p _build && cd _build

    # Флаги санитайзера замедляют работу ffmpeg в 2-3 раза (плохо)
    # Без части из них ffmpeg не слинкуется, нужно прокидывать и для него (плохо)
    # -fno-sanitize-recover=all при малейшей ошибке в fdk-aac FFmpeg мгновенно завершит работу без шанса на продолжение (плохо)
    # если оставить только -fsanitize=undefined (UBSan), то это даёт гораздо меньше оверхеда, чем address. Но это все равно замедляет работу, хоть и не в 3 раза (плохо)
    # Я не помню нахера это тут (хорошо)
    # Итог: Вырубаем.
    ASAN_CFLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize=shift-base -fno-sanitize-recover=all"
    ASAN_LDFLAGS="-fsanitize=address,undefined"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_PROGRAMS=OFF
        -DFDK_AAC_INSTALL_CMAKE_CONFIG_MODULE=ON
        -DFDK_AAC_INSTALL_PKGCONFIG_MODULE=ON # Install pkg-config .pc file
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

# Comment out; we will handle this directly in build.sh to avoid the deduplication process (not).

# ffbuild_cflags() {
    # echo "$ASAN_CFLAGS"
# }

# ffbuild_cxxflags() {
    # echo "$ASAN_CFLAGS"
# } 

# ffbuild_ldflags() {
    # echo "$ASAN_LDFLAGS"
# }

# ffbuild_libs() {
    # echo "-lasan"
# }

ffbuild_configure() {
    echo --enable-libfdk-aac
}

ffbuild_unconfigure() {
    echo --disable-libfdk-aac
}
