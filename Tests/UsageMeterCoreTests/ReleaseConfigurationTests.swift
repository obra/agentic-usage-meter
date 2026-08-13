import Foundation
import Testing
import UsageMeterCore

@Suite
struct ReleaseConfigurationTests {
    @Test
    func applicationBundleDeclaresMenuBarReleaseContract() throws {
        let plistURL = repositoryRoot
            .appending(path: "Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(
                from: data,
                format: nil,
            ) as? [String: Any],
        )

        #expect(
            plist["CFBundleIdentifier"] as? String
                == "com.fsck.agentic-usage-meter",
        )
        #expect(
            plist["CFBundleName"] as? String
                == "Agentic Usage Meter",
        )
        #expect(plist["CFBundleExecutable"] as? String == "AgenticUsageMeter")
        #expect(plist["CFBundlePackageType"] as? String == "APPL")
        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(plist["LSMinimumSystemVersion"] as? String == "26.0")
        #expect(
            plist["SUFeedURL"] as? String
                == "https://github.com/prime-radiant-inc/agentic-usage-meter/releases/latest/download/appcast.xml",
        )
        #expect(plist["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(plist["SUAutomaticallyUpdate"] as? Bool == false)

        let publicKey = try #require(plist["SUPublicEDKey"] as? String)
        let publicKeyData = try #require(Data(base64Encoded: publicKey))
        #expect(publicKeyData.count == 32)
    }

    @Test
    func keychainServiceUsesTheFsckProductNamespace() {
        #expect(
            KeychainCredentialStore.defaultService
                == "com.fsck.agentic-usage-meter.credentials",
        )
    }

    @Test
    func releaseVersionMapsSemanticTagsToMonotonicBuildNumbers() throws {
        #expect(try releaseVersion("v0.1.0") == "0.1.0\t1000")
        #expect(try releaseVersion("v0.1.1") == "0.1.1\t1001")
        #expect(try releaseVersion("v1.0.0") == "1.0.0\t1000000")
        #expect(
            try releaseVersion("v999.999.999")
                == "999.999.999\t999999999",
        )
    }

    @Test
    func releaseVersionRejectsMalformedOrOutOfRangeTags() throws {
        #expect(try releaseVersion("1.0.0") == nil)
        #expect(try releaseVersion("v1.0") == nil)
        #expect(try releaseVersion("v1.2.3-beta") == nil)
        #expect(try releaseVersion("v01.0.0") == nil)
        #expect(try releaseVersion("v1.00.0") == nil)
        #expect(try releaseVersion("v1000.0.0") == nil)
        #expect(
            try releaseVersion(
                "v999999999999999999999999999999999999999999.0.0",
            ) == nil,
        )
    }

    @Test
    func releaseNotesExtractOnlyTheRequestedChangelogSection() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true,
        )
        let changelog = temporaryRoot.appending(path: "CHANGELOG.md")
        try Data(
            """
            # Changelog

            ## 0.2.0 - 2026-08-02

            - Later release.

            ## 0.1.0 - 2026-08-01

            - First release.
            - Second detail.

            ## 0.0.1 - 2026-07-31

            - Earlier release.

            """.utf8,
        ).write(to: changelog)

        let result = try runScript(
            repositoryRoot.appending(
                path: "Scripts/extract-release-notes.sh",
            ),
            arguments: ["0.1.0", changelog.path],
        )

        #expect(result.terminationStatus == 0)
        #expect(
            result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                == """
                ## 0.1.0 - 2026-08-01

                - First release.
                - Second detail.
                """,
        )
    }

    @Test
    func releaseNotesFailWithoutProducingOutputForAnAbsentVersion() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true,
        )
        let changelog = temporaryRoot.appending(path: "CHANGELOG.md")
        try Data("## 0.1.0 - 2026-08-01\n\n- First release.\n".utf8)
            .write(to: changelog)

        let result = try runScript(
            repositoryRoot.appending(
                path: "Scripts/extract-release-notes.sh",
            ),
            arguments: ["0.2.0", changelog.path],
        )

        #expect(result.terminationStatus != 0)
        #expect(result.output.isEmpty)
    }

    @Test
    func releaseNotesRejectAdjacentDuplicateVersionHeadings() throws {
        let result = try releaseNotes(
            """
            ## 0.1.0 - 2026-08-01
            - First copy.
            ## 0.1.0 - 2026-08-02
            - Second copy.
            """,
            arguments: ["0.1.0"],
        )

        #expect(result.terminationStatus != 0)
        #expect(result.output.isEmpty)
    }

    @Test
    func releaseNotesRejectSeparatedDuplicateVersionHeadings() throws {
        let result = try releaseNotes(
            """
            ## 0.1.0 - 2026-08-01
            - First copy.
            ## 0.2.0 - 2026-08-02
            - Another release.
            ## 0.1.0 - 2026-08-03
            - Second copy.
            """,
            arguments: ["0.1.0"],
        )

        #expect(result.terminationStatus != 0)
        #expect(result.output.isEmpty)
    }

    @Test
    func releaseNotesRejectExtraArguments() throws {
        let result = try releaseNotes(
            "## 0.1.0 - 2026-08-01\n- First release.\n",
            arguments: ["0.1.0", "unexpected"],
        )

        #expect(result.terminationStatus != 0)
        #expect(result.output.isEmpty)
    }

    @Test
    func assembledReleaseUsesRequestedVersions() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let scriptsDirectory = temporaryRoot.appending(path: "Scripts")
        let resourcesDirectory = temporaryRoot.appending(path: "Resources")
        let toolsDirectory = temporaryRoot.appending(path: "tools")
        let binaryDirectory = temporaryRoot.appending(path: "bin")
        for directory in [
            scriptsDirectory,
            resourcesDirectory,
            toolsDirectory,
            binaryDirectory,
        ] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
        }
        try FileManager.default.copyItem(
            at: repositoryRoot.appending(path: "Scripts/assemble-app.sh"),
            to: scriptsDirectory.appending(path: "assemble-app.sh"),
        )
        try FileManager.default.copyItem(
            at: repositoryRoot.appending(path: "Resources/Info.plist"),
            to: resourcesDirectory.appending(path: "Info.plist"),
        )
        for helper in [
            "embed-sparkle-framework.sh",
            "copy-swiftpm-resource-bundles.sh",
        ] {
            try writeExecutableScript(
                "#!/bin/zsh\nexit 0\n",
                to: scriptsDirectory.appending(path: helper),
            )
        }
        try writeExecutableScript(
            """
            #!/bin/zsh
            if [[ " $* " == *" --show-bin-path "* ]]; then
                print -r -- "$BINARY_DIRECTORY"
            fi

            """,
            to: toolsDirectory.appending(path: "swift"),
        )
        try Data("test executable".utf8).write(
            to: binaryDirectory.appending(path: "AgenticUsageMeter"),
        )

        let result = try runScript(
            scriptsDirectory.appending(path: "assemble-app.sh"),
            environment: [
                "APP_VERSION": "1.2.3",
                "APP_BUILD": "1002003",
                "BINARY_DIRECTORY": binaryDirectory.path,
                "PATH": toolsDirectory.path + ":"
                    + (ProcessInfo.processInfo.environment["PATH"] ?? ""),
            ],
        )

        #expect(result.terminationStatus == 0)
        let generatedPlist = temporaryRoot.appending(
            path: "build/Agentic Usage Meter.app/Contents/Info.plist",
        )
        let plist = try #require(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: generatedPlist),
                format: nil,
            ) as? [String: Any],
        )
        #expect(plist["CFBundleShortVersionString"] as? String == "1.2.3")
        #expect(plist["CFBundleVersion"] as? String == "1002003")
    }

    @Test
    func releasePreflightRejectsDirtyWorktreeBeforeGitHubCalls() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseRepositoryFixture(at: temporaryRoot)
        try Data("uncommitted\n".utf8).write(
            to: temporaryRoot.appending(path: "dirty.txt"),
        )

        let result = try runScript(
            fixture.releaseScript,
            arguments: ["v0.1.0"],
            environment: fixture.environment,
        )

        #expect(result.terminationStatus != 0)
        #expect(result.error.contains("Release requires a clean worktree."))
        #expect(!FileManager.default.fileExists(atPath: fixture.ghLog.path))
    }

    @Test
    func releasePreflightRejectsLightweightTagBeforeGitHubCalls() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseRepositoryFixture(at: temporaryRoot)
        let tagResult = try runExecutable(
            URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", temporaryRoot.path, "tag", "v0.1.0"],
        )
        try #require(tagResult.terminationStatus == 0)
        let statusResult = try runExecutable(
            URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", temporaryRoot.path, "status", "--porcelain"],
        )
        try #require(statusResult.output.isEmpty)

        let result = try runScript(
            fixture.releaseScript,
            arguments: ["v0.1.0"],
            environment: fixture.environment,
        )

        #expect(result.terminationStatus != 0)
        #expect(result.error.contains("v0.1.0 must be an annotated tag."))
        #expect(!FileManager.default.fileExists(atPath: fixture.ghLog.path))
    }

    @Test
    func releasePreflightRejectsMismatchedRemoteTagBeforeGitHubCalls() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseRepositoryFixture(at: temporaryRoot)
        for arguments in [
            ["-C", temporaryRoot.path, "tag", "-a", "v0.1.0", "-m",
             "Release v0.1.0"],
            ["-C", temporaryRoot.path, "remote", "add", "origin",
             "https://github.com/prime-radiant-inc/agentic-usage-meter.git"],
        ] {
            let result = try runExecutable(
                URL(fileURLWithPath: "/usr/bin/git"),
                arguments: arguments,
            )
            try #require(result.terminationStatus == 0)
        }
        var environment = fixture.environment
        environment["REMOTE_TAG_OBJECT"] = String(repeating: "0", count: 40)

        let result = try runScript(
            fixture.releaseScript,
            arguments: ["v0.1.0"],
            environment: environment,
        )

        #expect(result.terminationStatus != 0)
        #expect(result.error.contains("Remote tag v0.1.0 does not match"))
        #expect(!FileManager.default.fileExists(atPath: fixture.ghLog.path))
    }

    @Test
    func swiftPMResourceBundleIsCopiedIntoAppResources() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(
                at: temporaryRoot,
            )
        }
        let binaryDirectory = temporaryRoot.appending(
            path: "bin",
        )
        let sourceBundle = binaryDirectory.appending(
            path: "AgenticUsageMeter_UsageMeterUI.bundle",
        )
        let applicationBundle = temporaryRoot.appending(
            path: "Agentic Usage Meter.app",
        )
        try FileManager.default.createDirectory(
            at: sourceBundle,
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: applicationBundle,
            withIntermediateDirectories: true,
        )
        try Data("provider mark".utf8).write(
            to: sourceBundle.appending(path: "mark.svg"),
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            repositoryRoot.appending(
                path: "Scripts/copy-swiftpm-resource-bundles.sh",
            ).path,
            binaryDirectory.path,
            applicationBundle.path,
        ]
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let copiedResource = applicationBundle
            .appending(path: "Contents/Resources")
            .appending(
                path: "AgenticUsageMeter_UsageMeterUI.bundle",
            )
            .appending(path: "mark.svg")
        #expect(
            try Data(contentsOf: copiedResource)
                == Data("provider mark".utf8),
        )
        let copiedInfoPlist = applicationBundle
            .appending(path: "Contents/Resources")
            .appending(path: "AgenticUsageMeter_UsageMeterUI.bundle")
            .appending(path: "Info.plist")
        let infoPlist = try #require(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: copiedInfoPlist),
                format: nil,
            ) as? [String: Any],
        )
        #expect(
            infoPlist["CFBundleIdentifier"] as? String
                == "com.fsck.agentic-usage-meter.resources",
        )
        #expect(infoPlist["CFBundleName"] as? String == "Usage Meter Resources")
        #expect(infoPlist["CFBundlePackageType"] as? String == "BNDL")
        #expect(infoPlist["CFBundleVersion"] as? String == "1")
    }

    @Test
    func sparkleFrameworkIsEmbeddedWithApplicationRPath() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let sourceFramework = temporaryRoot.appending(
            path: ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework",
        )
        let applicationBundle = temporaryRoot.appending(
            path: "Agentic Usage Meter.app",
        )
        let applicationExecutable = applicationBundle.appending(
            path: "Contents/MacOS/AgenticUsageMeter",
        )
        let fakeInstallNameTool = temporaryRoot.appending(
            path: "install_name_tool",
        )
        let invocationLog = temporaryRoot.appending(path: "invocations.log")
        try FileManager.default.createDirectory(
            at: sourceFramework,
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: applicationExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("framework marker".utf8).write(
            to: sourceFramework.appending(path: "marker"),
        )
        try Data("application executable".utf8).write(
            to: applicationExecutable,
        )
        try Data(
            """
            #!/bin/zsh
            /usr/bin/printf '%s\\n' "$@" >> "$INVOCATION_LOG"

            """.utf8,
        ).write(to: fakeInstallNameTool)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeInstallNameTool.path,
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            repositoryRoot.appending(
                path: "Scripts/embed-sparkle-framework.sh",
            ).path,
            temporaryRoot.path,
            applicationBundle.path,
            applicationExecutable.path,
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "INSTALL_NAME_TOOL_BIN": fakeInstallNameTool.path,
            "INVOCATION_LOG": invocationLog.path,
        ]) { _, new in new }
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(
            FileManager.default.fileExists(
                atPath: applicationBundle
                    .appending(
                        path: "Contents/Frameworks/Sparkle.framework/marker",
                    ).path,
            ),
        )
        let installNameToolArguments = try String(
            contentsOf: invocationLog,
            encoding: .utf8,
        ).split(separator: "\n").map(String.init)
        #expect(
            installNameToolArguments == [
                "-add_rpath",
                "@executable_path/../Frameworks",
                applicationExecutable.path,
            ],
        )
    }

    @Test
    func sparkleNestedCodeIsSignedBeforeApplication() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeSigningFixture(at: temporaryRoot)
        let invocations = try runSignApp(
            fixture: fixture,
            releaseSigning: false,
        )
        for invocation in invocations {
            #expect(
                invocation.filter { $0.hasPrefix("--timestamp") }
                    == ["--timestamp=none"],
            )
        }

        let targets = invocations.compactMap(\.last)
        let applicationIndex = try #require(
            targets.firstIndex(of: fixture.applicationBundle.path),
        )
        let executableIndex = try #require(
            targets.firstIndex(where: {
                $0.hasSuffix("Contents/MacOS/AgenticUsageMeter")
            }),
        )
        let frameworkIndex = try #require(
            targets.firstIndex(where: { $0.hasSuffix("Sparkle.framework") }),
        )
        let resourceBundleIndex = try #require(
            targets.firstIndex(where: { $0.hasSuffix("Resources.bundle") }),
        )
        let nestedSparkleIndices = try [
            "Installer.xpc",
            "Downloader.xpc",
            "Autoupdate",
            "Updater.app",
        ].map { suffix in
            try #require(
                targets.firstIndex(where: { $0.hasSuffix(suffix) }),
            )
        }

        for nestedIndex in nestedSparkleIndices {
            #expect(nestedIndex < frameworkIndex)
        }
        #expect(frameworkIndex < executableIndex)
        #expect(resourceBundleIndex < executableIndex)
        #expect(executableIndex < applicationIndex)
    }

    @Test
    func releaseSigningUsesSecureTimestamp() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeSigningFixture(at: temporaryRoot)
        let invocations = try runSignApp(
            fixture: fixture,
            releaseSigning: true,
        )

        for invocation in invocations {
            #expect(
                invocation.filter { $0.hasPrefix("--timestamp") }
                    == ["--timestamp"],
            )
        }
    }

    private struct SigningFixture {
        let applicationBundle: URL
        let fakeCodesign: URL
        let invocationLog: URL
    }

    private func makeSigningFixture(at temporaryRoot: URL) throws
        -> SigningFixture
    {
        let applicationBundle = temporaryRoot.appending(
            path: "Agentic Usage Meter.app",
        )
        let sparkleFramework = applicationBundle.appending(
            path: "Contents/Frameworks/Sparkle.framework",
        )
        for directory in [
            sparkleFramework.appending(
                path: "Versions/B/XPCServices/Installer.xpc",
            ),
            sparkleFramework.appending(
                path: "Versions/B/XPCServices/Downloader.xpc",
            ),
            sparkleFramework.appending(path: "Versions/B/Updater.app"),
            applicationBundle.appending(
                path: "Contents/Resources/UsageMeterResources.bundle",
            ),
            applicationBundle.appending(path: "Contents/MacOS"),
        ] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
        }
        try Data().write(
            to: sparkleFramework.appending(path: "Versions/B/Autoupdate"),
        )
        try Data().write(
            to: applicationBundle.appending(
                path: "Contents/MacOS/AgenticUsageMeter",
            ),
        )
        try Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key>
            <string>com.fsck.agentic-usage-meter.test-resources</string>
            <key>CFBundlePackageType</key><string>BNDL</string>
            <key>CFBundleVersion</key><string>1</string>
            </dict></plist>

            """.utf8,
        ).write(
            to: applicationBundle.appending(
                path: "Contents/Resources/UsageMeterResources.bundle/Info.plist",
            ),
        )

        let fakeCodesign = temporaryRoot.appending(path: "codesign")
        let invocationLog = temporaryRoot.appending(path: "invocations.log")
        try writeExecutableScript(
            """
            #!/bin/zsh
            {
                separator=
                for argument in "$@"; do
                    print -rn -- "${separator}${argument}"
                    separator=$'\\t'
                done
                print
            } >> "$INVOCATION_LOG"

            """,
            to: fakeCodesign,
        )

        return SigningFixture(
            applicationBundle: applicationBundle,
            fakeCodesign: fakeCodesign,
            invocationLog: invocationLog,
        )
    }

    private func runSignApp(
        fixture: SigningFixture,
        releaseSigning: Bool,
    ) throws -> [[String]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            repositoryRoot.appending(path: "Scripts/sign-app.sh").path,
            fixture.applicationBundle.path,
            "Developer ID Application: Example (TEAMID)",
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "CODESIGN_BIN": fixture.fakeCodesign.path,
            "INVOCATION_LOG": fixture.invocationLog.path,
            "RELEASE_SIGNING": releaseSigning ? "1" : "0",
        ]) { _, new in new }
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        try #require(process.terminationStatus == 0)
        return try String(
            contentsOf: fixture.invocationLog,
            encoding: .utf8,
        ).split(separator: "\n").map { line in
            line.split(separator: "\t").map(String.init)
        }
    }

    @Test
    func applicationRelaunchWaitsForThePreviousProcessToExit() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true,
        )
        let fakePkill = temporaryRoot.appending(path: "pkill")
        let fakePgrep = temporaryRoot.appending(path: "pgrep")
        let fakeSleep = temporaryRoot.appending(path: "sleep")
        let fakeOpen = temporaryRoot.appending(path: "open")
        let pgrepCount = temporaryRoot.appending(path: "pgrep-count")
        let sleepLog = temporaryRoot.appending(path: "sleep.log")
        let openLog = temporaryRoot.appending(path: "open.log")
        try writeExecutableScript(
            """
            #!/bin/zsh
            exit 0

            """,
            to: fakePkill,
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            count=0
            if [[ -f "$PGREP_COUNT" ]]; then
                count=$(/bin/cat "$PGREP_COUNT")
            fi
            (( count += 1 ))
            print -r -- "$count" > "$PGREP_COUNT"
            (( count < 3 ))

            """,
            to: fakePgrep,
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            print -r -- "$@" >> "$SLEEP_LOG"

            """,
            to: fakeSleep,
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            print -r -- "$@" >> "$OPEN_LOG"

            """,
            to: fakeOpen,
        )

        let applicationBundle = temporaryRoot.appending(
            path: "Agentic Usage Meter.app",
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            repositoryRoot.appending(
                path: "Scripts/relaunch-application.sh",
            ).path,
            "AgenticUsageMeter",
            applicationBundle.path,
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PKILL_BIN": fakePkill.path,
            "PGREP_BIN": fakePgrep.path,
            "SLEEP_BIN": fakeSleep.path,
            "OPEN_BIN": fakeOpen.path,
            "PGREP_COUNT": pgrepCount.path,
            "SLEEP_LOG": sleepLog.path,
            "OPEN_LOG": openLog.path,
        ]) { _, new in new }
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(
            try String(contentsOf: sleepLog, encoding: .utf8)
                .split(separator: "\n").count == 2,
        )
        #expect(
            try String(contentsOf: openLog, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                == applicationBundle.path,
        )
    }

    @Test
    func applicationRelaunchFailsRatherThanOpeningAfterExitTimeout() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true,
        )
        let fakePkill = temporaryRoot.appending(path: "pkill")
        let fakePgrep = temporaryRoot.appending(path: "pgrep")
        let fakeSleep = temporaryRoot.appending(path: "sleep")
        let fakeOpen = temporaryRoot.appending(path: "open")
        let openLog = temporaryRoot.appending(path: "open.log")
        for tool in [fakePkill, fakePgrep, fakeSleep] {
            try writeExecutableScript(
                """
                #!/bin/zsh
                exit 0

                """,
                to: tool,
            )
        }
        try writeExecutableScript(
            """
            #!/bin/zsh
            print -r -- "$@" >> "$OPEN_LOG"

            """,
            to: fakeOpen,
        )

        let errorOutput = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            repositoryRoot.appending(
                path: "Scripts/relaunch-application.sh",
            ).path,
            "AgenticUsageMeter",
            temporaryRoot.appending(path: "Agentic Usage Meter.app").path,
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PKILL_BIN": fakePkill.path,
            "PGREP_BIN": fakePgrep.path,
            "SLEEP_BIN": fakeSleep.path,
            "OPEN_BIN": fakeOpen.path,
            "OPEN_LOG": openLog.path,
        ]) { _, new in new }
        process.standardError = errorOutput

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus != 0)
        #expect(!FileManager.default.fileExists(atPath: openLog.path))
        let errorMessage = String(
            decoding: errorOutput.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self,
        )
        #expect(errorMessage.contains("AgenticUsageMeter"))
        #expect(errorMessage.contains("timeout"))
    }

    @Test
    func localSigningSelectsAStableDeveloperIDIdentity() throws {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            repositoryRoot.appending(
                path: "Scripts/select-local-signing-identity.sh",
            ).path,
        ]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        try process.run()
        input.fileHandleForWriting.write(
            Data(
                """
                    1) AAAA \"Apple Development: Example (TEAMID)\"
                    2) BBBB \"Developer ID Application: Example (TEAMID)\"
                       2 valid identities found

                """.utf8,
            ),
        )
        input.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let selectedIdentity = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self,
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(
            selectedIdentity
                == "Developer ID Application: Example (TEAMID)",
        )
    }

    @Test
    func localSigningRejectsAmbiguousDeveloperIDIdentities() throws {
        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            repositoryRoot.appending(
                path: "Scripts/select-local-signing-identity.sh",
            ).path,
        ]
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        input.fileHandleForWriting.write(
            Data(
                """
                    1) AAAA "Developer ID Application: Example (TEAMONE)"
                    2) BBBB "Developer ID Application: Example (TEAMTWO)"
                       2 valid identities found

                """.utf8,
            ),
        )
        input.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        #expect(process.terminationStatus != 0)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private struct ScriptResult {
        let terminationStatus: Int32
        let output: String
        let error: String
    }

    private struct ReleaseRepositoryFixture {
        let releaseScript: URL
        let ghLog: URL
        let environment: [String: String]
    }

    private func makeReleaseRepositoryFixture(at root: URL) throws
        -> ReleaseRepositoryFixture
    {
        let scriptsDirectory = root.appending(path: "Scripts")
        let toolsDirectory = root.appending(path: "tools")
        try FileManager.default.createDirectory(
            at: scriptsDirectory,
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: toolsDirectory,
            withIntermediateDirectories: true,
        )
        try FileManager.default.copyItem(
            at: repositoryRoot.appending(path: "Scripts/release-version.sh"),
            to: scriptsDirectory.appending(path: "release-version.sh"),
        )
        let releaseScript = scriptsDirectory.appending(path: "release.sh")
        let sourceReleaseScript = repositoryRoot.appending(
            path: "Scripts/release.sh",
        )
        if FileManager.default.fileExists(atPath: sourceReleaseScript.path) {
            try FileManager.default.copyItem(
                at: sourceReleaseScript,
                to: releaseScript,
            )
        }
        let ghLog = root.appending(path: "gh.log")
        try writeExecutableScript(
            """
            #!/bin/zsh
            print -r -- "$@" >> "$GH_LOG"
            exit 99

            """,
            to: toolsDirectory.appending(path: "gh"),
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            if [[ "$1" == ls-remote && -n "${REMOTE_TAG_OBJECT:-}" ]]; then
                /usr/bin/printf '%s\t%s\n' "$REMOTE_TAG_OBJECT" "$4"
                exit 0
            fi
            exec /usr/bin/git "$@"

            """,
            to: toolsDirectory.appending(path: "git"),
        )
        try Data("fixture\n".utf8).write(
            to: root.appending(path: "README.md"),
        )
        for arguments in [
            ["-C", root.path, "init", "-q"],
            ["-C", root.path, "config", "user.name", "Release Test"],
            [
                "-C", root.path, "config", "user.email",
                "release-test@example.invalid",
            ],
            ["-C", root.path, "add", "README.md", "Scripts", "tools"],
            ["-C", root.path, "commit", "-q", "-m", "Release fixture"],
        ] {
            let result = try runExecutable(
                URL(fileURLWithPath: "/usr/bin/git"),
                arguments: arguments,
            )
            try #require(result.terminationStatus == 0)
        }
        return ReleaseRepositoryFixture(
            releaseScript: releaseScript,
            ghLog: ghLog,
            environment: [
                "GH_BIN": toolsDirectory.appending(path: "gh").path,
                "GH_LOG": ghLog.path,
                "GIT_BIN": toolsDirectory.appending(path: "git").path,
                "PATH": toolsDirectory.path + ":"
                    + (ProcessInfo.processInfo.environment["PATH"] ?? ""),
            ],
        )
    }

    private func releaseVersion(_ tag: String) throws -> String? {
        let result = try runScript(
            repositoryRoot.appending(path: "Scripts/release-version.sh"),
            arguments: [tag],
        )
        guard result.terminationStatus == 0 else {
            return nil
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func releaseNotes(
        _ changelogContents: String,
        arguments: [String],
    ) throws -> ScriptResult {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true,
        )
        let changelog = temporaryRoot.appending(path: "CHANGELOG.md")
        try Data(changelogContents.utf8).write(to: changelog)
        return try runScript(
            repositoryRoot.appending(
                path: "Scripts/extract-release-notes.sh",
            ),
            arguments: [arguments[0], changelog.path]
                + Array(arguments.dropFirst()),
        )
    }

    private func runScript(
        _ script: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
    ) throws -> ScriptResult {
        try runExecutable(
            URL(fileURLWithPath: "/bin/zsh"),
            arguments: [script.path] + arguments,
            environment: environment,
        )
    }

    private func runExecutable(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
    ) throws -> ScriptResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            environment,
        ) { _, new in new }
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        return ScriptResult(
            terminationStatus: process.terminationStatus,
            output: String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self,
            ),
            error: String(
                decoding: error.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self,
            ),
        )
    }

    private func writeExecutableScript(
        _ contents: String,
        to file: URL,
    ) throws {
        try Data(contents.utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: file.path,
        )
    }
}
