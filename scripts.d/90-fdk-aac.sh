#!/bin/bash

SCRIPT_REPO="https://github.com/mccakit/fdk-aac.git"
SCRIPT_COMMIT="2e5642ea1e5dc4a1d2f0c2f331729acc9866caed"
SCRIPT_BRANCH="HDC-encoder-PS-patch"

ffbuild_enabled() {
    # [[ $VARIANT == nonfree* ]] || return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir _build
    cd _build

    # Флаги санитайзера замедляют работу ffmpeg в 2-3 раза (плохо)
    # Без части из них ffmpeg не слинкуется, нужно прокидывать и для него (плохо)
    # -fno-sanitize-recover=all при малейшей ошибке в fdk-aac FFmpeg мгновенно завершит работу без шанса на продолжение (плохо)
    # если оставить только -fsanitize=undefined (UBSan), то это даёт гораздо меньше оверхеда, чем address. Но это все равно замедляет работу, хоть и не в 3 раза (плохо)
    # Я не помню нахера это тут (хорошо)
    # Итог: Вырубаем.
    ASAN_CFLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize=shift-base -fno-sanitize-recover=all"
    ASAN_LDFLAGS="-fsanitize=address,undefined"

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_PROGRAMS=OFF \
        -DFDK_AAC_INSTALL_CMAKE_CONFIG_MODULE=ON \
        -DFDK_AAC_INSTALL_PKGCONFIG_MODULE=ON  .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
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
