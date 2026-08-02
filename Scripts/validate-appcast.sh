#!/bin/zsh
set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo 'usage: validate-appcast.sh APPCAST ASSET_URL BUILD VERSION LINK' >&2
    exit 64
fi

appcast=$1
asset_url=$2
build=$3
version=$4
link=$5
xmllint_bin=${XMLLINT_BIN:-/usr/bin/xmllint}
sparkle_namespace='http://www.andymatuschak.org/xml-namespaces/sparkle'

for expected_value in "${asset_url}" "${build}" "${version}" "${link}"; do
    [[ "${expected_value}" != *"'"* ]] || {
        echo 'Appcast expectations may not contain a single quote.' >&2
        exit 64
    }
done

"${xmllint_bin}" --noout "${appcast}"

enclosure_count=$("${xmllint_bin}" --xpath \
    'count(//*[local-name()="enclosure"])' \
    "${appcast}")
[[ "${enclosure_count}" == 1 ]] || {
    echo 'Appcast must contain exactly one enclosure.' >&2
    exit 1
}

matching_item_count=$("${xmllint_bin}" --xpath \
    "count(/*[local-name()='rss']/*[local-name()='channel']/*[local-name()='item' and count(*[local-name()='enclosure' and @url='${asset_url}'])=1 and count(*[local-name()='version' and namespace-uri()='${sparkle_namespace}'])=1 and *[local-name()='version' and namespace-uri()='${sparkle_namespace}']='${build}' and count(*[local-name()='shortVersionString' and namespace-uri()='${sparkle_namespace}'])=1 and *[local-name()='shortVersionString' and namespace-uri()='${sparkle_namespace}']='${version}'])" \
    "${appcast}")
[[ "${matching_item_count}" == 1 ]] || {
    echo 'Appcast item does not match the release artifact.' >&2
    exit 1
}

channel_count=$("${xmllint_bin}" --xpath \
    "count(/*[local-name()='rss']/*[local-name()='channel'])" \
    "${appcast}")
link_count=$("${xmllint_bin}" --xpath \
    "count(/*[local-name()='rss']/*[local-name()='channel']/*[local-name()='item']/*[local-name()='link'])" \
    "${appcast}")
matching_link_count=$("${xmllint_bin}" --xpath \
    "count(/*[local-name()='rss']/*[local-name()='channel']/*[local-name()='item']/*[local-name()='link' and text()='${link}'])" \
    "${appcast}")
[[ "${channel_count}" == 1 \
    && "${link_count}" == 1 \
    && "${matching_link_count}" == 1 ]] || {
    echo 'Appcast channel link does not match the release link.' >&2
    exit 1
}
