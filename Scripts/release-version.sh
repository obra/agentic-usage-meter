#!/bin/zsh
set -euo pipefail

version_pattern='^v(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$'
if [[ $# -ne 1 || ! $1 =~ $version_pattern ]]; then
    echo 'usage: release-version.sh vMAJOR.MINOR.PATCH' >&2
    exit 64
fi

major=${match[1]}
minor=${match[2]}
patch=${match[3]}
version="${major}.${minor}.${patch}"
build=$((10#${major} * 1000000 + 10#${minor} * 1000 + 10#${patch}))
/usr/bin/printf '%s\t%d\n' "${version}" "${build}"
