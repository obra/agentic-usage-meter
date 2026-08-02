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
cd "${repository_root}"

IFS=$'\t' read -r version build < <(
    "${script_directory}/release-version.sh" "${tag}"
)
[[ -z "$("${git_bin}" status --porcelain)" ]] || {
    echo 'Release requires a clean worktree.' >&2
    exit 1
}
[[ "$("${git_bin}" cat-file -t "${tag}" 2>/dev/null || true)" == tag ]] || {
    echo "${tag} must be an annotated tag." >&2
    exit 1
}
tag_commit=$("${git_bin}" rev-parse "${tag}^{commit}")
[[ "${tag_commit}" == "$("${git_bin}" rev-parse HEAD)" ]] || {
    echo "${tag} does not point to HEAD." >&2
    exit 1
}
[[ "$("${git_bin}" remote get-url origin)" == \
    'https://github.com/obra/agentic-usage-meter.git' ]] || {
    echo 'Unexpected origin URL.' >&2
    exit 1
}
local_tag_object=$("${git_bin}" rev-parse "${tag}")
remote_tag=$(
    "${git_bin}" ls-remote --tags origin "refs/tags/${tag}"
) || {
    echo "Could not verify remote tag ${tag}." >&2
    exit 1
}
[[ -z "${remote_tag}" \
    || "${remote_tag}" == \
        "${local_tag_object}"$'\t'"refs/tags/${tag}" ]] || {
    echo "Remote tag ${tag} does not match the local annotated tag." >&2
    exit 1
}
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
    /usr/bin/security find-identity -v -p codesigning \
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
/usr/bin/xcrun notarytool history \
    --keychain-profile "${NOTARYTOOL_PROFILE}" \
    >/dev/null

sparkle_tools="${repository_root}/.build/artifacts/sparkle/Sparkle/bin"
"${sparkle_tools}/generate_keys" \
    --account agentic-usage-meter -p \
    >/dev/null
swift test
if [[ -z "${remote_tag}" ]]; then
    "${git_bin}" push origin \
        "refs/tags/${tag}:refs/tags/${tag}"
fi

releases_directory="${repository_root}/build/releases"
release_directory="${releases_directory}/${tag}"
[[ "${release_directory}" == "${releases_directory}/v${version}" ]] || {
    echo 'Refusing unsafe release directory.' >&2
    exit 1
}
/bin/rm -rf "${release_directory}"
/bin/mkdir -p "${release_directory}"

APP_VERSION="${version}" APP_BUILD="${build}" \
    "${script_directory}/assemble-app.sh" >/dev/null
application_path="${repository_root}/build/Agentic Usage Meter.app"
RELEASE_SIGNING=1 \
    "${script_directory}/sign-app.sh" \
    "${application_path}" \
    "${DEVELOPER_ID_APPLICATION}"

notarization_archive="${release_directory}/notarization.zip"
/usr/bin/ditto -c -k --keepParent \
    "${application_path}" "${notarization_archive}"
/usr/bin/xcrun notarytool submit "${notarization_archive}" \
    --keychain-profile "${NOTARYTOOL_PROFILE}" \
    --wait
/usr/bin/xcrun stapler staple "${application_path}"
"${script_directory}/verify-release.sh" "${application_path}"
/bin/rm -f "${notarization_archive}"

asset_base="Agentic-Usage-Meter-${version}"
archive_path="${release_directory}/${asset_base}.zip"
notes_path="${release_directory}/${asset_base}.md"
/usr/bin/ditto -c -k --keepParent \
    "${application_path}" "${archive_path}"
"${script_directory}/extract-release-notes.sh" \
    "${version}" "${repository_root}/CHANGELOG.md" \
    >"${notes_path}"

appcast_inputs=("${release_directory}"/*(N))
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

"${sparkle_tools}/generate_appcast" \
    --account agentic-usage-meter \
    --download-url-prefix \
    "https://github.com/obra/agentic-usage-meter/releases/download/${tag}/" \
    --maximum-deltas 0 \
    --maximum-versions 3 \
    --link 'https://github.com/obra/agentic-usage-meter' \
    -o "${release_directory}/appcast.xml" \
    "${release_directory}"
appcast_path="${release_directory}/appcast.xml"
/usr/bin/xmllint --noout "${appcast_path}"
asset_url="https://github.com/obra/agentic-usage-meter/releases/download/${tag}/${asset_base}.zip"
/usr/bin/grep -F \
    "url=\"${asset_url}\"" \
    "${appcast_path}" >/dev/null
/usr/bin/grep -F \
    "sparkle:version=\"${build}\"" \
    "${appcast_path}" >/dev/null

"${gh_bin}" release create "${tag}" \
    "${archive_path}" \
    "${notes_path}" \
    "${appcast_path}" \
    --repo obra/agentic-usage-meter \
    --verify-tag \
    --title "Agentic Usage Meter ${version}" \
    --notes-file "${notes_path}"
