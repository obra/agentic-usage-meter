# Sparkle Release and GitHub Publication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add confirmation-based Sparkle updates, automate signed and notarized local releases, publish the repository under `obra`, and establish the first public appcast.

**Architecture:** A small app-lifetime `AppUpdateController` wraps Sparkle's standard updater and is enabled only in a correctly configured application bundle. SwiftPM embeds Sparkle 2.9.4; reusable packaging scripts copy and sign its nested code. A local release command uses the Developer ID identity, notarytool Keychain profile, and an app-specific Sparkle key stored in the login Keychain to produce a notarized zip, generate the appcast with official tooling, and upload immutable assets to GitHub Releases.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, Sparkle 2.9.4, Swift Package Manager binary artifacts, zsh, codesign, notarytool, stapler, GitHub CLI, Sparkle EdDSA and appcast tools.

## Global Constraints

- Run the OpenCode lifecycle and public-identity plans first; begin this plan from a clean worktree.
- Use Sparkle 2.9.4 exactly until a separate dependency update is reviewed.
- Feed URL: `https://github.com/obra/agentic-usage-meter/releases/latest/download/appcast.xml`.
- Sparkle Keychain account: `agentic-usage-meter`; never export or commit its private EdDSA key.
- Jesse Vincent is the app's author and maker; `https://fsck.com` is his personal homepage and remains the repository homepage.
- Check automatically and expose **Check for Updates…**, but require confirmation before installation.
- Sign and staple the application before Sparkle signs the final update archive.
- Use `com.fsck.agentic-usage-meter` and the stable Developer ID Application identity.
- Do not create a GitHub Actions release workflow that cannot run without inaccessible Winby secret values.
- Do not publish until the history audit is clean and the full Swift suite passes.
- Do not overwrite an existing GitHub repository or release; stop and inspect if either target already exists.

---

### Task 1: Add Sparkle configuration and an app-lifetime update controller

**Files:**
- Modify: `Package.swift`
- Create: `Sources/UsageMeterUI/Updates/AppUpdateController.swift`
- Create: `Tests/UsageMeterUITests/AppUpdateControllerTests.swift`
- Modify: `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift`
- Modify: `Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift`
- Modify: `Resources/Info.plist`
- Modify: `Tests/UsageMeterCoreTests/ReleaseConfigurationTests.swift`
- Modify: `THIRD_PARTY_NOTICES.md`

**Interfaces:**
- Consumes: Sparkle's `SPUStandardUpdaterController`, `Bundle.main.infoDictionary`, and the existing menu-bar footer.
- Produces: `AppUpdateConfiguration.from(infoDictionary:)`, `AppUpdateController.start()`, `AppUpdateController.checkForUpdates()`, and `AppUpdateController.canCheckForUpdates`.

- [ ] **Step 1: Add failing bundle-configuration tests**

Extend `applicationBundleDeclaresMenuBarReleaseContract` or add a sibling test that reads `Resources/Info.plist` and asserts:

```swift
#expect(
    plist["SUFeedURL"] as? String
        == "https://github.com/obra/agentic-usage-meter/releases/latest/download/appcast.xml"
)
#expect(plist["SUEnableAutomaticChecks"] as? Bool == true)
#expect(plist["SUAutomaticallyUpdate"] as? Bool == false)

let publicKey = try #require(plist["SUPublicEDKey"] as? String)
let publicKeyData = try #require(Data(base64Encoded: publicKey))
#expect(publicKeyData.count == 32)
```

- [ ] **Step 2: Add failing update-controller behavior tests**

Create `AppUpdateControllerTests.swift` with an internal closure-backed initializer seam:

```swift
@Suite
@MainActor
struct AppUpdateControllerTests {
    @Test
    func malformedBundleConfigurationDisablesUpdates() {
        #expect(
            AppUpdateConfiguration.from(
                infoDictionary: [
                    "SUFeedURL": "http://example.com/appcast.xml",
                    "SUPublicEDKey": "not-a-key",
                ]
            ) == nil
        )
    }

    @Test
    func configuredControllerStartsOnceAndChecksOnDemand() {
        var starts = 0
        var checks = 0
        let controller = AppUpdateController(
            startUpdater: { starts += 1 },
            checkForUpdates: { checks += 1 }
        )

        #expect(controller.canCheckForUpdates)
        controller.start()
        controller.start()
        controller.checkForUpdates()

        #expect(starts == 1)
        #expect(checks == 1)
    }

    @Test
    func disabledControllerDoesNothing() {
        let controller = AppUpdateController.disabled

        #expect(!controller.canCheckForUpdates)
        controller.start()
        controller.checkForUpdates()
    }
}
```

