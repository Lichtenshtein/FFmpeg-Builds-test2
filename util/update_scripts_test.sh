#!/bin/bash

set -eo pipefail
shopt -s globstar
export LC_ALL=C

cd "$(dirname "$0")"/..

# Можно передать маску файла, например: ./util/update_scripts.sh "scripts.d/50-x264.sh"
SEARCH_PATTERN="${1:-scripts.d/**/*.sh}"

for scr in $SEARCH_PATTERN; do
    [[ -f "$scr" ]] || continue
    echo -e "\033[1;32m[PROCESS]\033[0m Checking ${scr}..."
    
    # Создаем бэкап на случай ошибки
    cp "$scr" "${scr}.bak"

    (
        source "$scr"
        [[ -n "$SCRIPT_SKIP" ]] && exit 0

        for i in "" $(seq 2 9); do
            REPO_VAR="SCRIPT_REPO$i"; COMMIT_VAR="SCRIPT_COMMIT$i"
            CUR_REPO="${!REPO_VAR}"; CUR_COMMIT="${!COMMIT_VAR}"

            if [[ -z "${CUR_REPO}" ]]; then
                [[ -z "$i" ]] && echo "# FIXME: No repo" >> "$scr"
                break
            fi

            # Логика для GIT (самая частая)
            if [[ -n "${CUR_COMMIT}" ]]; then
                BRANCH_VAR="SCRIPT_BRANCH$i"; TAG_VAR="SCRIPT_TAGFILTER$i"
                CUR_BRANCH="${!BRANCH_VAR}"; CUR_TAG="${!TAG_VAR}"

                if [[ -n "${CUR_TAG}" ]]; then
                    NEW_COMMIT=$(git -c 'versionsort.suffix=-' ls-remote --tags --refs --sort "v:refname" "${CUR_REPO}" "${CUR_TAG}" | tail -n1 | awk '{print $1}')
                else
                    [[ -z "${CUR_BRANCH}" ]] && CUR_BRANCH=$(git remote show "${CUR_REPO}" 2>/dev/null | grep "HEAD branch:" | cut -d":" -f2 | xargs || echo "master")
                    NEW_COMMIT=$(git ls-remote --heads "${CUR_REPO}" "refs/heads/${CUR_BRANCH}" | cut -f1)
                fi

                if [[ -n "${NEW_COMMIT}" && "${NEW_COMMIT}" != "${CUR_COMMIT}" ]]; then
                    echo -e "  \033[1;33m[UPDATE]\033[0m ${COMMIT_VAR}: ${CUR_COMMIT:0:7} -> ${NEW_COMMIT:0:7}"
                    # Используем более строгий sed, чтобы менять только присваивание
                    sed -i "s|^${COMMIT_VAR}=.*|${COMMIT_VAR}=\"${NEW_COMMIT}\"|" "${scr}"
                fi
            fi
        done
    )

    # ПРОВЕРКА: не сломали ли мы синтаксис bash?
    if ! bash -n "$scr"; then
        echo -e "  \033[1;31m[ERROR]\033[0m Syntax error after update! Rolling back ${scr}."
        mv "${scr}.bak" "$scr"
    else
        rm -f "${scr}.bak"
    fi
done
