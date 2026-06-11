#!/bin/bash

set -e

retry-tool() {
    _retry "$@"
}
export -f retry-tool

# Вспомогательная функция для надежного выполнения сетевых команд
_retry() {
    local n=1
    local max=3
    local delay=5
    local timeout_val=300
    
    while true; do
        if timeout --kill-after=10 "$timeout_val" "$@"; then
            return 0
        else
            if [[ $n -lt $max ]]; then
                log_warn "Command failed: '$*'. Attempt $n/$max. Retrying in ${delay}s..."
                sleep "$delay"
                ((n++))
                delay=$((delay + 10))
            else
                log_error "Command '$1' failed after $max attempts: $*"
                return 1
            fi
        fi
    done
}

git-mini-clone() {
    local REPO="$1"
    local COMMIT="$2"
    local TARGET_DIR="${3:-.}"
    local BRANCH_ARG="$4"

    # resolve BRANCH and TAGFILTER for this specific REPO
    local BRANCH="$BRANCH_ARG"
    local TAGFILTER=""
    local MIRROR=""
    local MIRROR_COMMIT=""

    # Match REPO against SCRIPT_REPO, SCRIPT_REPO1..9
    local i
    for i in "" {1..9}; do
        local r_var="SCRIPT_REPO${i}"
        if [[ "${!r_var}" == "$REPO" ]]; then
            [[ -z "$BRANCH"    ]] && BRANCH="$(    eval echo "\${SCRIPT_BRANCH${i}:-}"    )"
            [[ -z "$TAGFILTER" ]] && TAGFILTER="$( eval echo "\${SCRIPT_TAGFILTER${i}:-}" )"
            MIRROR="$(        eval echo "\${SCRIPT_MIRROR${i}:-}"        )"
            MIRROR_COMMIT="$( eval echo "\${SCRIPT_MIRROR_COMMIT${i}:-}" )"
            break
        fi
    done

    # Пропуск если SVN
    [[ -n "$SCRIPT_REV" ]] && { log_warn "SVN detected, skipping git-mini-clone"; return 0; }

    mkdir -p "$TARGET_DIR"
    local OLD_PWD="$PWD"
    cd "$TARGET_DIR" || return 1
    # Cleanup on return regardless of exit path
    trap "cd '$OLD_PWD'" RETURN

    # Удаляем возможные локи от прошлых неудачных запусков
    [[ -d ".git" ]] && rm -f .git/index.lock
    # Инициализируем один раз
    [[ ! -d ".git" ]] && git init -q

    # TAGFILTER resolution (against primary repo only)
    if [[ -n "$TAGFILTER" ]]; then
        log_debug "Resolving tag with filter: $TAGFILTER"
        local RESOLVED_COMMIT
        RESOLVED_COMMIT=$(git ls-remote --tags --sort="v:refname" "$REPO" "$TAGFILTER" \
            | tail -n1 | awk '{print $1}')
        if [[ -n "$RESOLVED_COMMIT" ]]; then
            COMMIT="$RESOLVED_COMMIT"
        else
            log_error "Tag filter '$TAGFILTER' returned nothing from $REPO"
            return 1
        fi
    fi

    # fetch attempt: try one URL, return 0 on success
    _try_fetch() {
        local url="$1" commit="$2" branch="$3"
        git remote remove origin 2>/dev/null || true
        git remote add origin "$url"

        log_info "${DOWN_MARK} Fetching $(basename "$url") @ ${commit:0:12}..."

        # Direct shallow fetch of the exact commit
        if _retry git fetch --quiet --no-tags --depth=1 origin "$commit" >/dev/null 2>&1; then
            git checkout --quiet FETCH_HEAD && return 0
        fi

        # Via branch name
        if [[ -n "$branch" ]]; then
            log_warn "Direct fetch failed, trying branch '$branch' from $url"
            if _retry git fetch --quiet --no-tags --depth=1 origin "$branch" >/dev/null 2>&1; then
                git checkout --quiet "$commit" 2>/dev/null && return 0
            fi
        fi

        # Full fetch fallback
        log_warn "Shallow fetch failed, performing full fetch from $url (may be slow)..."
        if _retry git fetch --quiet --tags origin >/dev/null 2>&1 \
        || _retry git fetch --quiet origin >/dev/null 2>&1; then
            git checkout --quiet "$commit" && return 0
        fi

        return 1
    }

    # Try primary
    if _try_fetch "$REPO" "$COMMIT" "$BRANCH"; then
        return 0
    fi

    # Try mirror (only if primary failed)
    if [[ -n "$MIRROR" ]]; then
        log_warn "Primary failed. Trying mirror: $MIRROR"
        local m_commit="${MIRROR_COMMIT:-$COMMIT}"
        if _try_fetch "$MIRROR" "$m_commit" "$BRANCH"; then
            log_info "${CHECK_MARK} Mirror succeeded for $(basename "$REPO")"
            return 0
        fi
    fi

    log_error "Failed to clone $REPO @ $COMMIT (all sources exhausted)"
    return 1
}
export -f git-mini-clone