- [ ] **Step 3: Run focused tests and verify they fail**

Run:

```bash
swift test --filter 'AppUpdateControllerTests|applicationBundleDeclaresMenuBarReleaseContract'
```

Expected: configuration assertions fail and update-controller types are missing.

- [ ] **Step 4: Add the exact Sparkle dependency**

Modify `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/sparkle-project/Sparkle",
        exact: "2.9.4"
    )
],
```

Add the product only to `UsageMeterUI`:

```swift
.product(name: "Sparkle", package: "Sparkle")
```

Run:

```bash
swift package resolve
swift build --product AgenticUsageMeter
```

Expected: Sparkle 2.9.4 resolves and the app target links.

- [ ] **Step 5: Generate or retrieve the app-specific Sparkle public key**

Use Sparkle's checked-out tool and a unique Keychain account:

```bash
sparkle_tools='.build/artifacts/sparkle/Sparkle/bin'
if ! sparkle_public_key=$("$sparkle_tools/generate_keys" --account agentic-usage-meter -p 2>/dev/null); then
  "$sparkle_tools/generate_keys" --account agentic-usage-meter
  sparkle_public_key=$("$sparkle_tools/generate_keys" --account agentic-usage-meter -p)
fi
test "$(printf '%s' "$sparkle_public_key" | /usr/bin/base64 -D | wc -c | tr -d ' ')" = 32
printf '%s\n' "$sparkle_public_key"
```

Expected: the private key remains in the login Keychain and the printed line is one 32-byte public key encoded as Base64. Use that exact public value in `SUPublicEDKey`; do not create a private-key export or intermediate key file.

- [ ] **Step 6: Add the Sparkle Info.plist contract**

Add the feed and behavior keys exactly as follows:

```xml
<key>SUFeedURL</key>
<string>https://github.com/obra/agentic-usage-meter/releases/latest/download/appcast.xml</string>
<key>SUEnableAutomaticChecks</key>
<true/>
<key>SUAutomaticallyUpdate</key>
<false/>
```

Read the single line produced in Step 5 and use `apply_patch` to add `SUPublicEDKey` immediately after `SUFeedURL`; its string value must equal that generated Base64 line byte-for-byte. Re-run the 32-byte decoding assertion rather than copying the explanatory output from `generate_keys`.

- [ ] **Step 7: Implement the focused update wrapper**

Create `AppUpdateController.swift` with:

```swift
import Foundation
import Sparkle

struct AppUpdateConfiguration: Equatable {
    let feedURL: URL
    let publicKey: Data

    static func from(
        infoDictionary: [String: Any]?
    ) -> AppUpdateConfiguration? {
        guard
            let dictionary = infoDictionary,
            let feed = dictionary["SUFeedURL"] as? String,
            let feedURL = URL(string: feed),
            feedURL.scheme == "https",
            let encodedKey = dictionary["SUPublicEDKey"] as? String,
            let publicKey = Data(base64Encoded: encodedKey),
            publicKey.count == 32
        else {
            return nil
        }
        return AppUpdateConfiguration(
            feedURL: feedURL,
            publicKey: publicKey
        )
    }
}

@MainActor
public final class AppUpdateController {
    public static let disabled = AppUpdateController(
        startUpdater: nil,
        checkForUpdates: nil
    )

    private let startUpdater: (() -> Void)?
    private let check: (() -> Void)?
    private var didStart = false

    public var canCheckForUpdates: Bool {
        check != nil
    }

    public convenience init(bundle: Bundle = .main) {
        guard AppUpdateConfiguration.from(
            infoDictionary: bundle.infoDictionary
        ) != nil else {
            self.init(startUpdater: nil, checkForUpdates: nil)
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.init(
            startUpdater: { controller.startUpdater() },
            checkForUpdates: {
                controller.checkForUpdates(nil)
            }
        )
    }

    init(
        startUpdater: (() -> Void)?,
        checkForUpdates: (() -> Void)?
    ) {
        self.startUpdater = startUpdater
        check = checkForUpdates
    }

    public func start() {
        guard !didStart, let startUpdater else { return }
        didStart = true
        startUpdater()
    }

    public func checkForUpdates() {
        check?()
    }
}
```

If Sparkle's imported API requires Objective-C sender spelling under Swift 6.2, make the smallest compiler-directed adjustment while retaining these public interfaces.

- [ ] **Step 8: Own and start the updater from the app lifetime**

Add `@State private var updateController: AppUpdateController` to `AgenticUsageMeterApp`, initialize it once with `AppUpdateController()`, pass it to `MenuBarContentView` and `MenuBarLabel`, and call `updateController.start()` in the existing label startup task before automatic provider refresh begins.

