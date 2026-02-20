#!/bin/bash

SCRIPT_REPO="https://github.com/rocky/libcdio-paranoia.git"
SCRIPT_COMMIT="53718dbe36ee9fd42e97527188a788f2754288c0"

ffbuild_enabled() {
    return 0
}

# Сбрасываем кэш еще раз для надежности
# ffbuild_dockerdl() {
    # echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" . && echo 'v4-win32-fix'"
# }

ffbuild_dockerbuild() {
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
        --disable-shared
        --enable-static
        --disable-example-progs
        --disable-maintainer-mode
        --enable-cpp-progs=no
        --with-pic
        ac_cv_func_clock_gettime=no
    )

    ./configure "${myconf[@]}"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libcdio
}

ffbuild_unconfigure() {
    echo --disable-libcdio
}
