#!/bin/bash
set -eo pipefail
cd "$(dirname "$0")"

# Instead of running download.sh simply hash the contents of all build scripts.
# If change the URL or commit in any .sh script, the hash will change and the cache will be reset.
find scripts.d variants addins -type f -name "*.sh" -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d" " -f1
