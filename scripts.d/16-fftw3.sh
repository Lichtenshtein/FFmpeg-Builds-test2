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
    sed -i 's/-libs nums/-use-ocamlfind -package num/' genfft/Makefile.am

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --enable-maintainer-mode
        --disable-shared
        --enable-static
        --disable-fortran
        --disable-doc
        --with-our-malloc
        --enable-long-double
        --enable-threads
        --with-combined-threads
        --with-incoming-stack-boundary=2
    )

    # --with-combined-threads incompatible with --enable-openmp
    # [[ "$USE_OPENMP" == "1" ]] && myconf+=( --enable-openmp ) 
    [[ "$USE_AVX512" == "1" ]] && myconf+=( --enable-avx512 )

    if [[ $TARGET != *arm64 ]]; then
        myconf+=(
            --enable-sse2
            --enable-avx
            --enable-avx2
        )
    fi

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return 1
    fi

    sed -i 's/windows.h/process.h/' configure.ac

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS" \
    ./bootstrap.sh "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

}
