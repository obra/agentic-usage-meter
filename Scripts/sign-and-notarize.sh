#!/bin/zsh

set -euo pipefail

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the exact signing identity.}"
: "${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to an existing notarytool Keychain profile.}"

script_directory=${0:A:h}
repository_root=${script_directory:h}
application_path="${repository_root}/build/Agentic Usage Meter.app"
archive_path="${repository_root}/build/Agentic Usage Meter.zip"

"${script_directory}/assemble-app.sh"

/usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "${DEVELOPER_ID_APPLICATION}" \
    "${application_path}"

/bin/rm -f "${archive_path}"
/usr/bin/ditto \
    -c \
    -k \
    --keepParent \
    "${application_path}" \
    "${archive_path}"

/usr/bin/xcrun notarytool submit \
    "${archive_path}" \
    --keychain-profile "${NOTARYTOOL_PROFILE}" \
    --wait
/usr/bin/xcrun stapler staple "${application_path}"

"${script_directory}/verify-release.sh" "${application_path}"
