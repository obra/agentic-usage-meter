#!/bin/zsh

set -euo pipefail

/usr/bin/awk -F '"' '
    /"Developer ID Application: / {
        identities[++count] = $2
    }
    END {
        if (count != 1) {
            exit 1
        }
        print identities[1]
    }
'
