#!/bin/bash

SCRIPT_REPO="https://mirror.yandex.ru/mirrors/msys2/mingw/ucrt64/mingw-w64-ucrt-x86_64-python-pytorch-2.12.0-4-any.pkg.tar.zst"

# сбор сателлитных DLL
GLOG_LINK="https://mirror.yandex.ru/mirrors/msys2/mingw/ucrt64/mingw-w64-ucrt-x86_64-glog-0.7.1-10-any.pkg.tar.zst"
SLEEF_LINK="https://mirror.accum.se/mirror/msys2.org/mingw/ucrt64/mingw-w64-ucrt-x86_64-sleef-3.9.0-2-any.pkg.tar.zst"
OPENBLAS_LINK="https://mirrors.dotsrc.org/msys2/mingw/ucrt64/mingw-w64-ucrt-x86_64-openblas-0.3.33-3-any.pkg.tar.zst"
PROTOBUF_LINK="https://mirror.yandex.ru/mirrors/msys2/mingw/ucrt64/mingw-w64-ucrt-x86_64-protobuf-35.0-1-any.pkg.tar.zst"
UNWIND_LINK="https://distrohub.kyiv.ua/msys2/mingw/ucrt64/mingw-w64-ucrt-x86_64-libunwind-22.1.7-1-any.pkg.tar.zst"
ABSEIL_LINK="https://distrohub.kyiv.ua/msys2/mingw/ucrt64/mingw-w64-ucrt-x86_64-abseil-cpp-20260526.0-1-any.pkg.tar.zst"

export SKIP_POST_PC_PATCH=1

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "download_file \"$SCRIPT_REPO\" \"pytorch.tar.zst\""
    echo "mkdir -p extracted"
    echo "tar --use-compress-program=unzstd -xf pytorch.tar.zst -C extracted/ --wildcards \"*/site-packages/torch/include*\" \"*/site-packages/torch/lib*\""
    echo "mv extracted/ucrt64/lib/python*/site-packages/torch/include ."
    echo "mv extracted/ucrt64/lib/python*/site-packages/torch/lib ."
    echo "rm -rf pytorch.tar.zst extracted"

    echo "download_file \"$GLOG_LINK\" \"glog.tar.zst\""
    echo "mkdir -p extracted_glog"
    echo "tar --use-compress-program=unzstd -xf glog.tar.zst -C extracted_glog/ --wildcards \"*/include/glog*\" \"*/lib/*.a\" \"*/bin/*.dll\""
    echo "mkdir -p include/glog lib"
    echo "cp -rf extracted_glog/ucrt64/include/glog/* include/glog/"
    echo "cp -fv extracted_glog/ucrt64/lib/libglog.dll.a lib/glog.dll.a"
    echo "cp -fv extracted_glog/ucrt64/bin/libglog-2.dll lib/"
    echo "rm -rf glog.tar.zst extracted_glog"

    # --- SLEEF ---
    echo "download_file \"$SLEEF_LINK\" \"sleef.tar.zst\""
    echo "mkdir -p ext_sleef"
    echo "tar --use-compress-program=unzstd -xf sleef.tar.zst -C ext_sleef/ --wildcards \"*/bin/*.dll\""
    echo "cp -fv ext_sleef/ucrt64/bin/*.dll lib/"
    echo "rm -rf sleef.tar.zst ext_sleef"

    # --- OPENBLAS ---
    echo "download_file \"$OPENBLAS_LINK\" \"openblas.tar.zst\""
    echo "mkdir -p ext_openblas"
    echo "tar --use-compress-program=unzstd -xf openblas.tar.zst -C ext_openblas/ --wildcards \"*/bin/*.dll\""
    echo "cp -fv ext_openblas/ucrt64/bin/*.dll lib/"
    echo "rm -rf openblas.tar.zst ext_openblas"

    # --- PROTOBUF ---
    echo "download_file \"$PROTOBUF_LINK\" \"protobuf.tar.zst\""
    echo "mkdir -p ext_protobuf"
    echo "tar --use-compress-program=unzstd -xf protobuf.tar.zst -C ext_protobuf/ --wildcards \"*/bin/*.dll\""
    echo "cp -fv ext_protobuf/ucrt64/bin/*.dll lib/"
    echo "rm -rf protobuf.tar.zst ext_protobuf"

    # --- LIBUNWIND ---
    echo "download_file \"$UNWIND_LINK\" \"unwind.tar.zst\""
    echo "mkdir -p ext_unwind"
    echo "tar --use-compress-program=unzstd -xf unwind.tar.zst -C ext_unwind/ --wildcards \"*/bin/*.dll\""
    echo "cp -fv ext_unwind/ucrt64/bin/*.dll lib/"
    echo "rm -rf unwind.tar.zst ext_unwind"

    # --- ABSL ---
    echo "download_file \"$ABSEIL_LINK\" \"abseil.tar.zst\""
    echo "mkdir -p ext_abseil"
    echo "tar --use-compress-program=unzstd -xf abseil.tar.zst -C ext_abseil/ --wildcards \"*/bin/libabsl_*.dll\""
    echo "cp -fv ext_abseil/ucrt64/bin/*.dll lib/"
    echo "rm -rf abseil.tar.zst ext_abseil"
}

