#!/bin/zsh

set -euo pipefail

application_path=$1
signing_identity=$2
codesign_bin=${CODESIGN_BIN:-/usr/bin/codesign}
sparkle_framework="${application_path}/Contents/Frameworks/Sparkle.framework"
signing_arguments=(--force --options runtime)
if [[ "${RELEASE_SIGNING:-0}" == 1 ]]; then
    signing_arguments+=(--timestamp)
else
    signing_arguments+=(--timestamp=none)
fi
signing_arguments+=(--sign "${signing_identity}")

nested_targets=(
    "${sparkle_framework}/Versions/B/XPCServices/Installer.xpc"
    "${sparkle_framework}/Versions/B/XPCServices/Downloader.xpc"
    "${sparkle_framework}/Versions/B/Autoupdate"
    "${sparkle_framework}/Versions/B/Updater.app"
    "${sparkle_framework}"
)
for target in "${nested_targets[@]}"; do
    [[ -e "${target}" ]] || {
        echo "Missing signable Sparkle component: ${target}" >&2
        exit 1
    }
    "${codesign_bin}" "${signing_arguments[@]}" "${target}"
done

while IFS= read -r -d '' resource_bundle; do
    "${codesign_bin}" "${signing_arguments[@]}" "${resource_bundle}"
done < <(
    /usr/bin/find \
        "${application_path}/Contents/Resources" \
        -type d -name '*.bundle' -print0
)

"${codesign_bin}" \
    "${signing_arguments[@]}" \
    "${application_path}/Contents/MacOS/AgenticUsageMeter"
"${codesign_bin}" \
    "${signing_arguments[@]}" \
    "${application_path}"
