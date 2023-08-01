#!/bin/bash
set -xe

RETRY_COUNTER=0
MAX_RETRY=50
CUR_TIMEOUT=2000
while [[ $RETRY_COUNTER -lt $MAX_RETRY ]]; do
    timeout $CUR_TIMEOUT "$@" && break || sleep $(shuf -i 5-90 -n 1)
    RETRY_COUNTER=$(( $RETRY_COUNTER + 1 ))
    CUR_TIMEOUT=$(( $CUR_TIMEOUT + 120 ))
    echo "Retry $RETRY_COUNTER..."
done
if [[ $RETRY_COUNTER -ge $MAX_RETRY ]]; then
    echo "Max retry count exceeded."
    exit 1
fi
