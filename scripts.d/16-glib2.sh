#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/glib.git"
SCRIPT_COMMIT="8ef2f3ad402daf9fb94615ddef63ceef978fd76f"

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
    echo "rm -rf docs po glib/tests gio/tests gobject/tests"
}

ffbuild_dockerbuild() {
    set -e

    # disable docs search
    sed -i '/exe_wrapper:/,/)/ s/required: true/required: false/' meson.build
    sed -i "s|subdir('docs/reference')|if get_option('documentation')\n  subdir('docs/reference')\nendif|g" meson.build
    sed -i "s|gnome = import('gnome')|# gnome = import('gnome')|g" meson.build

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # Патчим генератор макросов, убирая __attribute__ visibility
        if [ -f "tools/gen-visibility-macros.py" ]; then
            sed -i 's/visibility("default")//g' tools/gen-visibility-macros.py
            sed -i 's/visibility("hidden")//g' tools/gen-visibility-macros.py
        fi
        # Ищем по всему дереву исходников 'gnu_symbol_visibility' и удаляем эти строки
        find . -name "meson.build" -type f -exec sed -i "/gnu_symbol_visibility/d" {} +
        # Находим определение макроса во внутренних заголовочных файлах GLib и принудительно зануляем его
        find . -name "*.h" -o -name "*.h.in" -type f -exec sed -i 's/#define G_GNUC_INTERNAL.*/#define G_GNUC_INTERNAL/g' {} +
        # Принудительно гасим внутренние переменные видимости в корневом meson.build
        sed -i "s/glib_have_gnuc_visibility = .*/glib_have_gnuc_visibility = false/g" meson.build 2>/dev/null || true
        sed -i "s/have_visibility_hidden = .*/have_visibility_hidden = false/g" meson.build 2>/dev/null || true
    fi

    if [ -f "gio/meson.build" ]; then
        # Вставляем объявление деактивации в самое начало файла.
        # Переопределяем массивы исходников и зависимости в disabler().
        # Это заставит Meson штатно отключить сборку самих .exe.
        sed -i '1i \
gio_tool_sources = disabler() \
gresource_tool_sources = disabler() \
gio_querymodules_sources = disabler() \
glib_compile_schemas_sources = disabler() \
glib_compile_resources_sources = disabler() \
gsettings_tool_sources = disabler() \
gdbus_tool_sources = disabler() \
gapplication_tool_sources = disabler() \
app_profile_dep = disabler()' gio/meson.build

        # переопределяем переменные, которые используются ниже по коду
        sed -i '1i \
gio_tool = disabler() \
gresource = disabler() \
gio_querymodules = disabler() \
glib_compile_schemas = disabler() \
glib_compile_resources = disabler() \
gsettings = disabler() \
gdbus_tool = disabler() \
gapplication = disabler()' gio/meson.build

        sed -i "s/subdir('tests')/# subdir('tests')/g" gio/meson.build
    fi

    # Отключаем создание симлинков для многоархитектурных бинарников, так как они нам не нужны
    sed -i "s/if multiarch_bindir != get_option('bindir')/if false/g" gio/meson.build

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # fix visibility attribute compatibility for windows static
        sed -i '1i #define GLIB_STATIC_COMPILATION 1' glib/glibconfig.h.in 2>/dev/null || true
    fi

    # Clean legacy windows definitions
    sed -i '/#define _WIN32_WINNT 0x/d' meson.build
    sed -i '/#include <sys\/resource.h>/d' girepository/cmph/cmph_time.h 2>/dev/null || true

    # disable tests
    if [ -f "gio/tests/meson.build" ]; then echo "" > gio/tests/meson.build; fi
    if [ -f "tests/meson.build" ]; then echo "" > tests/meson.build; fi

    # Clean up sysprof and third-party fallbacks
    rm -rf subprojects/sysprof subprojects/pcre2 subprojects/libffi

    cat <<EOF > glib_cross.txt
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[binaries]
# exe_wrapper = ['wine']
c = '${FFBUILD_TOOLCHAIN}-gcc'
cpp = '${FFBUILD_TOOLCHAIN}-g++'
ar = '${FFBUILD_CROSS_PREFIX}ar'
pkg-config = 'pkgconf'
strip = '${FFBUILD_TOOLCHAIN}-strip'
windres = '${FFBUILD_TOOLCHAIN}-windres'
nm = '${FFBUILD_CROSS_PREFIX}nm'
ranlib = '${FFBUILD_CROSS_PREFIX}ranlib'
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

    # pcre2 требует zlib/bz2 в некоторых конфигах
    # local DEP_LIBS="-lpcre2-posix -lpcre2-8 -lffi -lintl -liconv -lcharset -lz"
    # local WIN_LIBS="-luserenv -liphlpapi -lwinmm -luuid -ldnsapi $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file glib_cross.txt
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --wrap-mode=nodownload
        -Dtests=false
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Dinstalled_tests=false
        -Dintrospection=disabled
        -Dlibmount=disabled
        -Dnls=disabled # po folder is deleted
        -Dforce_posix_threads=true
        -Dglib_debug=disabled
        -Dman-pages=disabled
        -Dselinux=disabled
        -Dsysprof=disabled
    )

    # Mitigate LTO compiler engine bugs inside GLib compilation 
    local lto_cflags=""
    local lto_ldflags=""
    if [[ "$USE_LTO" == "1" ]]; then
        myconf+=( -Db_lto=false ) # Keep internal meson lto safe
        lto_cflags="${NOLTO}"
        lto_ldflags="${NOLTO}"
    fi

    export static_flags=""
    export self_static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DFFI_STATIC_BUILD" && self_static_flags="-DGLIB_STATIC_COMPILATION"

    meson setup _build . \
        "${myconf[@]}" \
        -Dc_args="$CFLAGS $CPPFLAGS ${lto_cflags} $self_static_flags $static_flags -DG_WIN32_IS_STRICT_MINGW -Wno-attributes -Wno-stringop-overflow" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${lto_cflags} $self_static_flags $static_flags -DG_WIN32_IS_STRICT_MINGW -Wno-attributes -Wno-stringop-overflow" \
        -Dc_link_args="$LDFLAGS ${lto_ldflags}" \
        -Dcpp_link_args="$LDFLAGS ${lto_ldflags}" || return 1

    ninja -C _build $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja -C _build install || return 1

    local ALL_GLIB_PCS=(
        "glib-2.0.pc" "gio-2.0.pc" "gthread-2.0.pc" 
        "gobject-2.0.pc" "gmodule-2.0.pc" "gio-windows-2.0.pc" 
        "girepository-2.0.pc" "gmodule-no-export-2.0.pc" "gmodule-export-2.0.pc"
    )
    for pc_name in "${ALL_GLIB_PCS[@]}"; do
        local pc="$PC_DIR/$pc_name"
        [[ -f "$pc" ]] || continue
        if [[ -n "$self_static_flags" ]]; then
            if ! grep -qF -- "$self_static_flags" "$pc"; then
                sed -i "/^Cflags:/ s/$/ $self_static_flags/" "$pc"
            fi
        fi
    done
}
