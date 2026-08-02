# Releasing Agentic Usage Meter

Agentic Usage Meter releases are built and published locally from a
maintainer's Mac. `Scripts/release.sh` is the only supported release path. It
runs every preflight before notarization or GitHub upload, then assembles,
signs, notarizes, staples, verifies, packages, and publishes one semantic
version.

There is no GitHub Actions release workflow and no GitHub Actions release
secrets are configured. Signing or notarization credentials have not been
copied from Winby.

## Required local credentials

- Set `DEVELOPER_ID_APPLICATION` to the exact Developer ID Application identity
  used for the release. It must resolve to exactly one valid codesigning
  identity.
- Set `NOTARYTOOL_PROFILE` to an existing notarytool Keychain profile. The
  release preflight verifies it with `notarytool history`.
- Keep the Sparkle EdDSA private key in the login Keychain under the account
  `agentic-usage-meter`. Losing this private key blocks the normal signed-update
  path for existing installations. Do not export it into the repository or a
  release directory.
- Authenticate GitHub CLI to `github.com` as `obra`.

The Sparkle EdDSA identity and the Apple Developer ID identity protect
different parts of the update. Never rotate both identities in the same
update. Ship and verify a transition release for one identity before changing
the other, so an installed trusted version can authenticate the transition.

## Prepare and publish a release

Start from the intended release commit with a clean worktree and the exact
`https://github.com/obra/agentic-usage-meter.git` origin. Run the full test
suite before tagging. Create an annotated tag at `HEAD`:

```sh
git tag -a v0.1.0 -m "Release v0.1.0"
```

Export the two local credential selectors without recording their values in
the repository, then run the single release command:

```sh
Scripts/release.sh v0.1.0
```

The tag must have the exact `vMAJOR.MINOR.PATCH` form, with each component in
`0...999`. The script maps it to a monotonic build number using
`major * 1,000,000 + minor * 1,000 + patch`. It refuses a dirty worktree, a
lightweight or non-`HEAD` tag, a different origin or GitHub user, an existing
release, a remote tag that differs from the local annotated tag, unavailable
credentials, or a failing test suite. Only after those checks and the full test
suite pass does it push an absent annotated tag as the first release upload.

The local output for `v0.1.0` is:

```text
build/releases/v0.1.0/Agentic-Usage-Meter-0.1.0.zip
build/releases/v0.1.0/Agentic-Usage-Meter-0.1.0.md
build/releases/v0.1.0/appcast.xml
```

`generate_appcast` intentionally treats the same-basename Markdown file as the
archive's release notes. Before invoking Sparkle 2.9.4, the release script
requires the input directory to contain exactly that nonempty Markdown file and
the intended distributable zip. No notarization archive or unrelated package
is allowed into the appcast input.

## Verify publication

Inspect the published release and its three assets:

```sh
gh release view v0.1.0 --repo obra/agentic-usage-meter --web
```

Download the public appcast and validate both the XML and release asset URL:

```sh
curl --fail --location \
  https://github.com/obra/agentic-usage-meter/releases/latest/download/appcast.xml \
  --output /tmp/agentic-usage-meter-appcast.xml
xmllint --noout /tmp/agentic-usage-meter-appcast.xml
grep -F \
  'https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/Agentic-Usage-Meter-0.1.0.zip' \
  /tmp/agentic-usage-meter-appcast.xml
```

Also download the zip from the release, expand it, launch the installed app,
and exercise **Check for Updates…** from an older signed build. A passing local
script does not replace that installed-app update check.

## Failure recovery

The script deletes only the exact local `build/releases/<tag>` directory before
building. It never deletes a GitHub Release or tag. If GitHub upload fails after
release creation, treat the release as partial: inspect its assets, preserve the
local release directory, and complete or supersede it deliberately. Do not
delete and recreate the tag, rotate signing identities, or rerun the release
command until the partial public state has been reconciled.
