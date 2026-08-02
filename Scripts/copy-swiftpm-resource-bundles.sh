#!/bin/zsh

set -euo pipefail

binary_directory=$1
application_bundle=$2
resource_bundle_name="AgenticUsageMeter_UsageMeterUI.bundle"
source_bundle="${binary_directory}/${resource_bundle_name}"
resources_directory="${application_bundle}/Contents/Resources"
copied_bundle="${resources_directory}/${resource_bundle_name}"

if [[ ! -d "${source_bundle}" ]]; then
    echo "Missing SwiftPM resource bundle: ${source_bundle}" >&2
    exit 1
fi

/bin/mkdir -p "${resources_directory}"
/bin/cp -R \
    "${source_bundle}" \
    "${copied_bundle}"

bundle_info_plist="${copied_bundle}/Info.plist"
/usr/bin/plutil -create xml1 "${bundle_info_plist}"
/usr/bin/plutil \
    -insert CFBundleIdentifier \
    -string com.fsck.agentic-usage-meter.resources \
    "${bundle_info_plist}"
/usr/bin/plutil \
    -insert CFBundleName \
    -string "Usage Meter Resources" \
    "${bundle_info_plist}"
/usr/bin/plutil \
    -insert CFBundlePackageType \
    -string BNDL \
    "${bundle_info_plist}"
/usr/bin/plutil \
    -insert CFBundleVersion \
    -string 1 \
    "${bundle_info_plist}"
