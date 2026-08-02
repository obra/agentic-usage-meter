#!/bin/zsh

set -euo pipefail

process_name=$1
application_path=$2
pkill_bin=${PKILL_BIN:-/usr/bin/pkill}
pgrep_bin=${PGREP_BIN:-/usr/bin/pgrep}
sleep_bin=${SLEEP_BIN:-/bin/sleep}
open_bin=${OPEN_BIN:-/usr/bin/open}
maximum_exit_checks=100
exit_check_interval=0.05

"${pkill_bin}" -x "${process_name}" 2>/dev/null || true

for _ in {1..${maximum_exit_checks}}; do
    if "${pgrep_bin}" -x "${process_name}" >/dev/null 2>&1; then
        "${sleep_bin}" "${exit_check_interval}"
        continue
    else
        pgrep_status=$?
    fi

    if (( pgrep_status == 1 )); then
        "${open_bin}" "${application_path}"
        exit 0
    fi

    echo "Unable to inspect ${process_name} before relaunch." >&2
    exit "${pgrep_status}"
done

echo "Relaunch timeout: ${process_name} did not exit." >&2
exit 1
