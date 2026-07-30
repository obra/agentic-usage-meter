#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
configuration=${CONFIGURATION:-release}
application_name="Agentic Usage Meter"
bundle_path="${repository_root}/build/${application_name}.app"
contents_path="${bundle_path}/Contents"
executable_name="AgenticUsageMeter"

swift build \
    --package-path "${repository_root}" \
    --configuration "${configuration}" \
    --product "${executable_name}"
binary_directory=$(
    swift build \
        --package-path "${repository_root}" \
        --configuration "${configuration}" \
        --show-bin-path
)

/bin/rm -rf "${bundle_path}"
/bin/mkdir -p "${contents_path}/MacOS" "${contents_path}/Resources"
/bin/cp \
    "${repository_root}/Resources/Info.plist" \
    "${contents_path}/Info.plist"
/bin/cp \
    "${binary_directory}/${executable_name}" \
    "${contents_path}/MacOS/${executable_name}"
/bin/chmod 755 "${contents_path}/MacOS/${executable_name}"

echo "${bundle_path}"
