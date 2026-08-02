#!/bin/zsh

set -euo pipefail

repository_root=$1
application_bundle=$2
application_executable=$3
source_framework="${repository_root}/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
frameworks_directory="${application_bundle}/Contents/Frameworks"
install_name_tool_bin=${INSTALL_NAME_TOOL_BIN:-/usr/bin/install_name_tool}

[[ -d "${source_framework}" ]] || {
    echo "Missing Sparkle framework: ${source_framework}" >&2
    exit 1
}
[[ -f "${application_executable}" ]] || {
    echo "Missing application executable: ${application_executable}" >&2
    exit 1
}

/bin/mkdir -p "${frameworks_directory}"
/bin/cp -R \
    "${source_framework}" \
    "${frameworks_directory}/Sparkle.framework"
"${install_name_tool_bin}" \
    -add_rpath '@executable_path/../Frameworks' \
    "${application_executable}"
