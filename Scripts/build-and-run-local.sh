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
/usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --sign "${signing_identity}" \
    "${application_path}"
/usr/bin/codesign \
    --verify \
    --deep \
    --strict \
    --verbose=2 \
    "${application_path}"

/usr/bin/pkill -x "${executable_name}" 2>/dev/null || true
/usr/bin/open "${application_path}"

echo "Launched ${application_path} signed as ${signing_identity}"
