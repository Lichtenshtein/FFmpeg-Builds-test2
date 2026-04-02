#!/bin/bash

set -eo pipefail
shopt -s globstar

# Загружаем оформление
source util/vars.sh 2>/dev/null || true

# Читаем список из ENV или используем пустой, если переменная не задана
# Превращаем строку "zlib base" в массив (zlib base)
read -ra EXCLUDE_COMPONENTS <<< "${UPDATE_PRESERVE_LIST:-}"
log_debug "Exclusion list active: ${EXCLUDE_COMPONENTS[*]}"

cd "$(dirname "$0")"/..

# Можно передать конкретный файл: ./util/update_scripts_test.sh "scripts.d/50-x264.sh"
SEARCH_PATTERN="${1:-scripts.d/**/*.sh}"

# Используем временные файлы для сбора отчетов, чтобы обойти проблему subshell в пайпах
TMP_REPORT=$(mktemp)
trap 'rm -f "$TMP_REPORT"' EXIT

# Массивы для отчета
# declare -a UPDATED_FILES
# declare -a BROKEN_REPOS
# declare -a UNKNOWN_LAYOUTS
# declare -a SYNTAX_ERRORS

check_repo_exists() {
    local repo=$1
    if [[ "$repo" == *.git ]]; then
        git ls-remote --exit-code "$repo" HEAD >/dev/null 2>&1
        return $?
    elif [[ "$repo" == *"/svn/"* ]]; then
        svn info --non-interactive "$repo" >/dev/null 2>&1
        return $?
    fi
    return 0 # Для остальных считаем доступным
}

# Shaderc dependency update function
update_shaderc_deps() {
    local deps_file="$PATCHES_DIR/shaderc/DEPS"
    [[ -f "$deps_file" ]] || return 0

    log_info "${SEARCH_MARK} Checking Shaderc dependencies in ${deps_file}..."

    # Создаем временную копию
    local tmp_deps=$(mktemp)
    cp "$deps_file" "$tmp_deps"

    # Базовые URL репозиториев (извлекаем из файла DEPS)
    local abseil_git=$(grep "'abseil_git':" "$deps_file" | cut -d"'" -f4)
    local google_git=$(grep "'google_git':" "$deps_file" | cut -d"'" -f4)
    local khronos_git=$(grep "'khronos_git':" "$deps_file" | cut -d"'" -f4)

    # Список зависимостей: "переменная_в_deps|URL_репозитория"
    local deps_map=(
        "abseil_revision|${abseil_git}/abseil-cpp.git"
        "effcee_revision|${google_git}/effcee.git"
        "googletest_revision|${google_git}/googletest.git"
        "glslang_revision|${khronos_git}/glslang.git"
        "re2_revision|${google_git}/re2.git"
        "spirv_headers_revision|${khronos_git}/SPIRV-Headers.git"
        "spirv_tools_revision|${khronos_git}/SPIRV-Tools.git"
    )

    for entry in "${deps_map[@]}"; do
        IFS="|" read -r var_name repo_url <<< "$entry"
        # Получаем текущий хеш из файла
        local current_hash=$(grep "'$var_name':" "$deps_file" | cut -d"'" -f4)
        [[ -z "$current_hash" ]] && continue
        # Получаем свежий хеш из удаленного репозитория (HEAD)
        local new_hash=$(git ls-remote "$repo_url" HEAD 2>/dev/null | awk '{print $1}')
        if [[ -n "$new_hash" && "$new_hash" != "$current_hash" ]]; then
            log_info "  ${SYNC_MARK} shaderc/${var_name}: ${current_hash:0:7} -> ${new_hash:0:7}"
            # Обновляем хеш в файле
            sed -i "s/'$var_name': '.*'/'$var_name': '$new_hash'/" "$deps_file"
            echo "REPORT_UPDATE|${deps_file}|${var_name}|${current_hash}|${new_hash}" >> "$TMP_REPORT"
        fi
    done
}