Change `MenuBarContentView` to accept the controller and add this footer button before Settings:

```swift
if updateController.canCheckForUpdates {
    Button {
        updateController.checkForUpdates()
    } label: {
        Label(
            "Check for Updates…",
            systemImage: "arrow.down.circle"
        )
    }
}
```

Keep the controller optional or default it to `.disabled` in the public initializer so existing UI tests and previews do not start Sparkle.

- [ ] **Step 9: Add Sparkle's complete distributed license**

Append a Sparkle 2.9.4 section to `THIRD_PARTY_NOTICES.md` by copying the complete upstream `LICENSE` from the resolved tag, including its external-license notices. Do not abbreviate it to the primary copyright paragraph because the embedded framework contains third-party code covered later in that file.

- [ ] **Step 10: Run focused and complete tests**

Run:

```bash
swift test --filter 'AppUpdateControllerTests|applicationBundleDeclaresMenuBarReleaseContract'
swift test
```

Expected: update configuration and controller tests pass, then the complete suite passes.

- [ ] **Step 11: Commit the updater behavior**

```bash
git status --short
git add Package.swift Sources/UsageMeterUI/Updates/AppUpdateController.swift Tests/UsageMeterUITests/AppUpdateControllerTests.swift Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift Resources/Info.plist Tests/UsageMeterCoreTests/ReleaseConfigurationTests.swift THIRD_PARTY_NOTICES.md
test ! -f Package.resolved || git add Package.resolved
git commit -m "Add confirmation-based Sparkle updates" -m "Embed Sparkle 2.9.4 as the standard update UI, retain one app-lifetime controller, check automatically from configured app bundles, expose a manual menu-bar check, and keep installation user-confirmed. Generate an app-specific EdDSA identity in the login Keychain and commit only its public key and required notices."
```

---

### Task 2: Embed and sign Sparkle correctly in assembled apps

**Files:**
- Create: `Scripts/embed-sparkle-framework.sh`
- Create: `Scripts/sign-app.sh`
- Modify: `Scripts/assemble-app.sh`
- Modify: `Scripts/build-and-run-local.sh`
- Modify: `Scripts/sign-and-notarize.sh`
- Modify: `Scripts/verify-release.sh`
- Modify: `Tests/UsageMeterCoreTests/ReleaseConfigurationTests.swift`

**Interfaces:**
- Consumes: SwiftPM's Sparkle binary artifact and existing assembled app layout.
- Produces: `embed-sparkle-framework.sh <repository-root> <app-bundle> <executable>` and `sign-app.sh <app-bundle> <identity>`; `RELEASE_SIGNING=1` adds a secure timestamp.

- [ ] **Step 1: Write a failing framework-embedding behavior test**

Add a test that creates a temporary repository-shaped directory containing:

```text
.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/marker
Agentic Usage Meter.app/Contents/MacOS/AgenticUsageMeter
```

Provide an executable fake `install_name_tool` through `INSTALL_NAME_TOOL_BIN`, run `embed-sparkle-framework.sh`, and assert:

```swift
#expect(
    FileManager.default.fileExists(
        atPath: applicationBundle
            .appending(path: "Contents/Frameworks/Sparkle.framework/marker")
            .path
    )
)
#expect(
    try String(contentsOf: invocationLog, encoding: .utf8)
        .contains("Agentic Usage Meter.app/Contents/MacOS/AgenticUsageMeter")
)
```

This executes the script with fake external tooling instead of matching its source.

- [ ] **Step 2: Write a failing inside-out signing behavior test**

Create a fake Sparkle bundle with the five nested signable paths and a fake `codesign` executable supplied through `CODESIGN_BIN`. Run `sign-app.sh`, read only the logged target paths, and assert:

```swift
#expect(targets.last == applicationBundle.path)
#expect(
    targets.firstIndex(where: { $0.hasSuffix("Installer.xpc") })
        < targets.firstIndex(of: applicationBundle.path)
)
#expect(
    targets.firstIndex(where: { $0.hasSuffix("Sparkle.framework") })
        < targets.firstIndex(of: applicationBundle.path)
)
```

Do not assert the complete rendered command line; the contract is that nested code is signed before the outer app.

- [ ] **Step 3: Run both tests and verify the scripts are missing**

Run:

```bash
swift test --filter 'sparkleFrameworkIsEmbeddedWithApplicationRPath|sparkleNestedCodeIsSignedBeforeApplication'
```

Expected: both fail because the scripts do not exist.

- [ ] **Step 4: Implement framework embedding**

