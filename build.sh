#!/bin/bash
set -xe
shopt -s globstar
cd "$(dirname "$0")"
source util/vars.sh

# Определяем целевой вариант
source "variants/${TARGET}-${VARIANT}.sh"
for addin in ${ADDINS[*]}; do
    source "addins/${addin}.sh"
done

# В GitHub Actions мы уже внутри контейнера. 
# Путь /opt/ffdest должен совпадать с тем, что указан в Dockerfile (generate.sh)
FINAL_DEST="/opt/ffdest"
mkdir -p "$FINAL_DEST"
mkdir -p ffbuild

FFMPEG_REPO="${FFMPEG_REPO:-https://github.com/MartinEesmaa/FFmpeg.git}"
GIT_BRANCH="${GIT_BRANCH:-master}"

# Клонирование и патчинг (прямо в текущем слое Docker)
echo "Cloning FFmpeg..."
rm -rf ffbuild/ffmpeg
git clone --filter=blob:none --depth=1 --branch="$GIT_BRANCH" "$FFMPEG_REPO" ffbuild/ffmpeg
cd ffbuild/ffmpeg

# Применяем патчи
PATCHES=("../../patches/ffmpeg/$GIT_BRANCH"/*.patch)
for patch in "${PATCHES[@]}"; do
    if [[ -f "$patch" ]]; then
        echo "Applying $patch"
        git apply --whitespace=fix --ignore-space-change --ignore-whitespace "$patch"
    fi
done

# Конфигурация ccache
export CCACHE_DIR=/root/.cache/ccache
export CCACHE_MAXSIZE=1248M
ccache -z # Сброс статистики для чистого лога

# Сборка FFmpeg
chmod +x configure

./configure \
    --prefix="$PWD/../prefix" \
    --pkg-config-flags="--static" \
    $FFBUILD_TARGET_FLAGS \
    $FF_CONFIGURE \
    --enable-filter=vpp_amf \
    --enable-filter=sr_amf \
    --enable-runtime-cpudetect \
    --enable-pic \
    --enable-pthreads \
    --disable-w32threads \
    --enable-lto \
    --h264-max-bit-depth=14 \
    --h265-bit-depths=8,9,10,12 \
    --extra-cflags="$FF_CFLAGS" \
    --extra-cxxflags="$FF_CXXFLAGS" \
    --extra-ldflags="$FF_LDFLAGS" \
    --extra-ldexeflags="$FF_LDEXEFLAGS" \
    --extra-libs="$FF_LIBS" \
    --cc="$CC" --cxx="$CXX" --ar="$AR" --ranlib="$RANLIB" --nm="$NM" \
    --extra-version="VVCEasy"

# Используем 2 потока, чтобы не перегружать RAM раннера (7GB RAM / 2 ядра)
make -j$(nproc) V=1
make install install-doc
ccache -s

# Подготовка к упаковке (ОЧИСТКА МУСОРА)
cd ../..
BUILD_NAME="ffmpeg_vvceasy-$(./ffbuild/ffmpeg/ffbuild/version.sh ffbuild/ffmpeg)-${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}"
PKG_DIR="ffbuild/pkgroot/$BUILD_NAME"

mkdir -p "$PKG_DIR"
package_variant ffbuild/prefix "$PKG_DIR"

# Копируем лицензию
[[ -n "$LICENSE_FILE" ]] && cp "ffbuild/ffmpeg/$LICENSE_FILE" "$PKG_DIR/LICENSE.txt"

# Стриппинг бинарников (удаление отладочных символов)
pushd "$PKG_DIR/bin"
for bin in *.exe; do
    if [[ -f "$bin" ]]; then
        ${FFBUILD_CROSS_PREFIX}strip --strip-unneeded "$bin"
    fi
done
popd

# Создание архива
OUTPUT_FNAME="${BUILD_NAME}.7z"

# Упаковываем только финальный результат, игнорируя 5ГБ объектных файлов
7z a -mx9 -mmt=on "${FINAL_DEST}/${OUTPUT_FNAME}" "./$PKG_DIR"

# Генерация метаданных для GitHub Actions
if [[ -n "$GITHUB_ACTIONS" ]]; then
    echo "build_name=${BUILD_NAME}" >> "$GITHUB_OUTPUT"
    echo "${OUTPUT_FNAME}" > "${FINAL_DEST}/${TARGET}-${VARIANT}.txt"
fi

# Очистка рабочего пространства ПЕРЕД завершением слоя Docker
# Это освободит место на диске раннера до того, как он начнет экспорт
rm -rf ffbuild
