#!/bin/bash

SCRIPT_REPO="https://github.com/mingw-w64/mingw-w64.git"
SCRIPT_COMMIT="fb2acd7c624b586cd5ed3397d7b82fc18eb6ec80"

ffbuild_enabled() {
    [[ $TARGET == win* ]] || return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Use the toolchain's internal sysroot as the target, but install to a temp dir first
    local SYSROOT=$(${CC} -print-sysroot)

    unset CC CXX LD AR CPP LIBS CCAS
    # unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS CCASFLAGS
    unset PKG_CONFIG_LIBDIR

    # Force use of cross-tools
    export CC="${CC}"
    export CXX="${CXX}"

    local CRT_CFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -pipe -g0 -fno-lto"

    # 1. Headers
    cd mingw-w64-headers
        CFLAGS="" CPPFLAGS="" ./configure \
          --prefix="$SYSROOT" \
          --host="$FFBUILD_TOOLCHAIN" \
          --with-default-win32-winnt="0x0A00" \
          --with-default-msvcrt=ucrt \
          --enable-idl \
          --enable-sdk=all || return 1
        make install DESTDIR="/opt/mingw" || return 1
        # Copy from DESTDIR to the actual SYSROOT of the toolchain
        cp -a /opt/mingw/"$SYSROOT"/. "$SYSROOT/"
    cd ..

    # 2. CRT
    cd mingw-w64-crt
        export AR="${AR}"
        export NM="${NM}"
        export RANLIB="${RANLIB}"
        local CLEAN_CPPFLAGS=$(echo "$BASE_CPPFLAGS" | sed 's/-D__USE_MINGW_ANSI_STDIO=1//g')

        CFLAGS="$CRT_CFLAGS" CPPFLAGS="$CLEAN_CPPFLAGS" ./configure \
          --prefix="$SYSROOT" \
          --host="$FFBUILD_TOOLCHAIN" \
          --with-default-msvcrt=ucrt \
          --enable-wildcard \
          --disable-lib32 \
          --enable-lib64 || return 1
        make -j$(nproc) $MAKE_V || return 1
        make install DESTDIR="/opt/mingw" || return 1
        # Copy from DESTDIR to the actual SYSROOT of the toolchain
        cp -a /opt/mingw/"$SYSROOT"/. "$SYSROOT/"
    cd ..

    # 3. Winpthreads
    cd mingw-w64-libraries/winpthreads
        if [[ "$USE_LTO" == "1" ]]; then
            local PTHREAD_CFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -pipe -g0 ${USELTO}${USELTO_C}"
        else
            local PTHREAD_CFLAGS="$CRT_CFLAGS"
        fi

        CFLAGS="$PTHREAD_CFLAGS" CPPFLAGS="$CLEAN_CPPFLAGS -D_WIN32_WINNT=0x0A00" ./configure \
          --prefix="$SYSROOT" \
          --host="$FFBUILD_TOOLCHAIN" \
          --with-pic \
          --enable-$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static) \
          --disable-$([ "${PREFER_SHARED}" == "1" ] && echo static || echo shared) || return 1
        make -j$(nproc) $MAKE_V || return 1
        make install DESTDIR="/opt/mingw" || return 1
        cp -a /opt/mingw/"$SYSROOT"/. "$SYSROOT/"

        # Create the necessary directories in persistent storage
        mkdir -p "$INSTALL_ROOT/include" "$INSTALL_ROOT/lib"

        # Copy headers and libraries to the external ffbuild prefix for ffmpeg
        cp -a "$SYSROOT/include/pthread"* "$INSTALL_ROOT/include/"
        cp -a "$SYSROOT/include/sched.h" "$INSTALL_ROOT/include/"

    cd ../..

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # Copy libwinpthread.a and create an alias libpthread.a
        cp -a "$SYSROOT/lib/libwinpthread.${lib_ext}" "$INSTALL_ROOT/lib/"
        ln -sf libwinpthread.${lib_ext} "$INSTALL_ROOT/lib/libpthread.${lib_ext}"

        log_info "Isolating compiler runtime static libraries for FFmpeg..."
        # Finding where the static libssp.a is hidden in the depths of ct-ng GCC
        local COMPILER_LIB_DIR=$(${CC} -print-file-name=libssp.${lib_ext})
        if [ -f "$COMPILER_LIB_DIR" ]; then
            local COMPILER_DIR=$(dirname "$COMPILER_LIB_DIR")
            log_info "Found compiler runtime directory at: ${COMPILER_DIR}"
            # Copying ssp statics to the external ffbuild prefix
            cp -a "${COMPILER_DIR}/libssp.${lib_ext}" "$INSTALL_ROOT/lib/"
            cp -a "${COMPILER_DIR}/libssp_nonshared.${lib_ext}" "$INSTALL_ROOT/lib/" 2>/dev/null || true
            if [ -f "${COMPILER_DIR}/libatomic.${lib_ext}" ]; then
                cp -a "${COMPILER_DIR}/libatomic.${lib_ext}" "$INSTALL_ROOT/lib/"
            fi
        else
            log_warn "Could not pinpoint libssp.${lib_ext} path via GCC wrapper."
        fi

        # There should be no copies in the sysroot that interfere with linking
        log_info "Purging conflicting runtime DLL references from target folders..."
        # Remove random .dll winpthread/ssp from $SYSROOT/lib $INSTALL_ROOT/lib
        rm -f "$INSTALL_ROOT/lib/libwinpthread.dll.a" "$INSTALL_ROOT/lib/libwinpthread-1.dll"
        rm -f "$INSTALL_ROOT/lib/libssp.dll.a" "$INSTALL_ROOT/lib/libssp-0.dll"
        log_info "Runtime static isolation complete."
    fi
}
