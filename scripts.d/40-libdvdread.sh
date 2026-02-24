#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/libdvdread.git"
SCRIPT_COMMIT="e294cf7156ce8170ebb6786e21c4baf7aa5f48e4"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    # Исправляем проблему "dubious ownership" для Git
    git config --global --add safe.directory /build/40-libdvdread.sh
    # удаляем папку .git, чтобы Meson даже не пытался запускать git команды
    rm -rf .git
    # stop the static library from exporting symbols when linked into a shared lib
    sed -i 's/-DDVDREAD_API_EXPORT/-DDVDREAD_API_EXPORT_DISABLED/g' src/meson.build

    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release      # Явно указываем release, чтобы выключить дебаг-проверки
        -Ddefault_library=static
        -Dwarning_level=1        # Снижаем уровень предупреждений
        -Dwerror=false           # Гарантируем, что предупреждения не прервут билд
        -Denable_docs=false
        -Dlibdvdcss=enabled
        --cross-file=/cross.meson
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file=/cross.meson
        )
    else
        echo "Unknown target"
        return 1
    fi

    meson setup "${myconf[@]}" ..
    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install
}

ffbuild_configure() {
    echo --enable-libdvdread
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) >= 700 )) || return 0
    echo --disable-libdvdread
}
