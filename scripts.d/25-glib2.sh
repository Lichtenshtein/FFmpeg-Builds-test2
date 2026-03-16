#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/glib.git"
SCRIPT_COMMIT="2.82.4" # Стабильная ветка
# SCRIPT_COMMIT="6b11cae1b3bf3e9cff9485481dd1c0f7e806c361"

ffbuild_depends() {
    echo zlib
    echo pcre2
    echo libffi
    echo gettext
    echo libiconv
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    # Исправляем неверный инклуд sys/resource.h в cmph
    # В MinGW его нет, заменяем проверку или просто комментируем
    sed -i 's/#include <sys\/resource.h>/ \/* #include <sys\/resource.h> *\//' girepository/cmph/cmph_time.h

    # Удаляем субпроекты, которые ломают сборку
    rm -rf subprojects/sysprof subprojects/pcre2 subprojects/libffi

    cat <<EOF > glib_cross.txt
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[binaries]
# exe_wrapper = 'wine'
c = '${FFBUILD_TOOLCHAIN}-gcc'
cpp = '${FFBUILD_TOOLCHAIN}-g++'
ar = '${FFBUILD_TOOLCHAIN}-gcc-ar'
pkg-config = 'pkg-config'
strip = '${FFBUILD_TOOLCHAIN}-strip'
windres = '${FFBUILD_TOOLCHAIN}-windres'
nm = '${FFBUILD_TOOLCHAIN}-gcc-nm'
ranlib = '${FFBUILD_TOOLCHAIN}-gcc-ranlib'
nasm = '/usr/bin/nasm'

[properties]
have_c99_snprintf = true
have_c99_vsnprintf = true
has_function_printf = true
va_val_copy = true
int_res_1 = 4
int_res_2 = 8
needs_exe_wrapper = true
printf_has_glibc_res1 = true
printf_has_glibc_res2 = true
EOF

    mkdir -p _build

    # Формируем список зависимостей из вашего чит-листа
    # pcre2 требует zlib/bz2 в некоторых конфигах
    local GLIB_DEPS="-lpcre2-8 -lffi -lintl -liconv -lcharset -lz"
    local WIN_SYS_LIBS="-lws2_32 -lole32 -lshlwapi -luserenv -lsetupapi -liphlpapi -lwinmm -ldnsapi"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file glib_cross.txt
        --buildtype=release
        --default-library=static
        --wrap-mode=nodownload
        -Dtests=false
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dinstalled_tests=false
        -Dintrospection=disabled
        -Dlibmount=disabled
        # -Dnls=disabled
        -Dnls=enabled
        -Dglib_debug=disabled
        -Dman-pages=disabled
        -Dselinux=disabled
        -Dsysprof=disabled
        # Флаги компиляции
        -Dc_args="-DGLIB_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW"
        -Dcpp_args="-DGLIB_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW"
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    # Передаем линковочные флаги через meson, чтобы проверки (типа наличия функций) проходили успешно
    meson setup _build . \
        "${myconf[@]}" \
        -Dc_link_args="$LDFLAGS $GLIB_DEPS $WIN_SYS_LIBS $LIBS" \
        -Dcpp_link_args="$LDFLAGS $GLIB_DEPS $WIN_SYS_LIBS $LIBS"

    ninja -C _build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C _build install

    clean_la_files

    # Чистим мусор
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "*.dll.a" -delete || true

    log_info "${SYNC_MARK} Patching GLib .pc files for static linking..."
    
    # Основной glib-2.0.pc
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/glib-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Гарантируем макрос статики всем, кто использует glib
        sed -i "/^Cflags:/ s/$/ -DGLIB_STATIC_COMPILATION/" "$PC_FILE"
        # Прописываем жесткую статику в Libs.private
        sed -i "s|^Libs.private:.*|Libs.private: $GLIB_DEPS $WIN_SYS_LIBS $LIBS|" "$PC_FILE"
    fi

    # gthread, gobject, gio
    for pc in gthread-2.0.pc gobject-2.0.pc gio-2.0.pc; do
        local TARGET_PC="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/$pc"
        [[ -f "$TARGET_PC" ]] || continue
        sed -i "/^Cflags:/ s/$/ -DGLIB_STATIC_COMPILATION/" "$TARGET_PC"
        # Для GIO добавляем специфичные либы
        if [[ "$pc" == "gio-2.0.pc" ]]; then
            sed -i "s|^Libs.private:.*|Libs.private: -lshlwapi -ldnsapi -liphlpapi $GLIB_DEPS $WIN_SYS_LIBS $LIBS|" "$TARGET_PC"
        fi
    done

    get_deps_list
}

ffbuild_cppflags() {
    echo "-DGLIB_STATIC_COMPILATION"
}
