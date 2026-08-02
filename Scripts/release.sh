#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo 'usage: release.sh vMAJOR.MINOR.PATCH' >&2
    exit 64
fi

tag=$1
script_directory=${0:A:h}
repository_root=${script_directory:h}
git_bin=${GIT_BIN:-git}
gh_bin=${GH_BIN:-gh}
security_bin=${SECURITY_BIN:-/usr/bin/security}
xcrun_bin=${XCRUN_BIN:-/usr/bin/xcrun}
swift_bin=${SWIFT_BIN:-swift}
ditto_bin=${DITTO_BIN:-/usr/bin/ditto}
cd "${repository_root}"

require_local_release_state() {
    [[ -z "$("${git_bin}" status --porcelain)" ]] || {
        echo 'Release requires a clean worktree.' >&2
        exit 1
    }
    [[ "$(
        "${git_bin}" cat-file -t "${tag}" 2>/dev/null || true
    )" == tag ]] || {
        echo "${tag} must be an annotated tag." >&2
        exit 1
    }
    tag_commit=$("${git_bin}" rev-parse "${tag}^{commit}")
    [[ "${tag_commit}" == "$("${git_bin}" rev-parse HEAD)" ]] || {
        echo "${tag} does not point to HEAD." >&2
        exit 1
    }
    local_tag_object=$("${git_bin}" rev-parse "${tag}")
}

require_remote_tag() {
    remote_tag=$(
        "${git_bin}" ls-remote --tags origin "refs/tags/${tag}"
    ) || {
        echo "Could not verify remote tag ${tag}." >&2
        exit 1
    }
    [[ -n "${remote_tag}" ]] || {
        echo "${tag} must already exist on origin." >&2
        exit 1
    }
    [[ "${remote_tag}" == \
        "${local_tag_object}"$'\t'"refs/tags/${tag}" ]] || {
        echo "Remote tag ${tag} does not match the local annotated tag." >&2
        exit 1
    }
}

ensure_real_directory() {
    local directory=$1
    local expected_path=$2
    [[ ! -L "${directory}" ]] || {
        echo "Refusing symlinked release parent: ${directory}" >&2
        exit 1
    }
    if [[ -e "${directory}" ]]; then
        [[ -d "${directory}" ]] || {
            echo "Release parent is not a directory: ${directory}" >&2
            exit 1
        }
    else
        /bin/mkdir "${directory}"
    fi
    [[ "${directory:A}" == "${expected_path}" ]] || {
        echo "Refusing release parent outside the repository: ${directory}" >&2
        exit 1
    }
}

IFS=$'\t' read -r version build < <(
    "${script_directory}/release-version.sh" "${tag}"
)
require_local_release_state
[[ "$("${git_bin}" remote get-url origin)" == \
    'https://github.com/obra/agentic-usage-meter.git' ]] || {
    echo 'Unexpected origin URL.' >&2
    exit 1
}
require_remote_tag
"${gh_bin}" auth status --hostname github.com >/dev/null 2>&1
[[ "$("${gh_bin}" api user --jq .login)" == obra ]] || {
    echo 'GitHub CLI is not authenticated as obra.' >&2
    exit 1
}
release_status=
release_probe_exit=0
release_status=$(
    "${gh_bin}" api \
        "repos/obra/agentic-usage-meter/releases/tags/${tag}" \
        --include \
        --silent \
        2>/dev/null \
        | /usr/bin/head -n 1
) || release_probe_exit=$?
if (( release_probe_exit == 0 )); then
    echo "Release ${tag} already exists." >&2
    exit 1
