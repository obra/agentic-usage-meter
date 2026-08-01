#!/bin/zsh

set -euo pipefail

/usr/bin/awk -F '"' '
    /"Developer ID Application: / {
        found = 1
        print $2
        exit
    }
    END {
        if (!found) {
            exit 1
        }
    }
'
