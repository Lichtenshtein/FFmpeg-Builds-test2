#!/bin/bash

SCRIPT_REPO="https://mirror.yandex.ru/mirrors/msys2/mingw/ucrt64/mingw-w64-ucrt-x86_64-python-pytorch-2.12.0-4-any.pkg.tar.zst"
GLOG_LINK="https://mirror.yandex.ru/mirrors/msys2/mingw/ucrt64/mingw-w64-ucrt-x86_64-glog-0.7.1-10-any.pkg.tar.zst"

export SKIP_POST_PC_PATCH=1

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "download_file \"$SCRIPT_REPO\" \"pytorch.tar.zst\""
    echo "mkdir -p extracted"
    echo "tar --use-compress-program=unzstd -xf pytorch.tar.zst -C extracted/ \
        --wildcards \
        \"*/site-packages/torch/include*\" \
        \"*/site-packages/torch/lib*\" "
    echo "mv extracted/ucrt64/lib/python*/site-packages/torch/include ."
    echo "mv extracted/ucrt64/lib/python*/site-packages/torch/lib ."
    echo "rm -rf pytorch.tar.zst extracted"

    echo "download_file \"$GLOG_LINK\" \"glog.tar.zst\""
    echo "mkdir -p extracted_glog"
    echo "tar --use-compress-program=unzstd -xf glog.tar.zst -C extracted_glog/ \
        --wildcards \"*/include/glog*\" \"*/lib/*.a\" \"*/bin/*.dll\" "
    echo "mkdir -p include/glog lib"
    echo "cp -rf extracted_glog/ucrt64/include/glog/* include/glog/"
    echo "cp -fv extracted_glog/ucrt64/lib/libglog.dll.a lib/glog.dll.a"
    echo "cp -fv extracted_glog/ucrt64/bin/libglog-2.dll lib/"
    echo "rm -rf glog.tar.zst extracted_glog"
}

ffbuild_dockerbuild() {
    set -e

    log_info "Preparing LibTorch headers for GCC 15 compatibility..."

    # Прописываем базовые типы в заголовки C10/Torch, чтобы GCC 15 не падал на uint64_t или std::string
    find include/ -name "*.h" -o -name "*.hpp" -exec sed -i '1i #include <cstdint>\n#include <string>\n#include <stdexcept>' {} + 2>/dev/null || true

    # Гарантируем структуру папок в префиксе
    mkdir -p "${INSTALL_ROOT}"/{include,lib,bin}

    # Раскладываем заголовочные файлы
    cp -rf include/* "${INSTALL_ROOT}/include/"

    # Создаем минимальную заглушку Google Glog
    mkdir -p "${INSTALL_ROOT}/include/glog"
    cat << 'EOF' > "${INSTALL_ROOT}/include/glog/logging.h"
#ifndef FAKE_GLOG_LOGGING_H_
#define FAKE_GLOG_LOGGING_H_

#include <iostream>
#include <sstream>

class FakeLogMessage {
public:
    FakeLogMessage() {}
    template<typename T>
    FakeLogMessage& operator<<(const T&) { return *this; }
};

namespace google {
    enum LogSeverity { GLOG_INFO = 0, GLOG_WARNING = 1, GLOG_ERROR = 2, GLOG_FATAL = 3 };
    class LogMessage {
    public:
        LogMessage(const char* file, int line, LogSeverity severity) {}
        std::ostream& stream() { return std::cerr; }
    };
}

#define INFO 0
#define WARNING 1
#define ERROR 2
#define FATAL 3

#define LOG(severity) FakeLogMessage()

#define VLOG(verbose_level) FakeLogMessage()
#define LOG_IF(severity, condition) if(condition) FakeLogMessage()

#endif // FAKE_GLOG_LOGGING_H_
EOF
    log_info "Advanced fake glog stub successfully generated."

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
Libs: -L\${libdir} -ltorch -ltorch_cpu -lc10 -lglog
Libs.private: -lshlwapi -lws2_32 -lstdc++ -lpthread
Cflags: -I\${includedir} -I\${includedir}/torch/csrc/api/include -DNOMINMAX -DNDEBUG -DC10_USE_MINIMAL_GLOG
EOF
}

ffbuild_cxxflags() {
    echo "-Wno-deprecated-declarations -Wno-error=deprecated-declarations -fpermissive -I$FFBUILD_PREFIX/include/torch/csrc/api/include -I$FFBUILD_PREFIX/include/torch/csrc/jit -DNOMINMAX -DNDEBUG -DC10_USE_MINIMAL_GLOG"
}

ffbuild_configure() {
    echo --enable-libtorch
}

ffbuild_unconfigure() {
    echo --disable-libtorch
}
