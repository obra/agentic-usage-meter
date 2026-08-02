#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo 'usage: extract-release-notes.sh VERSION CHANGELOG' >&2
    exit 64
fi

version=$1
changelog=$2
/usr/bin/awk -v version="${version}" '
    $1 == "##" {
        capturing = 0
        if ($2 == version) {
            matches += 1
            if (matches == 1) {
                capturing = 1
            }
        }
    }
    capturing {
        section[++line_count] = $0
    }
    END {
        if (matches != 1) {
            exit 1
        }
        for (line = 1; line <= line_count; line += 1) {
            print section[line]
        }
    }
' "${changelog}"