Create `embed-sparkle-framework.sh` that:

- accepts explicit repository root, app bundle, and executable paths;
- requires the exact SwiftPM artifact directory;
- creates `Contents/Frameworks`;
- copies `Sparkle.framework` preserving its bundle structure;
- invokes `${INSTALL_NAME_TOOL_BIN:-/usr/bin/install_name_tool} -add_rpath @executable_path/../Frameworks` on the app executable;
- fails immediately if the framework, executable, copy, or rpath operation is missing or unsuccessful.

Use this implementation:

```zsh
#!/bin/zsh
set -euo pipefail

repository_root=$1
application_bundle=$2
application_executable=$3
source_framework="${repository_root}/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
frameworks_directory="${application_bundle}/Contents/Frameworks"
install_name_tool_bin=${INSTALL_NAME_TOOL_BIN:-/usr/bin/install_name_tool}

[[ -d "${source_framework}" ]] || {
    echo "Missing Sparkle framework: ${source_framework}" >&2
    exit 1
}
[[ -f "${application_executable}" ]] || {
    echo "Missing application executable: ${application_executable}" >&2
    exit 1
}

/bin/mkdir -p "${frameworks_directory}"
/bin/cp -R \
    "${source_framework}" \
    "${frameworks_directory}/Sparkle.framework"
"${install_name_tool_bin}" \
    -add_rpath '@executable_path/../Frameworks' \
    "${application_executable}"
```

Modify `assemble-app.sh` to create `Contents/Frameworks` and invoke the new script after copying the executable.

- [ ] **Step 5: Implement reusable inside-out signing**

Create `sign-app.sh` with `set -euo pipefail`. It accepts app path and exact identity, uses `${CODESIGN_BIN:-/usr/bin/codesign}`, and signs in this order when present:

```text
Sparkle.framework/Versions/B/XPCServices/Installer.xpc
Sparkle.framework/Versions/B/XPCServices/Downloader.xpc
Sparkle.framework/Versions/B/Autoupdate
Sparkle.framework/Versions/B/Updater.app
Sparkle.framework
every Contents/Resources/*.bundle
Contents/MacOS/AgenticUsageMeter
Agentic Usage Meter.app
```

Use `--force --options runtime --sign <identity>` for every target. Add `--timestamp` only when `RELEASE_SIGNING=1`. Do not use `--deep` for signing.

Use this implementation shape:

```zsh
#!/bin/zsh
set -euo pipefail

application_path=$1
signing_identity=$2
codesign_bin=${CODESIGN_BIN:-/usr/bin/codesign}
sparkle_framework="${application_path}/Contents/Frameworks/Sparkle.framework"
signing_arguments=(--force --options runtime)
if [[ "${RELEASE_SIGNING:-0}" == 1 ]]; then
    signing_arguments+=(--timestamp)
fi
signing_arguments+=(--sign "${signing_identity}")

nested_targets=(
    "${sparkle_framework}/Versions/B/XPCServices/Installer.xpc"
    "${sparkle_framework}/Versions/B/XPCServices/Downloader.xpc"
    "${sparkle_framework}/Versions/B/Autoupdate"
    "${sparkle_framework}/Versions/B/Updater.app"
    "${sparkle_framework}"
)
for target in "${nested_targets[@]}"; do
    [[ -e "${target}" ]] || {
        echo "Missing signable Sparkle component: ${target}" >&2
        exit 1
    }
    "${codesign_bin}" "${signing_arguments[@]}" "${target}"
done

while IFS= read -r -d '' resource_bundle; do
    "${codesign_bin}" "${signing_arguments[@]}" "${resource_bundle}"
done < <(
    /usr/bin/find \
        "${application_path}/Contents/Resources" \
        -type d -name '*.bundle' -print0
)

"${codesign_bin}" \
    "${signing_arguments[@]}" \
    "${application_path}/Contents/MacOS/AgenticUsageMeter"
"${codesign_bin}" \
    "${signing_arguments[@]}" \
    "${application_path}"
```

Update `build-and-run-local.sh` to call `sign-app.sh` without release timestamping. Update `sign-and-notarize.sh` to call it with `RELEASE_SIGNING=1`.

- [ ] **Step 6: Strengthen release verification**

Keep the outer `codesign --verify --deep --strict`, Gatekeeper assessment, and staple validation. Add explicit verification for:

```text
Contents/Frameworks/Sparkle.framework
Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app
Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc
Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc
```

Also run:

```bash
otool -L 'build/Agentic Usage Meter.app/Contents/MacOS/AgenticUsageMeter'
```

and require the linked Sparkle path to resolve through `@rpath` rather than a `.build` directory.

