#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
application_path="${repository_root}/build/Agentic Usage Meter.app"
executable_name="AgenticUsageMeter"

if [[ -n "${LOCAL_SIGNING_IDENTITY:-}" ]]; then
    signing_identity=${LOCAL_SIGNING_IDENTITY}
else
    signing_identity=$(
        /usr/bin/security find-identity -v -p codesigning \
            | "${script_directory}/select-local-signing-identity.sh"
    )
fi

"${script_directory}/assemble-app.sh"
"${script_directory}/sign-app.sh" \
    "${application_path}" \
    "${signing_identity}"
/usr/bin/codesign \
    --verify \
    --deep \
    --strict \
    --verbose=2 \
    "${application_path}"

"${script_directory}/relaunch-application.sh" \
    "${executable_name}" \
    "${application_path}"

echo "Launched ${application_path} signed as ${signing_identity}"
