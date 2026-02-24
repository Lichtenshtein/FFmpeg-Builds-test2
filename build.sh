#!/bin/bash
set -xe
shopt -s globstar
cd "$(dirname "$0")"
source util/vars.sh "$1" "$2"
# Если "Hits" всегда 0, значит, монтирование --mount=type=cache в generate.sh не пробрасывается в build.sh (проверить совпадение путей /root/.cache/ccache).
ccache -s

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

# Клонирование и патчинг (прямо в текущем слое Docker)
log_info "Using pre-mounted FFmpeg source..."
cd ffbuild/ffmpeg

# Патчи теперь ищем по имени ветки, пришедшей из ENV
if [[ -d "/builder/patches/ffmpeg/$FFMPEG_BRANCH" ]]; then
    git checkout .
    for patch in "/builder/patches/ffmpeg/$FFMPEG_BRANCH"/*.patch; do
        [[ -e "$patch" ]] || continue
            log_info "-----------------------------------"
            log_info "APPLYING PATCH: $patch"
        if patch -p1 < "$patch"; then
            log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            log_info "-----------------------------------"
        else
            log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
            log_info "-----------------------------------"
            # exit 1 # если нужно прервать сборку при ошибке
        fi
    done
fi

ccache -z # Сброс статистики для чистого лога
log_info "Cleaning up potential prefix pollution..."
# Удаляем пустые папки или старые логи, если они остались
find /opt/ffbuild -type d -empty -delete

# Force update of pkg-config paths
export PKG_CONFIG_PATH="/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig"
export PKG_CONFIG_LIBDIR="/opt/ffbuild/lib/pkgconfig"
# Перед запуском configure убедимся, что линковщик видит DLL-импорты
# Эти флаги до -Wl нужны для статической линковки glib, так как она используется во многих фильтрах. -lintl -liconv часто конфликтуют с внутренними функциями glibc или самого компилятора, если они не были собраны как строго статические.
# Если линковка падает с "undefined reference", добавить -Wl,--copy-dt-needed-entries в LDFLAGS
# Позволяем линкеру искать DLL для конкретных библиотек -Wl,--copy-dt-needed-entries -Wl,--dynamicbase -Wl,--nxcompat
export LDFLAGS="$LDFLAGS -Wl,--allow-multiple-definition -Wl,--copy-dt-needed-entries -Wl,--dynamicbase -Wl,--nxcompat"

# Сборка FFmpeg
chmod +x configure

# Полустатический режим
# --extra-libs="$FF_LIBS -lstdc++ -lm -lws2_32 -lole32" - системный минимум
# Библиотеки ИИ
# -lshlwapi, -luser32, -ladvapi32 - критичны для LibTorch.
# -lbcrypt - часто нужен для современных версий TensorFlow и OpenSSL.
# -ldbghelp - нужен для обработки исключений в LibTorch.
# --extra-libs="$FF_LIBS -lstdc++ -lm -lws2_32 -lole32 -lshlwapi -luser32 -ladvapi32 -lbcrypt -lsetupapi -ldbghelp"

# линковка с --enable-lto может потребовать более 16-32 ГБ RAM. Стандартный раннер GitHub имеет всего 7 ГБ
./configure \
    --prefix="$PWD/../prefix" \
    --pkg-config-flags="--static" \
    $FFBUILD_TARGET_FLAGS \
    --extra-cflags="$FF_CFLAGS" \
    --extra-ldflags="$FF_LDFLAGS" \
    --extra-cxxflags="$FF_CXXFLAGS" \
    --extra-ldexeflags="$FF_LDEXEFLAGS" \
    --extra-libs="$FF_LIBS" \
    $FF_CONFIGURE \
    --enable-filter=vpp_amf \
    --enable-filter=sr_amf \
    --enable-runtime-cpudetect \
    --enable-pic \
    --h264-max-bit-depth=14 \
    --h265-bit-depths=8,9,10,12 \
    --cc="$CC" --cxx="$CXX" --ar="$AR" --ranlib="$RANLIB" --nm="$NM" \
    --extra-version="VVCEasy"

    if ! ./configure ... ; then
        log_error "Configure failed! Check ffbuild/config.log"
        tail -n 100 ffbuild/config.log
        exit 1
    fi

# Используем 2 потока, чтобы не перегружать RAM раннера (7GB RAM / 2 ядра)
make -j$(nproc) $MAKE_V
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

log_info "Collecting external DLLs for AI support..."
mkdir -p "$PKG_DIR/bin"
# Копируем все DLL из нашего сборочного префикса в папку с бинарниками
# Это подхватит DLL от OpenVINO, TBB, TensorFlow, LibTorch и других
log_info "Copying OpenVINO plugins..."
# OpenVINO часто ищет файлы openvino_intel_cpu_plugin.dll в той же папке
# Если они лежат в /opt/ffbuild/bin, то всё ок. 
# Но если они в подпапках (runtime/bin/intel64/...), нужно убедиться, что они попали в $PKG_DIR/bin/
find "/opt/ffbuild/bin" -name "*.dll" -exec cp -v {} "$PKG_DIR/bin/" \;
# Проверяем наличие критических библиотек (для отладки в логах)
ls -lh "$PKG_DIR/bin/"
# Скачиваем модели для ИИ
# log_info "Downloading Additional Models for AI..."
# MODELS_FINAL_DIR="$PKG_DIR/models"
# /builder/util/download_models.sh "$MODELS_FINAL_DIR"

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
    # Вывод статистики ccache (теперь через прямую команду)
    log_info "--- CCACHE STATISTICS ---"
    ccache -s
fi

# Очистка рабочего пространства ПЕРЕД завершением слоя Docker
# Это освободит место на диске раннера до того, как он начнет экспорт
rm -rf ffbuild