- [ ] **Step 7: Run focused tests and assemble a real signed local app**

Run:

```bash
swift test --filter 'sparkleFrameworkIsEmbeddedWithApplicationRPath|sparkleNestedCodeIsSignedBeforeApplication'
CONFIGURATION=release Scripts/build-and-run-local.sh
codesign --verify --deep --strict --verbose=2 'build/Agentic Usage Meter.app'
otool -L 'build/Agentic Usage Meter.app/Contents/MacOS/AgenticUsageMeter'
```

Expected: tests pass, the app launches, signature verification succeeds, and no Sparkle linkage points into `.build`.

- [ ] **Step 8: Commit packaging and signing**

```bash
git status --short
git add Scripts/embed-sparkle-framework.sh Scripts/sign-app.sh Scripts/assemble-app.sh Scripts/build-and-run-local.sh Scripts/sign-and-notarize.sh Scripts/verify-release.sh Tests/UsageMeterCoreTests/ReleaseConfigurationTests.swift
git commit -m "Package and sign the Sparkle runtime" -m "Copy Sparkle's SwiftPM binary framework into assembled apps, add the application rpath, and replace deep signing with reusable inside-out signing of Sparkle helpers, resources, executable, and outer bundle. Exercise embedding and signing order with fake external tools before verifying a real Developer ID-signed local app."
```

---

### Task 3: Build deterministic local release automation

**Files:**
- Create: `CHANGELOG.md`
- Create: `docs/releasing.md`
- Create: `Scripts/release-version.sh`
- Create: `Scripts/extract-release-notes.sh`
- Create: `Scripts/release.sh`
- Modify: `Scripts/assemble-app.sh`
- Modify: `Tests/UsageMeterCoreTests/ReleaseConfigurationTests.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: an annotated `vMAJOR.MINOR.PATCH` tag at `HEAD`, `DEVELOPER_ID_APPLICATION`, `NOTARYTOOL_PROFILE`, Sparkle Keychain account `agentic-usage-meter`, and authenticated `gh`.
- Produces: `build/releases/vMAJOR.MINOR.PATCH/Agentic-Usage-Meter-MAJOR.MINOR.PATCH.zip`, matching Markdown release notes, and `appcast.xml`, then a GitHub Release containing all three.

- [ ] **Step 1: Write failing semantic-version mapping tests**

Add a test helper that runs `Scripts/release-version.sh` and assert:

```swift
#expect(try releaseVersion("v0.1.0") == "0.1.0\t1000")
#expect(try releaseVersion("v0.1.1") == "0.1.1\t1001")
#expect(try releaseVersion("v1.0.0") == "1.0.0\t1000000")
#expect(try releaseVersion("1.0.0") == nil)
#expect(try releaseVersion("v1.0") == nil)
#expect(try releaseVersion("v1.2.3-beta") == nil)
```

The build number formula is `major * 1_000_000 + minor * 1_000 + patch`, with each component restricted to `0...999`.

- [ ] **Step 2: Write failing release-note extraction tests**

Create a temporary changelog containing `0.1.0` and `0.2.0` sections, run `extract-release-notes.sh 0.1.0 <file>`, and assert it returns only the `0.1.0` heading and bullets. Assert an absent version exits nonzero without creating output.

- [ ] **Step 3: Run focused tests and verify scripts are missing**

Run:

```bash
swift test --filter 'releaseVersion|releaseNotes'
```

Expected: failures because the release helper scripts do not exist.

- [ ] **Step 4: Implement strict release version parsing**

Create `release-version.sh` with `set -euo pipefail`. Accept exactly one tag, require `^v[0-9]+\.[0-9]+\.[0-9]+$`, reject any component above 999, strip the `v`, compute the monotonic build number, and print:

```text
0.1.0<TAB>1000
```

Use shell arithmetic only after numeric validation; do not evaluate arbitrary input.

Use this implementation:

```zsh
#!/bin/zsh
set -euo pipefail