download_file() {
    local URL="$1"
    local DEST="$2"
    local SHA512="$3"
    local useragent="Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"

    mkdir -p "$(dirname "$DEST")"

    # Cache hit check BEFORE any deletion
    if [[ -f "$DEST" ]]; then
        if [[ -n "${SHA512:-}" ]]; then
            if echo "$SHA512  $DEST" | sha512sum -c --status 2>/dev/null; then
                log_info "${TARGET_MARK} File $(basename "$DEST") matches cache."
                return 0
            fi
            log_warn "Checksum mismatch for $(basename "$DEST"), re-downloading..."
            rm -f "$DEST"
        else
            log_info "${CHECK_MARK} File $(basename "$DEST") exists, skipping."
            return 0
        fi
    fi

    log_info "${DOWN_MARK} Downloading: $(basename "$DEST")"

    # -f (fail silently) возвращает код 22 при 404 и триггерит _retry
    # -I информация
    # -L (location) следовать редиректам SourceForge

    # если первая попытка провалилась (или нет pv) запускаем _retry
    if ! _retry curl -A "$useragent" \
            -fsSL --connect-timeout 15 \
            "$URL" -o "$DEST"; then
        log_error "All download attempts failed for $(basename "$DEST")"
        rm -f "$DEST"
        return 1
    fi

    # Verify the file was actually written
    if [[ ! -s "$DEST" ]]; then
        log_error "Downloaded file is empty: $(basename "$DEST")"
        rm -f "$DEST"
        return 1
    fi

    # Hash check
    if [[ -n "${SHA512:-}" ]]; then
        if ! echo "$SHA512  $DEST" | sha512sum -c --status; then
            log_error "Hash validation FAILED for $(basename "$DEST")"
            rm -f "$DEST"
            return 1
        fi
        log_info "${CHECK_MARK} Hash verified."
    fi

    return 0
}
export -f download_file

