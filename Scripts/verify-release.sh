#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
repository_root=${script_directory:h}
application_path=${1:-"${repository_root}/build/Agentic Usage Meter.app"}

/usr/bin/codesign \
    --verify \
    --deep \
    --strict \
    --verbose=2 \
    "${application_path}"
/usr/sbin/spctl \
    --assess \
    --type execute \
    --verbose=2 \
    "${application_path}"
/usr/bin/xcrun stapler validate "${application_path}"
