#!/bin/bash

SCRIPT_REPO="https://github.com/rocky/libcdio-paranoia.git"
SCRIPT_COMMIT="307fa2e43dad116b5a9ffe36424fbfd08da30a8f"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # заменяем реализацию gettime в utils.c на пустую/совместимую
    # Это уберет ошибку компиляции, так как clock_gettime больше не будет вызываться
    echo "Patching utils.c to bypass clock_gettime..."
    
    cat <<EOF > lib/cdda_interface/utils.c.patch
--- lib/cdda_interface/utils.c
+++ lib/cdda_interface/utils.c
@@ -176,11 +176,7 @@
 static void
 gettime (struct timespec *ts)
 {
-#if defined(HAVE_CLOCK_GETTIME) && defined(CLOCK_MONOTONIC)
-  static clockid_t clock = (clockid_t)-1;
-  if ((int)clock == -1) clock = (clock_gettime(CLOCK_MONOTONIC, ts) < 0 ? CLOCK_REALTIME : CLOCK_MONOTONIC);
-  clock_gettime(clock, ts);
-#elif defined(HAVE_GETTIMEOFDAY)
+#if defined(HAVE_GETTIMEOFDAY)
   struct timeval tv;
   gettimeofday (&tv, NULL);
   ts->tv_sec = tv.tv_sec;
EOF
    patch -p0 < lib/cdda_interface/utils.c.patch

    autoreconf -if

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-example-progs
        --disable-maintainer-mode
        --enable-cpp-progs=no
        --with-pic
        ac_cv_func_clock_gettime=no
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

}

ffbuild_configure() {
    echo --enable-libcdio
}

ffbuild_unconfigure() {
    echo --disable-libcdio
}
