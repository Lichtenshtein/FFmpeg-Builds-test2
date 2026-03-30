#!/bin/bash

ffbuild_enabled() {
    # [[ $TARGET == win* ]] || return 1
    return 0
}

ffbuild_dockerbuild() {
    set -e
    # В Mingw-w64 заголовки GL обычно уже встроены в тулчейн.
    # просто создаем пустую стадию, чтобы активировать флаги.
    return 0

}

ffbuild_configure() {
    echo "--enable-opengl"
}

ffbuild_libs() {
    echo "-lopengl32 -lgdi32"
}
