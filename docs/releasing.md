# Releasing Agentic Usage Meter

Agentic Usage Meter releases run `Scripts/release.sh`, either locally from a
maintainer's Mac or from the GitHub Actions release workflow. The script
runs every preflight before notarization or GitHub upload, then assembles,
signs, notarizes, staples, verifies, packages, and publishes one semantic
version.

`.github/workflows/release.yml` runs that same script on a `macos-26` runner
whenever a `v*` tag is pushed. It materializes the release credentials into a
temporary keychain from these repository secrets, then destroys the keychain:

- `DEVELOPER_ID_CERT_P12` — base64 of the Developer ID Application
  certificate exported with its private key
  (`base64 < developer-id.p12 | pbcopy`).
- `DEVELOPER_ID_CERT_PASSWORD` — the export password for that `.p12`.
- `NOTARY_API_KEY_P8`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID` — an App
  Store Connect API key with the Developer role, pasted as the `.p8` file
  contents plus its key and issuer identifiers. Individual API keys have no
  issuer; leave `NOTARY_API_ISSUER_ID` unset for those. The currently
  configured secret is the individual key `A27HSE218FA7`.
- `SPARKLE_ED_PRIVATE_KEY` — the Sparkle EdDSA private key exported with
  `generate_keys --account agentic-usage-meter -x <file>`.
Publishing uses the workflow's built-in `GITHUB_TOKEN` with
`contents: write`; no personal token is stored. Because that token has no
user identity, the release script replaces its authenticated-as-`obra`
preflight with a push-access check on the canonical repository when it
detects it is running in this repository's Actions environment.

Signing or notarization credentials have not been copied from Winby.

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
git push origin v0.1.0
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
suite pass does it create the GitHub Release. The script never creates or pushes
a tag; the exact annotated tag must already exist on `origin` before it starts,
and the script checks the remote object again immediately before upload.

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

Download the public appcast and validate its correlated release metadata:

```sh
curl --fail --location \
  https://github.com/obra/agentic-usage-meter/releases/latest/download/appcast.xml \
  --output /tmp/agentic-usage-meter-appcast.xml
Scripts/validate-appcast.sh \
  /tmp/agentic-usage-meter-appcast.xml \
  'https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/Agentic-Usage-Meter-0.1.0.zip' \
  1000 \
  0.1.0 \
  'https://github.com/obra/agentic-usage-meter'
```

Also download the zip from the release, expand it, launch the installed app,
and exercise **Check for Updates…** from an older signed build. A passing local
script does not replace that installed-app update check.

## Failure recovery

The script never deletes or replaces an existing `build/releases/<tag>` path.
If that path already exists, inspect it and move or remove it deliberately
before starting a new attempt. The script never deletes a GitHub Release or
tag. If GitHub upload fails after release creation, treat the release as
partial: inspect its assets, preserve the local release directory, and complete
or supersede it deliberately. Do not delete and recreate the tag, rotate
signing identities, or rerun the release command until the partial public state
has been reconciled.
