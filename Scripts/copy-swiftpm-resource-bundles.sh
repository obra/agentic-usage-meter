#!/bin/zsh

set -euo pipefail

binary_directory=$1
application_bundle=$2
resource_bundle_name="AgenticUsageMeter_UsageMeterUI.bundle"
source_bundle="${binary_directory}/${resource_bundle_name}"
resources_directory="${application_bundle}/Contents/Resources"

if [[ ! -d "${source_bundle}" ]]; then
    echo "Missing SwiftPM resource bundle: ${source_bundle}" >&2
    exit 1
fi

/bin/mkdir -p "${resources_directory}"
/bin/cp -R \
    "${source_bundle}" \
    "${resources_directory}/${resource_bundle_name}"
