#!/bin/bash

set -eo pipefail
shopt -s globstar

source util/vars.sh "$TARGET" "$VARIANT" 2>&1 || {
    echo "ERROR: vars.sh failed (TARGET=$TARGET VARIANT=$VARIANT)" >&2
    exit 1
}

# Читаем список из ENV или используем пустой, если переменная не задана
# Превращаем строку "zlib base" в массив (zlib base)
read -ra EXCLUDE_COMPONENTS <<< "${UPDATE_PRESERVE_LIST:-}"
[[ ${#EXCLUDE_COMPONENTS[@]} -gt 0 ]] && \
    log_debug "Exclusion list active: ${EXCLUDE_COMPONENTS[*]}"

cd "$(dirname "$0")"/..

# Можно передать конкретный файл: ./util/update_scripts_test.sh "scripts.d/50-x264.sh"
SEARCH_PATTERN="${1:-scripts.d/**/*.sh}"

# Используем временные файлы для сбора отчетов, чтобы обойти проблему subshell в пайпах
TMP_REPORT=$(mktemp)
trap 'rm -f "$TMP_REPORT"' EXIT

# Helper: check if a repository is accessible
check_repo_exists() {
    local repo=$1
    if [[ "$repo" == *.git ]]; then
        git ls-remote --exit-code "$repo" HEAD >/dev/null 2>&1
        return $?
    elif [[ "$repo" == *"/svn/"* ]]; then
        svn info --non-interactive "$repo" >/dev/null 2>&1
        return $?
    fi
    return 0
}

# Update Shaderc DEPS file (Python syntax, not bash)
# This must be called BEFORE we start processing regular scripts
update_shaderc_deps() {
    local deps_file="$PATCHES_DIR/shaderc/DEPS"
    [[ -f "$deps_file" ]] || return 0

    log_info "${SEARCH_MARK} Checking Shaderc dependencies in ${deps_file}..."

    # Создаем временную копию
    local tmp_deps
    tmp_deps=$(mktemp)
    cp "$deps_file" "$tmp_deps"

    # Базовые URL репозиториев (извлекаем из файла DEPS)
    local abseil_git google_git khronos_git
    abseil_git=$(grep "'abseil_git':" "$deps_file" | cut -d"'" -f4)
    google_git=$(grep "'google_git':" "$deps_file" | cut -d"'" -f4)
    khronos_git=$(grep "'khronos_git':" "$deps_file" | cut -d"'" -f4)

    # Map of "python_var_name|full_repo_url"
    local -a deps_map=(
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

        local current_hash
        current_hash=$(grep "'${var_name}':" "$deps_file" | grep -oP "'\K[a-f0-9]{40}" | head -n1)
        [[ -z "$current_hash" ]] && continue

        local new_hash
        new_hash=$(git ls-remote "$repo_url" HEAD 2>/dev/null | awk '{print $1}' | head -n1) || {
            log_warn "  ${CROSS_MARK} Failed to fetch ${var_name} from ${repo_url}"
            echo "REPORT_DEAD|${deps_file}|${var_name}" >> "$TMP_REPORT"
            continue
        }

        if [[ -n "$new_hash" && "$new_hash" != "$current_hash" ]]; then
          if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
            log_debug "DEBUG_SHADERC_BEFORE: Target Var=[${var_name}] Matching line in DEPS:"
            grep "'${var_name}':" "$deps_file" || true
          fi
            sed -i -E 's/(\x27'"${var_name}"'\x27\s*:\s*\x27)[a-f0-9]{40}(\x27)/\1'"${new_hash}"'\2/g' "$deps_file"

            log_info "  ${SYNC_MARK} shaderc/${var_name}: ${current_hash:0:7} -> ${new_hash:0:7}"
            echo "REPORT_UPDATE|${deps_file}|${var_name}|${current_hash}|${new_hash}" >> "$TMP_REPORT"
        fi
    done

    rm -f "$tmp_deps"
}

phase_header "🔄" "UPDATING COMPONENT VERSIONS"

# Main: process all stage scripts
for STAGE in $SEARCH_PATTERN; do
    [[ -f "$STAGE" ]] || continue

    STAGENAME="$(basename "$STAGE" .sh)"
    COMPONENT_NAME="${STAGENAME#*-}"

    # Проверка на вхождение в массив исключений
    skip_this=0
    for exc in "${EXCLUDE_COMPONENTS[@]}"; do
        [[ "$COMPONENT_NAME" == "$exc" ]] && skip_this=1 && break
    done
    [[ $skip_this -eq 1 ]] && log_info "${LOCK_MARK} Skipping: ${STAGENAME} (In exclusion list)" && continue

    # Пропускаем помеченные скрипты
    if grep -q 'SCRIPT_SKIP="1"' "$STAGE"; then
        log_debug "${LOCK_MARK} Skipping ${STAGENAME} (SCRIPT_SKIP active)"
        continue
    fi

    log_info "${SEARCH_MARK} Checking ${STAGENAME}..."
    cp "$STAGE" "${STAGE}.bak"

    # Создаем изолированный файл задач для текущего скрипта
    STAGE_TASKS=$(mktemp)

    # Process in subshell to avoid polluting the main environment
    # source the full script, not just grep variables
    # This ensures all variable assignments (including complex ones) are captured
    (
        set +e  # Don't exit on errors inside the subshell
        # Source the script to get all variables
        # Redirect stderr to avoid polluting logs with debug output
        source "$STAGE" >/dev/null 2>&1 || true

        # Now iterate through all possible SCRIPT_REPO/COMMIT/REV/HGREV variables
        for i in "" $(seq 2 9); do
            REPO_VAR="SCRIPT_REPO$i"
            COMMIT_VAR="SCRIPT_COMMIT$i"
            REV_VAR="SCRIPT_REV$i"
            HGREV_VAR="SCRIPT_HGREV$i"
            BRANCH_VAR="SCRIPT_BRANCH$i"
            TAG_VAR="SCRIPT_TAGFILTER$i"

            # Get current values using indirect expansion
            CUR_REPO="${!REPO_VAR:-}"
            CUR_COMMIT="${!COMMIT_VAR:-}"
            CUR_REV="${!REV_VAR:-}"
            CUR_HGREV="${!HGREV_VAR:-}"
            CUR_BRANCH="${!BRANCH_VAR:-}"
            CUR_TAG="${!TAG_VAR:-}"

            # Если имя репозитория пустое или не похоже на URL, останавливаем
            if [[ -z "${CUR_REPO}" || ! "${CUR_REPO}" =~ ^(https?|git|svn):// ]]; then
                break
            fi

            # Check if repo is accessible
            if ! check_repo_exists "$CUR_REPO"; then
                echo "REPORT_DEAD|${STAGE}|${CUR_REPO}" >> "$TMP_REPORT"
                continue
            fi

            NEW_VAL="" TARGET_VAR=""

            # Determine which type of revision control and fetch latest
            if [[ -n "$CUR_COMMIT" ]]; then
                TARGET_VAR="${COMMIT_VAR}"
                if [[ -n "$CUR_TAG" ]]; then
                    # Git tag (semantic versioning)
                    NEW_VAL=$(git -c 'versionsort.suffix=-' ls-remote --tags --refs \
                        --sort "v:refname" "${CUR_REPO}" "${CUR_TAG}" 2>/dev/null | \
                        tail -n1 | awk '{print $1}') || true
                elif [[ -n "$CUR_BRANCH" ]]; then
                    # Git branch
                    NEW_VAL=$(git ls-remote --heads "${CUR_REPO}" \
                        "refs/heads/${CUR_BRANCH}" 2>/dev/null | cut -f1) || true
                else
                    # Default branch (HEAD)
                    NEW_VAL=$(git ls-remote "${CUR_REPO}" HEAD 2>/dev/null | \
                        awk '{print $1}') || true
                fi
            elif [[ -n "$CUR_REV" ]]; then
                # Subversion
                TARGET_VAR="${REV_VAR}"
                NEW_VAL=$(svn --non-interactive info --username "anonymous" \
                    --password="" "${CUR_REPO}" 2>/dev/null | \
                    grep ^Revision: | cut -d" " -f2 | xargs || true)
            elif [[ -n "$CUR_HGREV" ]]; then
                # Mercurial
                TARGET_VAR="${HGREV_VAR}"
                NEW_VAL=$(hg identify "${CUR_REPO}" -r default 2>/dev/null | \
                    awk '{print $1}' || true)
            elif [[ "$CUR_REPO" == *.tar.gz || "$CUR_REPO" == *.7z || "$CUR_REPO" == *.zip || "$CUR_REPO" == *.tar.xz ]]; then
                continue
            else
                # Unknown format
                echo "REPORT_UNKNOWN|${STAGE}|${CUR_REPO}" >> "$TMP_REPORT"
                continue
            fi

            # Update if new value differs from current
            if [[ -n "$NEW_VAL" && "$NEW_VAL" != "${!TARGET_VAR}" ]]; then
                # Вместо запуска sed, записываем параметры во временный файл задач
                echo "${TARGET_VAR}|${!TARGET_VAR}|${NEW_VAL}" >> "$STAGE_TASKS"
            fi
        done

    )

    if [[ -s "$STAGE_TASKS" ]]; then
        while IFS='|' read -r t_var old_val new_val; do
          if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
            log_debug "DEBUG_REPLACE: File=[${STAGE##*/}] Var=[${t_var}] Old=[${old_val}] New=[${new_val}]"
          fi
            # Проверяем на пустые значения, чтобы не портить файлы
            if [[ -z "$t_var" || -z "$new_val" ]]; then
                log_warn "DEBUG_ALERT: Skipped execution because variable name or new hash is empty!"
                continue
            fi
          if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
            # Показываем точную команду sed перед её выполнением
            log_debug "DEBUG_CMD: sed -i \"s@^${t_var}=\\\"[^\\\"]*\\\"@${t_var}=\\\"${new_val}\\\"@g\" \"${STAGE}\""
          fi
            # Применяем атомарный sed
            sed -i "s@^${t_var}=\"[^\"]*\"@${t_var}=\"${new_val}\"@g" "${STAGE}"
            sed -i "s@^${t_var}='[^']*'@${t_var}='${new_val}'@g" "${STAGE}"
            
            log_info "  ${SYNC_MARK} ${t_var}: ${old_val:0:7} -> ${new_val:0:7}"
            echo "REPORT_UPDATE|${STAGE}|${t_var}|${old_val}|${new_val}" >> "$TMP_REPORT"
        done < "$STAGE_TASKS"
    fi
    rm -f "$STAGE_TASKS"

    # Subshell succeeded — validate syntax
    if ! bash -n "$STAGE"; then
        log_error "${CROSS_MARK} Syntax error in ${STAGENAME}! Rolling back."
        echo "REPORT_SYNTAX|${STAGE}" >> "$TMP_REPORT"
        mv "${STAGE}.bak" "$STAGE"
    else
        rm -f "${STAGE}.bak"
    fi
done

# --- ФИНАЛЬНЫЙ ОТЧЕТ ---

# Process Shaderc DEPS (must be after regular scripts so report is complete)
update_shaderc_deps

# Final Report
phase_header "📋" "UPDATE SUMMARY"

UPDATED_FILES=()
BROKEN_REPOS=()
UNKNOWN_LAYOUTS=()
SYNTAX_ERRORS=()

# Parse report file and populate arrays
while IFS='|' read -r type file var old new; do
    case "$type" in
        REPORT_UPDATE)  UPDATED_FILES+=("${file##*/} (${var})") ;;
        REPORT_DEAD)    BROKEN_REPOS+=("${file##*/} (${var})") ;;
        REPORT_UNKNOWN) UNKNOWN_LAYOUTS+=("${file##*/}") ;;
        REPORT_SYNTAX)  SYNTAX_ERRORS+=("${file##*/}") ;;
    esac
done < "$TMP_REPORT"

# Print results
if [[ ${#UPDATED_FILES[@]} -gt 0 ]]; then
    separator "─" "  UPDATED  "
    for item in "${UPDATED_FILES[@]}"; do
        printf '%b  ✔ %s%b\n' "$LOG_INFO" "$item" "$NC" >&2
    done
fi

if [[ ${#BROKEN_REPOS[@]} -gt 0 ]]; then
    separator "─" "  DEAD REPOSITORIES  "
    for item in "${BROKEN_REPOS[@]}"; do
        printf '%b  ✖ %s%b\n' "$LOG_ERROR" "$item" "$NC" >&2
    done
fi

if [[ ${#UNKNOWN_LAYOUTS[@]} -gt 0 ]]; then
    separator "─" "  UNKNOWN LAYOUTS  "
    for item in "${UNKNOWN_LAYOUTS[@]}"; do
        printf '%b  ? %s%b\n' "$LOG_WARN" "$item" "$NC" >&2
    done
fi

if [[ ${#SYNTAX_ERRORS[@]} -gt 0 ]]; then
    separator "─" "  SYNTAX ERRORS (ROLLED BACK)  "
    for item in "${SYNTAX_ERRORS[@]}"; do
        printf '%b  ✖ %s%b\n' "$LOG_ERROR" "$item" "$NC" >&2
    done
fi

phase_footer "✔ Update process complete"

exit 0
