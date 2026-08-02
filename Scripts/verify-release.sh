#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
application_path=${1:-"${repository_root}/build/Agentic Usage Meter.app"}
sparkle_framework="${application_path}/Contents/Frameworks/Sparkle.framework"
application_executable="${application_path}/Contents/MacOS/AgenticUsageMeter"

/usr/bin/codesign \
    --verify \
    --deep \
    --strict \
    --verbose=2 \
    "${application_path}"

signable_sparkle_components=(
    "${sparkle_framework}"
    "${sparkle_framework}/Versions/B/Updater.app"
    "${sparkle_framework}/Versions/B/XPCServices/Installer.xpc"
    "${sparkle_framework}/Versions/B/XPCServices/Downloader.xpc"
)
for component in "${signable_sparkle_components[@]}"; do
    /usr/bin/codesign \
        --verify \
        --strict \
        --verbose=2 \
        "${component}"
done

/usr/sbin/spctl \
    --assess \
    --type execute \
    --verbose=2 \
    "${application_path}"
/usr/bin/xcrun stapler validate "${application_path}"

sparkle_linkage=$(/usr/bin/otool -L "${application_executable}")
print -r -- "${sparkle_linkage}"
[[ "${sparkle_linkage}" == *"@rpath/Sparkle.framework/Versions/B/Sparkle"* ]] || {
    echo "Application executable does not link Sparkle through @rpath." >&2
    exit 1
}
[[ "${sparkle_linkage}" != *".build/"* ]] || {
    echo "Application executable links Sparkle from the SwiftPM build directory." >&2
    exit 1
}