for STAGE in $SEARCH_PATTERN; do
    [[ -f "$STAGE" ]] || continue
    # STAGENAME=$(basename "$STAGE" .sh)

    # Проверка на вхождение в массив исключений
    skip_this=0
    for exc in "${EXCLUDE_COMPONENTS[@]}"; do
        [[ "$COMPONENT_NAME" == "$exc" ]] && skip_this=1 && break
    done
    [[ $skip_this -eq 1 ]] && log_info "${LOCK_MARK} Skipping: ${STAGENAME} (In exclusion list)" && continue

    # Пропускаем помеченные скрипты
    if grep -q 'SCRIPT_SKIP="1"' "$STAGE"; then
        log_debug "${LOCK_MARK} Skipping ${STAGE} (SCRIPT_SKIP active)"
        continue
    fi

    log_info "${SEARCH_MARK} Checking ${STAGE}..."
    cp "$STAGE" "${STAGE}.bak"
    file_changed=0

    # Запускаем в подоболочке, чтобы source не замусорил окружение
    (
        # Нам нужно только получить переменные, не выполняя функции билда
        # Поэтому мы грепаем только строки с определениями переменных
        eval "$(grep -E '^[A-Z0-9_]+=".*"' "$STAGE")"

        for i in "" $(seq 2 9); do
            REPO_VAR="SCRIPT_REPO$i"; COMMIT_VAR="SCRIPT_COMMIT$i"
            REV_VAR="SCRIPT_REV$i"; HGREV_VAR="SCRIPT_HGREV$i"
            BRANCH_VAR="SCRIPT_BRANCH$i"; TAG_VAR="SCRIPT_TAGFILTER$i"

            CUR_REPO="${!REPO_VAR}"; CUR_COMMIT="${!COMMIT_VAR}"
            CUR_REV="${!REV_VAR}"; CUR_HGREV="${!HGREV_VAR}"
            CUR_BRANCH="${!BRANCH_VAR}"; CUR_TAG="${!TAG_VAR}"

            [[ -z "${CUR_REPO}" ]] && break

            # Проверка на "живучесть" репозитория
            if ! check_repo_exists "$CUR_REPO"; then
                echo "REPORT_DEAD|${STAGE}|${CUR_REPO}" >> "$TMP_REPORT"
                continue
            fi

            NEW_VAL=""
            TARGET_VAR=""

            if [[ -n "${CUR_COMMIT}" ]]; then
                TARGET_VAR="${COMMIT_VAR}"
                if [[ -n "${CUR_TAG}" ]]; then
                    NEW_VAL=$(git -c 'versionsort.suffix=-' ls-remote --tags --refs --sort "v:refname" "${CUR_REPO}" "${CUR_TAG}" | tail -n1 | awk '{print $1}')
                # Если есть ВЕТКА
                elif [[ -n "${CUR_BRANCH}" ]]; then
                    NEW_VAL=$(git ls-remote --heads "${CUR_REPO}" "refs/heads/${CUR_BRANCH}" | cut -f1)
                # Если ничего не указано пытаемся найти дефолтную ветку (HEAD)
                else
                    NEW_VAL=$(git ls-remote "${CUR_REPO}" HEAD | awk '{print $1}')
                fi
            elif [[ -n "${CUR_REV}" ]]; then
                TARGET_VAR="${REV_VAR}"
                NEW_VAL=$(svn --non-interactive info --username "anonymous" --password="" "${CUR_REPO}" 2>/dev/null | grep ^Revision: | cut -d" " -f2 | xargs || true)
            elif [[ -n "${CUR_HGREV}" ]]; then
                TARGET_VAR="${HGREV_VAR}"
                NEW_VAL=$(hg identify "${CUR_REPO}" -r default 2>/dev/null | awk '{print $1}' || true)
            else
                # Неизвестный формат (нет ни коммита, ни ревизии)
                echo "REPORT_UNKNOWN|${STAGE}|${CUR_REPO}" >> "$TMP_REPORT"
                continue
            fi

            # Если нашли новое значение и оно отличается от текущего
            if [[ -n "${NEW_VAL}" && "${NEW_VAL}" != "${!TARGET_VAR}" ]]; then
                echo "REPORT_UPDATE|${STAGE}|${TARGET_VAR}|${!TARGET_VAR}|${NEW_VAL}" >> "$TMP_REPORT"
                # Обновляем файл физически
                sed -i "s|^${TARGET_VAR}=\".*\"|${TARGET_VAR}=\"${NEW_VAL}\"|" "${STAGE}"
                log_info "  ${SYNC_MARK} ${TARGET_VAR}: ${!TARGET_VAR:0:7} -> ${NEW_VAL:0:7}"
            fi
        done
    ) 

    # Валидация синтаксиса
    if ! bash -n "$STAGE"; then
        log_error "${CROSS_MARK} Syntax error in ${STAGE}! Rolling back."
        echo "REPORT_SYNTAX|${STAGE}" >> "$TMP_REPORT"
        mv "${STAGE}.bak" "$STAGE"
    else
        rm -f "${STAGE}.bak"
    fi
done

# --- ФИНАЛЬНЫЙ ОТЧЕТ ---

# Вызываем обновление Shaderc отдельно
update_shaderc_deps

echo -e "\n${LOGS_MARK} ${LOG_INFO}--- FINAL UPDATE REPORT ---${LOG_NC}"
UPDATED_FILES=(); BROKEN_REPOS=(); UNKNOWN_LAYOUTS=(); SYNTAX_ERRORS=()

# Читаем из TMP_REPORT и формируем массивы в основном процессе
while IFS='|' read -r type file var old new; do
    case "$type" in
        REPORT_UPDATE) UPDATED_FILES+=("$file ($var)") ;;
        REPORT_DEAD)   BROKEN_REPOS+=("$file ($var)") ;;
        REPORT_UNKNOWN) UNKNOWN_LAYOUTS+=("$file") ;;
        REPORT_SYNTAX) SYNTAX_ERRORS+=("$file") ;;
    esac
done < "$TMP_REPORT"

if [[ ${#UPDATED_FILES[@]} -gt 0 ]]; then
    echo -e "${GREEN}✅ UPDATED:${NC}"
    printf "  - %s\n" $(printf "%s\n" "${UPDATED_FILES[@]}" | sort -u)
fi

if [[ ${#BROKEN_REPOS[@]} -gt 0 ]]; then
    echo -e "${RED}💀 DEAD REPOSITORIES (Need manual fix):${NC}"
    printf "  - %s\n" "${BROKEN_REPOS[@]}"
fi

if [[ ${#UNKNOWN_LAYOUTS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}❓ UNKNOWN LAYOUTS (Manual check required)${NC}"
    printf "  - %s\n" "${UNKNOWN_LAYOUTS[@]}"
fi

if [[ ${#SYNTAX_ERRORS[@]} -gt 0 ]]; then
    echo -e "${RED}🚫 SYNTAX ERRORS (Rollbacked):${NC}"
    printf "  - %s\n" "${SYNTAX_ERRORS[@]}"
fi

log_info "${CHECK_MARK} Update process finished."
