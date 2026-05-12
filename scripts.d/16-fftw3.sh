#!/bin/bash

SCRIPT_REPO="https://github.com/FFTW/fftw3.git"
SCRIPT_COMMIT="6c8f5c3e620ebc38262cd80ca6f65e9f85783d9e"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Исправление для ocaml/genfft
    if [ -f genfft/Makefile.am ]; then
        sed -i 's/-libs nums/-use-ocamlfind -package num/' genfft/Makefile.am
    fi
    sed -i 's/windows.h/process.h/' configure.ac

    local base_conf=(
        --prefix="$FFBUILD_PREFIX"
        --enable-maintainer-mode
        --disable-fortran
        --disable-doc
    )

    # --with-combined-threads incompatible with --enable-openmp
    [[ "${USE_OPENMP}" == "1" ]] && \
        base_conf+=( --enable-openmp ) || \
        base_conf+=( --enable-threads --with-combined-threads )
    [[ "${PREFER_SHARED}" == "1" ]] && \
        base_conf+=( --disable-static --enable-shared ) || \
        base_conf+=( --enable-static --disable-shared )
    [[ "$USE_AVX512" == "1" ]] && base_conf+=( --enable-avx512 )

    if [[ $TARGET != *arm64 ]]; then
        base_conf+=(
            --with-incoming-stack-boundary=4
            --enable-sse2
            --enable-avx
            --enable-avx2
            --enable-fma
        )
    fi
    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        base_conf+=(
            --host="$FFBUILD_TOOLCHAIN"
            # гарантирует выравнивание памяти по границе 16/32 байта
            --with-our-malloc
        )
    fi

    # Запуск автогенерации скриптов (один раз)
    ./bootstrap.sh

    # Список точностей: "double" (стандарт) и "float" (одинарная)
    # FFTW для float требует флаг --enable-single
    for precision in double float; do
        local myconf=("${base_conf[@]}")

        if [[ "$precision" == "float" ]]; then
            myconf+=( --enable-single )
            log_info "Building FFTW3 in FLOAT precision..."
        else
            log_info "Building FFTW3 in DOUBLE precision..."
        fi

        # Чистим перед пересборкой другой точности
        make distclean || true

        CFLAGS="$CFLAGS -mincoming-stack-boundary=4 ${OPENMP_C}${USELTO}${USELTO_C}" \
        CPPFLAGS="$CPPFLAGS" \
        CXXFLAGS="$CXXFLAGS ${OPENMP_C}${USELTO}${USELTO_C}" \
        LDFLAGS="$LDFLAGS ${USELTO}" \
        LIBS="${OPENMP_LIB}$LIBS" \
        ./configure "${myconf[@]}" || return 1

        make -j$(nproc) $MAKE_V || return 1
        make install DESTDIR="$FFBUILD_DESTDIR" || return 1
    done
}

# ffbuild_libs() {
    # echo "-lfftw3 -lfftw3f"
# }