git-submodule-clone() {
    log_info "${START_MARK} Starting robust submodule synchronization..."

    # Принудительно обновляем URL подмодулей из файла .gitmodules
    # Это решает проблему, если в репозитории изменились адреса подмодулей
    log_info "${SYNC_MARK} Syncing submodules..."
    git submodule sync --recursive

    # Попытка стандартного обновления
    # --force поможет, если локально были внесены небольшие изменения
    log_info "${SYNC_MARK} Attempting standard update..."
    if _retry git submodule update --quiet --init --recursive --depth 1; then
        log_info "${CHECK_MARK} Submodules synchronized successfully via standard update."
        return 0
    fi

    # Если не помогло, пробуем более агрессивный метод
    log_warn "Standard submodule update failed, trying manual foreach..."

    # используем || return 1, чтобы если foreach упадет, функция сразу вернула ошибку
    # 1. Сброс локальных изменений, которые могут мешать checkout
    # 2. Получаем данные напрямую
    # 3. Пытаемся переключиться на нужный коммит (записанный в основном репозитории)
    # Обычно это FETCH_HEAD после fetch, если мы тянем конкретный коммит
    git submodule foreach --recursive bash -c "
        source \"\$UTIL_DIR/vars.sh\" \"\$TARGET\" \"\$VARIANT\" 2>/dev/null
        source \"\$UTIL_DIR/dl_functions.sh\"
        log_info \"Processing submodule: \$name\"
        git reset --hard HEAD && git clean -fd
        if _retry git fetch --quiet --no-tags --depth=1 origin; then
            git checkout -q FETCH_HEAD || \
            git checkout -q \$(git config -f \"\$toplevel/.gitmodules\" \
                \"submodule.\$name.branch\" 2>/dev/null || echo 'master')
        else
            log_error \"Failed to fetch submodule \$name\"
            exit 1
        fi
    "

    # Финальная проверка
    if [ $? -eq 0 ]; then
        log_info "${CHECK_MARK} Submodules synchronized after manual intervention."
        return 0
    else
        log_error "ERROR: Could not synchronize submodules."
        return 1
    fi
}

svn-mini-clone() {
    local REPO="$1"
    local REV="${2:-HEAD}"
    local TARGET_DIR="${3:-.}"

    [[ -z "$REV" ]] && REV="HEAD"

    log_info "Fetching SVN: $REPO@$REV"
    mkdir -p "$TARGET_DIR"

    # Добавляем --username 'anonymous' и --password ''
    # Добавляем --trust-server-cert для обхода проблем с SSL
    if _retry svn export --non-interactive \
        --username 'anonymous' --password '' \
        --trust-server-cert \
        --trust-server-cert-failures=unknown-ca,cn-mismatch,expired,not-yet-valid,other \
        "$REPO@$REV" "$TARGET_DIR" --force --quiet; then
        log_info "${CHECK_MARK} SVN export successful."
        return 0
    else
        log_error "ERROR: Failed to export SVN: $REPO (Check credentials or URL)"
        return 1
    fi
}

default_dl() {
    local TARGET_DIR="${1:-.}"

    # Если задан SVN
    if [[ -n "$SCRIPT_REV" ]]; then
        echo "svn-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_REV\" \"$TARGET_DIR\""
        return 0
    fi

    # Иначе работаем с Git
    local CMDS=()
    
    # Primary repo → TARGET_DIR
    if [[ -n "$SCRIPT_REPO" ]]; then
        local BASE_COMMIT="${SCRIPT_COMMIT:-master}"
        CMDS+=( "git-mini-clone \"$SCRIPT_REPO\" \"$BASE_COMMIT\" \"$TARGET_DIR\"" )
    fi

    # SCRIPT_REPO1..9 → each clones into its own named subdir
    # (these are *additional* repos, not mirrors — mirrors are handled inside git-mini-clone)
    for i in {1..9}; do
        local r_var="SCRIPT_REPO${i}"
        local c_var="SCRIPT_COMMIT${i}"
        local d_var="SCRIPT_DIR${i}"   # optional explicit subdir name
        [[ -z "${!r_var}" ]] && continue

        local sub_commit="${!c_var:-${SCRIPT_COMMIT:-master}}"
        # Use explicit SCRIPT_DIR{i} if set, otherwise derive from repo basename
        local sub_dir
        if [[ -n "${!d_var}" ]]; then
            sub_dir="${TARGET_DIR}/${!d_var}"
        else
            sub_dir="${TARGET_DIR}/$(basename "${!r_var}" .git)"
        fi
        CMDS+=( "git-mini-clone \"${!r_var}\" \"$sub_commit\" \"$sub_dir\"" )
    done

    # Валидация
    if [[ ${#CMDS[@]} -eq 0 ]]; then
        # Пишем в stderr, чтобы не сломать eval/stdout
        log_error "No SCRIPT_REPO defined for stage!" >&2
        return 1
    fi

    # All commands run sequentially; any failure aborts the chain
    local IFS=$'\n'
    printf '%s\n' "${CMDS[@]}"
}
export -f default_dl

# ---------------------------------------------------------------------------
# configs Hash file is keyed on STAGE_HASH — when you pin a new commit in the build script, STAGE_HASH changes, the old .confhash is simply ignored and a new baseline is written. No false positives from script-only changes.
# ${STAGENAME}_${STAGE_HASH}.confhash   # stored alongside .tar.zst in CACHE_DIR
# Options are sorted before hashing — reordering options in upstream source doesn't trigger a change alert.
# 
# confhash_extract_options prefixes each option with its build system (autotools:, cmake:, meson:) — this means a cmake:BUILD_TESTS and a meson:build_tests are tracked separately, which matters when a project migrates build systems.
# 
# .confopts file is only written at FFBUILD_VERBOSE >= 2 on first save — keeps cache clean by default. The diff is only computed when you explicitly want it.
# 
# confhash_compute returns 1 silently if no config files are found — meta-packages and header-only stages are skipped without noise.
#
# confhash_compute  <src_dir>
#
# Finds build-system config files in <src_dir>, extracts recognised option
# declarations, strips noise, and returns a stable SHA-256 hash on stdout.
# Prints nothing and returns 1 if no config files were found.
# ---------------------------------------------------------------------------
confhash_compute() {
    local src_dir="$1"
    [[ -d "$src_dir" ]] || return 1

    local raw_options
    raw_options=$(confhash_extract_options "$src_dir") || true

    # Temporary debug
    # if print is not working
    # find "$src_dir" -maxdepth 8 \( ... \) 2>/dev/null | sed "s|^$src_dir||" | head -n 20 >&2
    if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
        log_debug "confhash: scanning $(basename "$src_dir")"
        find "$src_dir" -maxdepth 8 \
            \( -name "configure.ac" \
            -o -name "CMakeLists.txt" \
            -o -name "meson_options.txt" \) \
            -not -path "*/test/*" \
            -not -path "*/tests/*" \
            -not -path "*/example/*" \
            -not -path "*/examples/*" \
            -printf "/%P\n" 2>/dev/null | head -n 20 >&2
    fi

    if [[ -z "$raw_options" ]]; then
        # Если файлов нет совсем — возвращаем 1
        local found_files=$(find "$src_dir" -maxdepth 6 \( -name "configure.ac" -o -name "CMakeLists.txt" -o -name "meson_options.txt" -o -name "CMakeOptions.txt" -o -name "DefineOptions.cmake" \) | wc -l)
        [[ "$found_files" -eq 0 ]] && return 1

        # Files were found but no options extracted — still save a hash
        # so we can detect when options ARE added in the future
        printf 'no-options' | sha256sum | cut -c1-16
        return 0
    fi

    # Stable hash: sort + deduplicate so option order changes don't matter
    printf '%s' "$raw_options" | sed 's/^[^:]*://' | sort -u | sha256sum | cut -c1-16
}
export -f confhash_compute

# ---------------------------------------------------------------------------
# confhash_extract_options  <src_dir>
#
# Same as confhash_compute but prints the sorted, deduplicated option list
# to stdout instead of a hash. Used for verbose diff output.
# ---------------------------------------------------------------------------
confhash_extract_options() {
    local src_dir="$1"
    [[ -d "$src_dir" ]] || return 1
    local opts=""

    # Autotools
    # use only configure.ac, for now. del "-o -name "configure.in"" \)"
    while IFS= read -r -d '' f; do
        # VERSION a)
        # local chunk=$(grep -oP 'AS_HELP_STRING\(\s*\[\s*--[a-zA-Z][a-zA-Z0-9_-]*' "$f" | grep -oP -- '--[a-zA-Z][a-zA-Z0-9_-]*' 2>/dev/null || true)
        # [[ -n "$chunk" ]] && raw_options+="autotools:$chunk"$'\n'
    # done < <(find "$src_dir" -maxdepth 8 \
               # \( -name "configure.ac" -o -name "configure.in" \) \
               # -print0 2>/dev/null)
        # VERSION b)
        local chunk=$(grep -oP '(?:AC_ARG_ENABLE|AC_ARG_WITH|AS_HELP_STRING)\(\s*\[?\K--[a-zA-Z0-9_-]+' "$f" 2>/dev/null)
        [[ -n "$chunk" ]] && while read -r line; do opts+="autotools:$line"$'\n'; done <<< "$chunk"
    done < <(find "$src_dir" -maxdepth 6 \( -name "configure.ac" -o -name "configure.in" \) -print0 2>/dev/null)

    # CMake
    # use only CMakeLists.txt, for now. del "-o -name "*.cmake" \)"
    while IFS= read -r -d '' f; do
        # VERSION a)
        # local chunk=$(grep -oP '(?i)(?:cmake_dependent_)?option\(\s*\K[A-Z_][A-Z0-9_]+' "$f" 2>/dev/null || true)
        # [[ -n "$chunk" ]] && raw_options+="cmake:$chunk"$'\n'
    # done < <(find "$src_dir" -maxdepth 8 \
               # \( -name "CMakeLists.txt" -o -name "CMakeOptions.txt" \) \
               # -print0 2>/dev/null)
        # VERSION b)
        local chunk=$(grep -oP '(?i)(?:cmake_dependent_)?option\(\s*\K[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null)
        [[ -n "$chunk" ]] && while read -r line; do opts+="cmake:$line"$'\n'; done <<< "$chunk"
    done < <(find "$src_dir" -maxdepth 6 \( -name "CMakeLists.txt" -o -name "CMakeOptions.txt" -o -name "DefineOptions.cmake" \) -print0 2>/dev/null)

    # use only meson_options.txt, for now. del "-o -name "meson.build" " \)"
    while IFS= read -r -d '' f; do
        # VERSION a)
        # local chunk=$(grep -oP "option\(\s*'\K[a-zA-Z][a-zA-Z0-9_-]+" "$f" 2>/dev/null || true)
        # [[ -n "$chunk" ]] && raw_options+="meson:$chunk"$'\n'
    # done < <(find "$src_dir" -maxdepth 8 \
               # \( -name "meson_options.txt" \) \
               # -print0 2>/dev/null)
        # VERSION b)
        local chunk=$(grep -oP "option\(\s*['\"]?\K[a-zA-Z][a-zA-Z0-9_-]+" "$f" 2>/dev/null)
        [[ -n "$chunk" ]] && while read -r line; do opts+="meson:$line"$'\n'; done <<< "$chunk"
    done < <(find "$src_dir" -maxdepth 6 \( -name "meson_options.txt" -o -name "meson.build" \) -print0 2>/dev/null)

    [[ -z "$opts" ]] && return 1
    echo -n "$opts" | sort -u
}
export -f confhash_extract_options

download_stage() {
    local STAGE="$1"
    local CACHE_DIR="${2:-$CACHE_DIR}"

    local STAGE_HASH STAGENAME COMPONENT_NAME STAGE_CACHE_FILE STAGE_LATEST_LINK
    eval "$(stage_vars "$STAGE")"

    local DL_COMMANDS="$(bash --norc --noprofile -c "
        source \"${UTIL_DIR}/vars.sh\" \"${TARGET}\" \"${VARIANT}\" >/dev/null 2>&1
        source \"${UTIL_DIR}/dl_functions.sh\"
        source \"${STAGE}\"
        ffbuild_enabled || exit 0
        ffbuild_dockerdl
    " 2>"/tmp/dl_cmd_err_${STAGENAME}" || true)"

    # Если команд нет — это стадия без исходников (мета-пакет), выходим
    if [[ -z "$DL_COMMANDS" ]]; then
        # Log any real error from the subshell
        [[ -s "/tmp/dl_cmd_err_${STAGENAME}" ]] && \
            log_warn "dl subshell stderr for ${STAGENAME}:" && \
            cat "/tmp/dl_cmd_err_${STAGENAME}" >&2
        rm -f "/tmp/dl_cmd_err_${STAGENAME}"
        return 0  # meta-package, nothing to download
    fi
    rm -f "/tmp/dl_cmd_err_${STAGENAME}"

    # Проверяем, что у нас есть путь к кэшу, иначе упадем на mkdir/tar
    if [[ -z "$CACHE_DIR" ]]; then
        log_error "CACHE_DIR is empty! Check if vars.sh is sourced."
        return 1
    fi

    # Debug: show keep-list only at verbose >= 2
    if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
        log_info "${DIRS_MARK} Files in cache for $STAGENAME:"
        ls -F "$CACHE_DIR" 2>/dev/null | grep "$STAGENAME" || log_warn "No files matching $STAGENAME found!"
    fi

    # Cache hit
    if [[ -f "$STAGE_CACHE_FILE" ]]; then
        local size
        size=$(du -sh "$STAGE_CACHE_FILE" | cut -f1)
        dl_result_line "hit" "$STAGENAME" "$STAGE_HASH" "$size"
        touch "$STAGE_CACHE_FILE"
        ln -sf "$(basename "$STAGE_CACHE_FILE")" "$STAGE_LATEST_LINK"
        return 0
    fi

    # Cache miss
    local miss_reason="no archive"
    [[ -L "$STAGE_LATEST_LINK" ]] && miss_reason="hash changed → ${STAGE_HASH:0:8}"
    dl_result_line "miss" "$STAGENAME" "$STAGE_HASH" "$miss_reason"
    log_warn "Cache miss: $STAGENAME ($miss_reason). ${DOWN_MARK} Re-downloading..."

    # Use subshell for cleanup isolation — avoids clobbering EXIT trap
    local WORK_DIR
    WORK_DIR=$(mktemp -d -p "$TMP_DIR")
    # Очистка при выходе. Удаляем только WORK_DIR конкретного процесса, а не весь TMP_DIR! Иначе параллельные процессы удалят чужие папки.
    # trap 'rm -rf "$WORK_DIR"' EXIT

    # Выполняем загрузку
    local dl_status=0
    (   cd "$WORK_DIR" || exit 1
        eval "$DL_COMMANDS"
    ) || dl_status=$?

    if [[ $dl_status -eq 0 ]]; then
        (
            cd "$WORK_DIR" || exit 0
            if [[ -f "$STAGE" ]]; then
                source "$STAGE"
            else
                source "${ROOT_DIR}/${STAGE}" 2>/dev/null || true
            fi
            log_info "Running version auto-detection for ${STAGENAME}..."
            get_stage_version > /dev/null
        )

        # Whitelist метаданных .git (список подгружается из workflow.yaml). 
        if [[ "$STAGENAME" =~ $GIT_PRESERVE_LIST ]]; then
            log_info "${LOCK_MARK} Preserving Git metadata for $STAGENAME (Whitelist match)"
        else
            log_debug "${BROOM_MARK} Stripping Git metadata for $STAGENAME to save cache space"
            # Удаляем .git папки и .gitignore файлы
            find "$WORK_DIR" -maxdepth 8 -name ".git*" -exec rm -rf {} + 2>/dev/null || true
        fi

        # Config option changes tracing and hashing
        # Path for the hash file sits next to the .tar.zst, never inside it
        local CONF_HASH_FILE="${CACHE_DIR}/${STAGENAME}_${STAGE_HASH}.confhash"
        local CONF_OPTIONS_FILE="${CACHE_DIR}/${STAGENAME}_${STAGE_HASH}.confopts"
        local new_conf_hash=$(confhash_compute "$WORK_DIR") || true
        if [[ -n "$new_conf_hash" ]]; then
            if [[ -f "$CONF_HASH_FILE" ]]; then
                local old_conf_hash=$(cat "$CONF_HASH_FILE")
                if [[ "$old_conf_hash" == "$new_conf_hash" ]]; then
                    log_info "${CHECK_MARK} Config options unchanged for $STAGENAME (hash: ${new_conf_hash})"
                else
                    log_warn "${XCLAM_MARK} Config options CHANGED for $STAGENAME"
                    log_warn "  old: ${old_conf_hash}  →  new: ${new_conf_hash}"
                    # Verbose=2: show which options appeared/disappeared
                    if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
                        local old_opts_file="${CACHE_DIR}/${STAGENAME}_${STAGE_HASH}.confopts.prev"

                        # Recover old option list if it was saved
                        if [[ -f "$CONF_OPTIONS_FILE" ]]; then
                            cp "$CONF_OPTIONS_FILE" "$old_opts_file"
                        fi

                        local new_opts=$(confhash_extract_options "$WORK_DIR") || true
                        if [[ -f "$old_opts_file" && -n "$new_opts" ]]; then
                            local added removed
                            added=$(comm  -13 <(sort "$old_opts_file") <(echo "$new_opts" | sort))
                            removed=$(comm -23 <(sort "$old_opts_file") <(echo "$new_opts" | sort))
                            if [[ -n "$added" ]]; then
                                log_debug "${LOG_INFO}  ++ NEW options:${NC}"
                                while IFS= read -r opt; do
                                    log_debug "     ${LOG_INFO}+${NC} $opt"
                                done <<< "$added"
                            fi
                            if [[ -n "$removed" ]]; then
                                log_debug "${LOG_WARN}  -- REMOVED options:${NC}"
                                while IFS= read -r opt; do
                                    log_debug "     ${LOG_WARN}-${NC} $opt"
                                done <<< "$removed"
                            fi
                            rm -f "$old_opts_file"
                        elif [[ -n "$new_opts" ]]; then
                            log_debug "  (no previous option list saved — diff unavailable)"
                        fi
                        # Save new option list for next run
                        printf '%s\n' "$new_opts" > "$CONF_OPTIONS_FILE"
                    fi
                    # Overwrite with new hash
                    printf '%s' "$new_conf_hash" > "$CONF_HASH_FILE"
                fi
            else
                # First time seeing this component — just save, no comparison
                printf '%s' "$new_conf_hash" > "$CONF_HASH_FILE"
                local current_opts=$(confhash_extract_options "$WORK_DIR") || true
                if [[ -n "$current_opts" ]]; then
                    echo "$current_opts" > "$CONF_OPTIONS_FILE"
                    log_info "${SAVE_MARK} Config option hash saved for $STAGENAME (${new_conf_hash})"
                    # Принудительный вывод найденных опций в лог (уровень INFO или DEBUG)
                    if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
                        log_debug "${SEARCH_MARK} Detected options for $STAGENAME:"
                        while IFS= read -r opt; do
                            # Подсветка: синим название системы, обычным — опция
                            local sys="${opt%%:*}"
                            local name="${opt#*:}"
                            log_debug "${BLUE}${sys}${NC}: ${name}"
                        done <<< "$current_opts"
                    fi
                else
                    log_info "${SAVE_MARK} Hash saved (no options found)."
                fi
                log_info "${SAVE_MARK} Config option hash saved for $STAGENAME (${new_conf_hash})"
            fi
        else
            log_debug "No recognisable config files found for $STAGENAME — skipping confhash"
        fi

        # Упаковка
        mkdir -p "$(dirname "$STAGE_CACHE_FILE")"
        # -c: создать, -f: файл, -I 'zstd -T0 -3': -T0 задействует все ядра, -3 — оптимальный баланс скорости/сжатия
        tar -I 'zstd -T0 -3' -cf "$STAGE_CACHE_FILE" -C "$WORK_DIR" .
        ln -sf "$(basename "$STAGE_CACHE_FILE")" "$STAGE_LATEST_LINK"
        local final_size=$(du -sh "$STAGE_CACHE_FILE" | cut -f1)
        # Update the result line from miss → cached (overwrite by appending corrected line)
        dl_result_line "miss" "$STAGENAME" "$STAGE_HASH" "downloaded → ${final_size}"
        log_info "${CACHE_MARK} Cached $STAGENAME (${final_size})"
        rm -rf "$WORK_DIR"
        return 0
    else
        dl_result_line "fail" "$STAGENAME" "$STAGE_HASH" "download failed"
        log_error "FAILED to download $STAGENAME"
        [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && log_debug "$DL_COMMANDS"
        rm -rf "$WORK_DIR"
        return 1
    fi
}
export -f download_stage
