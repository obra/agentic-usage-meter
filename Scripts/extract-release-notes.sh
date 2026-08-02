#!/bin/zsh
set -euo pipefail

version=$1
changelog=$2
/usr/bin/awk -v version="${version}" '
    $1 == "##" && $2 == version {
        found = 1
    }
    found && $1 == "##" && $2 != version {
        exit
    }
    found {
        print
    }
    END {
        if (!found) {
            exit 1
        }
    }
' "${changelog}"