version_pattern='^v([0-9]+)\.([0-9]+)\.([0-9]+)$'
if [[ $# -ne 1 || ! $1 =~ $version_pattern ]]; then
    echo 'usage: release-version.sh vMAJOR.MINOR.PATCH' >&2
    exit 64
fi

major=${match[1]}
minor=${match[2]}
patch=${match[3]}
if (( major > 999 || minor > 999 || patch > 999 )); then
    echo 'version components must be between 0 and 999' >&2
    exit 64
fi

version="${major}.${minor}.${patch}"
build=$((10#${major} * 1000000 + 10#${minor} * 1000 + 10#${patch}))
/usr/bin/printf '%s\t%d\n' "${version}" "${build}"
```

- [ ] **Step 5: Implement focused changelog extraction**

Create `CHANGELOG.md` with a `## 0.1.0 - 2026-08-01` section summarizing the first public multi-provider menu-bar release. Create `extract-release-notes.sh` that prints that exact version's `##` section through the line before the next `##` section and exits nonzero if the heading is absent.

Use this script:

```zsh
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
```

- [ ] **Step 6: Let assembly inject release versions into generated artifacts**

In `assemble-app.sh`, after copying `Resources/Info.plist`, apply these optional environment values only to the generated app:

```zsh
if [[ -n "${APP_VERSION:-}" ]]; then
    /usr/bin/plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$contents_path/Info.plist"
fi
if [[ -n "${APP_BUILD:-}" ]]; then
    /usr/bin/plutil -replace CFBundleVersion -string "$APP_BUILD" "$contents_path/Info.plist"
fi
```

Add a behavior test that assembles with `APP_VERSION=1.2.3 APP_BUILD=1002003` and reads those two values from the generated plist.

- [ ] **Step 7: Implement the fail-closed release command**

Create `release.sh` with these preconditions before any upload:

```text
one vMAJOR.MINOR.PATCH argument
clean Git worktree
tag resolves to HEAD
origin is https://github.com/obra/agentic-usage-meter.git
gh is authenticated as obra
GitHub release for the tag does not exist
DEVELOPER_ID_APPLICATION is set and resolves to one valid identity
NOTARYTOOL_PROFILE is set and passes a notarytool credential preflight
Sparkle generate_keys -p succeeds for account agentic-usage-meter
full swift test passes
```

Then perform these exact phases:

1. derive marketing/build versions with `release-version.sh`;
2. assemble with `APP_VERSION` and `APP_BUILD`;
3. sign through `sign-app.sh` with `RELEASE_SIGNING=1`;
4. create a temporary notarization zip with `/usr/bin/ditto`;
5. submit with `xcrun notarytool submit --keychain-profile "$NOTARYTOOL_PROFILE" --wait`;
6. staple and run `verify-release.sh` on the app;
7. recreate the final zip from the stapled app;
8. extract matching Markdown release notes beside the zip;
9. run Sparkle 2.9.4 `generate_appcast` with:

```zsh
"$sparkle_tools/generate_appcast" \
    --account agentic-usage-meter \
    --download-url-prefix "https://github.com/obra/agentic-usage-meter/releases/download/$tag/" \
    --maximum-deltas 0 \
    --maximum-versions 3 \
    --link "https://github.com/obra/agentic-usage-meter" \
    -o "$release_directory/appcast.xml" \
    "$release_directory"
```

10. validate `appcast.xml` with `xmllint --noout` and verify it contains the exact tag asset URL plus the expected `sparkle:version`;
11. create the GitHub Release with the zip, Markdown notes asset, and `appcast.xml`, using the Markdown file as `--notes-file`.

Use an exact versioned directory under `build/releases/`. Never remove a broad build, home, or repository path. If upload fails after release creation, report the partial release rather than deleting it automatically.

Implement the orchestration with this concrete structure:

```zsh
#!/bin/zsh
set -euo pipefail

tag=${1:?usage: release.sh vMAJOR.MINOR.PATCH}
script_directory=${0:A:h}
repository_root=${script_directory:h}
cd "${repository_root}"

IFS=$'\t' read -r version build < <(
    "${script_directory}/release-version.sh" "${tag}"
)
[[ -z "$(git status --porcelain)" ]] || {
    echo 'Release requires a clean worktree.' >&2
    exit 1
}
[[ "$(git rev-parse "${tag}^{commit}")" == "$(git rev-parse HEAD)" ]] || {
    echo "${tag} does not point to HEAD." >&2
    exit 1
}
[[ "$(git remote get-url origin)" == \
    'https://github.com/obra/agentic-usage-meter.git' ]] || {
    echo 'Unexpected origin URL.' >&2
    exit 1
}
gh auth status --hostname github.com >/dev/null
[[ "$(gh api user --jq .login)" == obra ]] || {
    echo 'GitHub CLI is not authenticated as obra.' >&2
    exit 1
}
if gh release view "${tag}" -R obra/agentic-usage-meter >/dev/null 2>&1; then
    echo "Release ${tag} already exists." >&2
    exit 1
fi

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION.}"
: "${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE.}"
security find-identity -v -p codesigning \
    | /usr/bin/grep -F "\"${DEVELOPER_ID_APPLICATION}\"" \
    >/dev/null
xcrun notarytool history \
    --keychain-profile "${NOTARYTOOL_PROFILE}" \
    >/dev/null

sparkle_tools="${repository_root}/.build/artifacts/sparkle/Sparkle/bin"
"${sparkle_tools}/generate_keys" \
    --account agentic-usage-meter -p \
    >/dev/null
swift test

release_directory="${repository_root}/build/releases/${tag}"
[[ "${release_directory}" == \
    "${repository_root}/build/releases/${tag}" ]]
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
xcrun notarytool submit "${notarization_archive}" \
    --keychain-profile "${NOTARYTOOL_PROFILE}" \
    --wait
xcrun stapler staple "${application_path}"
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

"${sparkle_tools}/generate_appcast" \
    --account agentic-usage-meter \
    --download-url-prefix \
    "https://github.com/obra/agentic-usage-meter/releases/download/${tag}/" \
    --maximum-deltas 0 \
    --maximum-versions 3 \
    --link 'https://github.com/obra/agentic-usage-meter' \
    -o "${release_directory}/appcast.xml" \
    "${release_directory}"
xmllint --noout "${release_directory}/appcast.xml"
/usr/bin/grep -F \
    "${tag}/${asset_base}.zip" \
    "${release_directory}/appcast.xml" >/dev/null
/usr/bin/grep -F \
    "sparkle:version=\"${build}\"" \
    "${release_directory}/appcast.xml" >/dev/null

gh release create "${tag}" \
    "${archive_path}" \
    "${notes_path}" \
    "${release_directory}/appcast.xml" \
    --repo obra/agentic-usage-meter \
    --title "Agentic Usage Meter ${version}" \
    --notes-file "${notes_path}"
```

- [ ] **Step 8: Document release ownership and recovery boundaries**

Create `docs/releasing.md` with:

- the Sparkle Keychain account name and a warning that losing its private key blocks normal update signing;
- required Developer ID and notarytool profile environment variables;
- the annotated-tag command;
- the single release command;
- the fact that GitHub Actions release secrets are not configured or copied from Winby;
- how to verify the public appcast and release asset;
- the rule that EdDSA and Apple signing identities must not both rotate in one update.

Update README's Release and Updates section to link this document and `https://github.com/obra/agentic-usage-meter/releases/latest`.

- [ ] **Step 9: Run helper tests and a no-upload preflight**

Run:

```bash
swift test --filter 'releaseVersion|releaseNotes|assembledReleaseUsesRequestedVersions'
Scripts/release-version.sh v0.1.0
Scripts/extract-release-notes.sh 0.1.0 CHANGELOG.md
```

Expected: tests pass, version mapping prints `0.1.0` and `1000`, and release notes are nonempty. Exercise one deliberate preflight failure with an unclean temporary worktree or missing tag and prove no `gh release` is created.

- [ ] **Step 10: Commit deterministic release tooling**

```bash
git status --short
git add CHANGELOG.md docs/releasing.md Scripts/release-version.sh Scripts/extract-release-notes.sh Scripts/release.sh Scripts/assemble-app.sh Tests/UsageMeterCoreTests/ReleaseConfigurationTests.swift README.md
git commit -m "Automate signed Sparkle releases" -m "Derive monotonic bundle versions from strict semantic tags, extract matching release notes, inject versions only into generated app artifacts, and add a fail-closed local release command that tests, signs, notarizes, staples, generates the official Sparkle appcast, and uploads immutable GitHub Release assets."
```

---

### Task 4: Publish the repository and first signed release

**Files:**
- No source changes are expected after the final release commit.
- Generated release artifacts remain under ignored `build/releases/v0.1.0/`.

**Interfaces:**
- Consumes: clean audited local history, completed documentation/screenshots, `gh` account `obra`, tag `v0.1.0`, Developer ID identity, notarytool profile, and Sparkle Keychain key.
- Produces: public `obra/agentic-usage-meter`, default branch `main`, release `v0.1.0`, downloadable signed archive, and latest-release `appcast.xml`.

- [ ] **Step 1: Run final local verification before external mutation**

Run:

```bash
swift test
git diff --check
git status --short --branch
gh auth status
gh repo view obra/agentic-usage-meter --json nameWithOwner 2>/dev/null && exit 1 || true
gh release view v0.1.0 -R obra/agentic-usage-meter 2>/dev/null && exit 1 || true
```

Expected: tests pass, worktree is clean, GitHub authentication is `obra`, and neither repository nor release exists. If the repository exists, stop and inspect it rather than running creation commands.

- [ ] **Step 2: Rename the completed local branch to the public default branch**

Run:

```bash
git branch -m main
git status --short --branch
```

Expected: the current branch is `main` at the fully verified release commit.

- [ ] **Step 3: Create and configure the public GitHub repository**

Run:

```bash
gh repo create obra/agentic-usage-meter \
  --public \
  --description 'macOS menu-bar meter for coding-agent subscription quotas' \
  --homepage 'https://fsck.com'
git remote add origin https://github.com/obra/agentic-usage-meter.git
git push -u origin main
gh repo edit obra/agentic-usage-meter \
  --default-branch main \
  --enable-issues \
  --enable-wiki=false \
  --homepage 'https://fsck.com'
gh api --method PUT repos/obra/agentic-usage-meter/topics \
  -f 'names[]=macos' \
  -f 'names[]=swiftui' \
  -f 'names[]=menu-bar' \
  -f 'names[]=claude' \
  -f 'names[]=codex'
```

Expected: the entire audited history is public on `main`, README and screenshots render, GitHub detects the MIT license, and repository metadata points to fsck.com.

- [ ] **Step 4: Inspect public rendering before publishing binaries**

Open `https://github.com/obra/agentic-usage-meter` and verify:

- both synthetic screenshots render at readable sizes;
- no screenshot exposes PII;
- provider table and links render correctly;
- License shows MIT;
- homepage points to `https://fsck.com`;
- no ignored `.superpowers`, `.build`, `build`, or diagnostic file was pushed.

- [ ] **Step 5: Create and push the first annotated version tag**

Run:

```bash
git tag -a v0.1.0 -m 'Agentic Usage Meter 0.1.0'
git push origin v0.1.0
```

Expected: `v0.1.0` resolves to the same commit as `main`.

- [ ] **Step 6: Run the local signed-release command**

Use the exact Developer ID identity already selected by local signing and the existing notarytool Keychain profile:

```bash
DEVELOPER_ID_APPLICATION='Developer ID Application: Jesse Vincent (87WJ58S66M)' \
NOTARYTOOL_PROFILE='agentic-usage-meter' \
Scripts/release.sh v0.1.0
```

If the named profile does not exist, use `xcrun notarytool store-credentials agentic-usage-meter` and provide Apple credentials interactively; secret values cannot be inferred or copied automatically. Rerun the release only after the credential preflight succeeds.

Expected: notarization is accepted, the app is stapled and verified, the final archive and appcast are generated from that stapled app, and GitHub Release `v0.1.0` contains all expected assets.

- [ ] **Step 7: Verify public release assets and feed contents**

Run:

```bash
gh release view v0.1.0 -R obra/agentic-usage-meter --json url,isDraft,isPrerelease,assets
curl --fail --location --output /tmp/agentic-usage-meter-appcast.xml \
  https://github.com/obra/agentic-usage-meter/releases/latest/download/appcast.xml
xmllint --noout /tmp/agentic-usage-meter-appcast.xml
rg -n 'v0\.1\.0/Agentic-Usage-Meter-0\.1\.0\.zip|sparkle:version="1000"' /tmp/agentic-usage-meter-appcast.xml
rm -f /tmp/agentic-usage-meter-appcast.xml
```

Expected: the release is public, non-draft, non-prerelease; the feed is valid XML and names the immutable archive with build 1000.

- [ ] **Step 8: Perform live confirmation-based update acceptance**

Assemble a lower-version copy with the production feed and public key, sign it with the same Developer ID identity, and place it at an exact temporary app path:

```bash
APP_VERSION=0.0.1 APP_BUILD=1 Scripts/assemble-app.sh
Scripts/sign-app.sh 'build/Agentic Usage Meter.app' 'Developer ID Application: Jesse Vincent (87WJ58S66M)'
mkdir -p /tmp/agentic-usage-meter-update-test
ditto 'build/Agentic Usage Meter.app' '/tmp/agentic-usage-meter-update-test/Agentic Usage Meter.app'
open -na '/tmp/agentic-usage-meter-update-test/Agentic Usage Meter.app' --args --sample-data
```

Verify through the UI:

1. **Check for Updates…** finds `0.1.0`.
2. The app displays release information and waits for confirmation.
3. Cancel leaves the `0.0.1` test app unchanged.
4. Check again, confirm installation, and verify the temporary app relaunches as `0.1.0` with a valid Developer ID signature.

After acceptance, quit only the temporary test app and remove the exact temporary directory:

```bash
rm -rf /tmp/agentic-usage-meter-update-test
```

- [ ] **Step 9: Restore and launch the production local build**

Run:

```bash
CONFIGURATION=release Scripts/build-and-run-local.sh
```

Expected: the normal signed production app is running, uses the new `com.fsck` identity, and future checks target the verified public feed.