fi
[[ "${release_status}" == HTTP/*" 404 "* ]] || {
    echo "Could not verify that release ${tag} does not exist." >&2
    exit 1
}

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION.}"
: "${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE.}"
identity_count=$(
    "${security_bin}" find-identity -v -p codesigning \
        | /usr/bin/awk -v identity="${DEVELOPER_ID_APPLICATION}" '
            index($0, "\"" identity "\"") {
                count += 1
            }
            END {
                print count + 0
            }
        '
)
[[ "${identity_count}" == 1 ]] || {
    echo 'DEVELOPER_ID_APPLICATION must resolve to exactly one identity.' >&2
    exit 1
}
"${xcrun_bin}" notarytool history \
    --keychain-profile "${NOTARYTOOL_PROFILE}" \
    >/dev/null

sparkle_tools="${repository_root}/.build/artifacts/sparkle/Sparkle/bin"
"${sparkle_tools}/generate_keys" \
    --account agentic-usage-meter -p \
    >/dev/null
"${swift_bin}" test
require_local_release_state

build_directory="${repository_root}/build"
releases_directory="${repository_root}/build/releases"
release_directory="${releases_directory}/${tag}"
[[ "${release_directory}" == "${releases_directory}/v${version}" ]] || {
    echo 'Refusing unsafe release directory.' >&2
    exit 1
}
ensure_real_directory "${build_directory}" "${repository_root}/build"
ensure_real_directory \
    "${releases_directory}" "${repository_root}/build/releases"
[[ ! -e "${release_directory}" && ! -L "${release_directory}" ]] || {
    echo "Release path already exists: ${release_directory}" >&2
    exit 1
}
/bin/mkdir "${release_directory}"
[[ "${release_directory:A:h}" == "${releases_directory:A}" ]] || {
    echo 'Refusing release directory outside its validated parent.' >&2
    exit 1
}

APP_VERSION="${version}" APP_BUILD="${build}" \
    "${script_directory}/assemble-app.sh" >/dev/null
application_path="${repository_root}/build/Agentic Usage Meter.app"
RELEASE_SIGNING=1 \
    "${script_directory}/sign-app.sh" \
    "${application_path}" \
    "${DEVELOPER_ID_APPLICATION}"

notarization_archive="${release_directory}/notarization.zip"
"${ditto_bin}" -c -k --keepParent \
    "${application_path}" "${notarization_archive}"
"${xcrun_bin}" notarytool submit "${notarization_archive}" \
    --keychain-profile "${NOTARYTOOL_PROFILE}" \
    --wait
"${xcrun_bin}" stapler staple "${application_path}"
"${script_directory}/verify-release.sh" "${application_path}"
/bin/rm -f "${notarization_archive}"

asset_base="Agentic-Usage-Meter-${version}"
archive_path="${release_directory}/${asset_base}.zip"
notes_path="${release_directory}/${asset_base}.md"
"${ditto_bin}" -c -k --keepParent \
    "${application_path}" "${archive_path}"
"${script_directory}/extract-release-notes.sh" \
    "${version}" "${repository_root}/CHANGELOG.md" \
    >"${notes_path}"

appcast_inputs=("${release_directory}"/*(DN))
[[ ${#appcast_inputs} == 2 \
    && -f "${archive_path}" \
    && -s "${notes_path}" ]] || {
    echo 'Appcast input must contain one archive and its release notes.' >&2
    exit 1
}
for appcast_input in "${appcast_inputs[@]}"; do
    [[ "${appcast_input}" == "${archive_path}" \
        || "${appcast_input}" == "${notes_path}" ]] || {
        echo "Unexpected appcast input: ${appcast_input:t}" >&2
        exit 1
    }
done

appcast_link='https://github.com/obra/agentic-usage-meter'
"${sparkle_tools}/generate_appcast" \
    --account agentic-usage-meter \
    --download-url-prefix \
    "https://github.com/obra/agentic-usage-meter/releases/download/${tag}/" \
    --maximum-deltas 0 \
    --maximum-versions 3 \
    --link "${appcast_link}" \
    -o "${release_directory}/appcast.xml" \
    "${release_directory}"
appcast_path="${release_directory}/appcast.xml"
asset_url="https://github.com/obra/agentic-usage-meter/releases/download/${tag}/${asset_base}.zip"
"${script_directory}/validate-appcast.sh" \
    "${appcast_path}" \
    "${asset_url}" \
    "${build}" \
    "${version}" \
    "${appcast_link}"

require_remote_tag
"${gh_bin}" release create "${tag}" \
    "${archive_path}" \
    "${notes_path}" \
    "${appcast_path}" \
    --repo obra/agentic-usage-meter \
    --verify-tag \
    --title "Agentic Usage Meter ${version}" \
    --notes-file "${notes_path}" || {
        release_exit=$?
        echo "GitHub release ${tag} may be partial; inspect it before retrying." >&2
        exit "${release_exit}"
    }
