#!/bin/bash
set -e # Убираем -x для чистоты, ошибки все равно будут видны
cd "$(dirname "$0")"
source util/vars.sh

# В GitHub Actions мы пропускаем сборку базовых образов здесь, 
# так как они уже собраны в предыдущих шагах workflow.
if [[ -z "$GITHUB_ACTIONS" ]]; then
    echo "Running locally, building base images..."
    # Локальная сборка (если нужно)
    docker build -t "${REGISTRY}/${REPO}/base:latest" images/base
    docker build -t "${REGISTRY}/${REPO}/base-${TARGET}:latest" \
        --build-arg GH_REPO="${REGISTRY}/${REPO}" "images/base-${TARGET}"
fi

# Загрузка исходников (теперь на хосте, без Docker)
echo "Step: Downloading sources..."
./download.sh

# Генерация Dockerfile (наш новый линейный формат)
echo "Step: Generating Dockerfile..."
./generate.sh "$TARGET" "$VARIANT" "${ADDINS[@]}"

# Сборка финального образа и экспорт
echo "Step: Building FFmpeg..."

# Если мы в GitHub Actions, мы используем билд через обычный docker build
# или позволяем workflow самому вызвать docker buildx.
# Но если нужно запустить именно из скрипта:

DOCKER_BUILDKIT=1 docker build \
    --target artifacts \
    --output type=local,dest=artifacts/ \
    --tag "$IMAGE" .

echo "Build finished. Artifacts are in artifacts/ directory."
