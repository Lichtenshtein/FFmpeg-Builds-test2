#!/bin/bash

set -eo pipefail
shopt -s globstar
export LC_ALL=C

# Загружаем оформление
source util/vars.sh 2>/dev/null || true

cd "$(dirname "$0")"/..

# Можно передать конкретный файл: ./util/update_scripts_test.sh "scripts.d/50-x264.sh"
SEARCH_PATTERN="${1:-scripts.d/**/*.sh}"

# Массивы для отчета
declare -a UPDATED_FILES
declare -a BROKEN_REPOS
declare -a UNKNOWN_LAYOUTS
declare -a SYNTAX_ERRORS

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

for scr in $SEARCH_PATTERN; do
    [[ -f "$scr" ]] || continue
    
    # Пропускаем помеченные скрипты
    if grep -q 'SCRIPT_SKIP="1"' "$scr"; then
        log_debug "${LOCK_MARK} Skipping ${scr} (SCRIPT_SKIP active)"
        continue
    fi

    log_info "${SEARCH_MARK} Checking ${scr}..."
    cp "$scr" "${scr}.bak"
    file_changed=0

    # Запускаем в подоболочке, чтобы source не замусорил окружение
    (
        # Нам нужно только получить переменные, не выполняя функции билда
        # Поэтому мы грепаем только строки с определениями переменных
        eval "$(grep -E '^[A-Z0-9_]+=".*"' "$scr")"

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
                echo "REPORT_DEAD|${scr}|${CUR_REPO}"
                continue
            fi

            NEW_VAL=""
            TARGET_VAR=""

            if [[ -n "${CUR_COMMIT}" ]]; then
                TARGET_VAR="${COMMIT_VAR}"
                if [[ -n "${!TAG_VAR}" ]]; then
                    NEW_VAL=$(git -c 'versionsort.suffix=-' ls-remote --tags --refs --sort "v:refname" "${CUR_REPO}" "${!TAG_VAR}" | tail -n1 | awk '{print $1}')
                # Если есть ВЕТКА
                elif [[ -n "${!BRANCH_VAR}" ]]; then
                    NEW_VAL=$(git ls-remote --heads "${CUR_REPO}" "refs/heads/${!BRANCH_VAR}" | cut -f1)
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
                echo "REPORT_UNKNOWN|${scr}|${CUR_REPO}"
                continue
            fi

            if [[ -n "${NEW_VAL}" && "${NEW_VAL}" != "${!TARGET_VAR}" ]]; then
                echo "REPORT_UPDATE|${scr}|${TARGET_VAR}|${!TARGET_VAR}|${NEW_VAL}"
                sed -i "s|^${TARGET_VAR}=\".*\"|${TARGET_VAR}=\"${NEW_VAL}\"|" "${scr}"
            fi
        done
    ) | while IFS='|' read -r type file var old new; do
        # Обработка сигналов из подоболочки
        case "$type" in
            REPORT_UPDATE)  log_info "  ${SYNC_MARK} $var: ${old:0:7} -> ${new:0:7}"; UPDATED_FILES+=("$file") ;;
            REPORT_DEAD)    log_error "  ${CROSS_MARK} Repo is DEAD/Offline: $var"; BROKEN_REPOS+=("$file ($var)") ;;
            REPORT_UNKNOWN) log_warn "  ${XCLAM_MARK} Unknown layout (no commit/rev var)"; UNKNOWN_LAYOUTS+=("$file") ;;
        esac
    done

    # Валидация синтаксиса
    if ! bash -n "$scr"; then
        log_error "${CROSS_MARK} Syntax error in ${scr}! Rolling back."
        SYNTAX_ERRORS+=("$scr")
        mv "${scr}.bak" "$scr"
    else
        rm -f "${scr}.bak"
    fi
done

# --- ФИНАЛЬНЫЙ ОТЧЕТ ---
echo -e "\n${LOGS_MARK} ${LOG_INFO}--- FINAL UPDATE REPORT ---${LOG_NC}"

[[ ${#BROKEN_REPOS[@]} -gt 0 ]] && {
    echo -e "${RED}💀 DEAD REPOSITORIES (Need manual fix):${NC}"
    printf "  - %s\n" "${BROKEN_REPOS[@]}"
}

[[ ${#UNKNOWN_LAYOUTS[@]} -gt 0 ]] && {
    echo -e "${YELLOW}❓ UNKNOWN LAYOUTS (Manual check required):${NC}"
    printf "  - %s\n" "${UNKNOWN_LAYOUTS[@]}"
}

[[ ${#SYNTAX_ERRORS[@]} -gt 0 ]] && {
    echo -e "${RED}🚫 SYNTAX ERRORS (Rollbacked):${NC}"
    printf "  - %s\n" "${SYNTAX_ERRORS[@]}"
}

log_info "${CHECK_MARK} Update process finished."