ffbuild_dockerbuild() {
    set -e

    local GLOG_FLAGS_H="include/glog/flags.h"
    if [[ -f "$GLOG_FLAGS_H" ]]; then
        log_info "Injecting direct macro overrides into glog/flags.h..."
        sed -i '1i #undef GLOG_EXPORT\n#define GLOG_EXPORT' "$GLOG_FLAGS_H"
    fi

    log_info "Preparing LibTorch headers for GCC 15 compatibility..."

    # Прописываем базовые типы в заголовки C10/Torch, чтобы GCC 15 не падал на uint64_t или std::string
    find include/ -name "*.h" -o -name "*.hpp" -exec sed -i '1i #include <cstdint>\n#include <string>\n#include <stdexcept>' {} + 2>/dev/null || true

    # Гарантируем структуру папок в префиксе
    mkdir -p "${INSTALL_ROOT}"/{include,lib,bin}

    # Раскладываем заголовочные файлы
    cp -rf include/* "${INSTALL_ROOT}/include/"

    # Создаем минимальную заглушку Google Glog
#     mkdir -p "${INSTALL_ROOT}/include/glog"
#     cat << 'EOF' > "${INSTALL_ROOT}/include/glog/logging.h"
# #ifndef FAKE_GLOG_LOGGING_H_
# #define FAKE_GLOG_LOGGING_H_
# 
# #include <iostream>
# #include <sstream>
# 
# class FakeLogMessage {
# public:
#     FakeLogMessage() {}
#     template<typename T>
#     FakeLogMessage& operator<<(const T&) { return *this; }
# };
# 
# namespace google {
#     enum LogSeverity { GLOG_INFO = 0, GLOG_WARNING = 1, GLOG_ERROR = 2, GLOG_FATAL = 3 };
#     class LogMessage {
#     public:
#         LogMessage(const char* file, int line, LogSeverity severity) {}
#         std::ostream& stream() { return std::cerr; }
#     };
# }
# 
# #define INFO 0
# #define WARNING 1
# #define ERROR 2
# #define FATAL 3
# 
# #define LOG(severity) FakeLogMessage()
# 
# #define VLOG(verbose_level) FakeLogMessage()
# #define LOG_IF(severity, condition) if(condition) FakeLogMessage()
# 
# #endif // FAKE_GLOG_LOGGING_H_
# EOF
    # log_info "Advanced fake glog stub successfully generated."

    log_info "Distributing LibTorch and glog libraries..."
    # Копируем динамические .dll (они уйдут в финальный дистрибутив ffmpeg)
    cp -fv lib/*.dll "${INSTALL_ROOT}/bin/" 2>/dev/null || true

    # Копируем библиотеки импорта. 
    # В MSYS2 они называются *.dll.a, копируем их с переименованием в lib*.a
    for libfile in lib/*.dll.a; do
        if [[ -f "$libfile" ]]; then
            local filename=$(basename "$libfile")
            local clean_name=$(echo "$filename" | sed 's/\.dll\.a$//')
            if [[ "$clean_name" == lib* ]]; then
                cp -fv "$libfile" "${INSTALL_ROOT}/lib/${clean_name}.a"
            else
                cp -fv "$libfile" "${INSTALL_ROOT}/lib/lib${clean_name}.a"
            fi
        fi
    done

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/libtorch.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: LibTorch
Description: PyTorch C++ API (MSYS2 MinGW-w64 Build)
Version: 2.12.0
Libs: -L\${libdir} -ltorch -ltorch_cpu -lc10 -lglog-2 -lopenblas -lprotobuf -lsleef-3 -lunwind -labsl_cord-2605.0.0
Libs.private: -lshlwapi -lws2_32 -lstdc++ -lpthread
Cflags: -I\${includedir} -I\${includedir}/torch/csrc/api/include -DNOMINMAX -DNDEBUG
EOF

# -DC10_USE_MINIMAL_GLOG
}

ffbuild_cxxflags() {
    echo "-Wno-deprecated-declarations -Wno-error=deprecated-declarations -fpermissive -I$FFBUILD_PREFIX/include/torch/csrc/api/include -I$FFBUILD_PREFIX/include/torch/csrc/jit -DNOMINMAX -DNDEBUG"
}

ffbuild_configure() {
    echo --enable-libtorch
}

ffbuild_unconfigure() {
    echo --disable-libtorch
}
