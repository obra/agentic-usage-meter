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
                == "https://github.com/obra/agentic-usage-meter/releases/latest/download/appcast.xml",
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
        #expect(
            try String(contentsOf: invocationLog, encoding: .utf8)
                .contains(
                    "Agentic Usage Meter.app/Contents/MacOS/AgenticUsageMeter",
                ),
        )
    }

    @Test
    func sparkleNestedCodeIsSignedBeforeApplication() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let applicationBundle = temporaryRoot.appending(
            path: "Agentic Usage Meter.app",
        )
        let sparkleFramework = applicationBundle.appending(
            path: "Contents/Frameworks/Sparkle.framework",
        )
        let installer = sparkleFramework.appending(
            path: "Versions/B/XPCServices/Installer.xpc",
        )
        let downloader = sparkleFramework.appending(
            path: "Versions/B/XPCServices/Downloader.xpc",
        )
        let autoupdate = sparkleFramework.appending(
            path: "Versions/B/Autoupdate",
        )
        let updater = sparkleFramework.appending(
            path: "Versions/B/Updater.app",
        )
        let applicationExecutable = applicationBundle.appending(
            path: "Contents/MacOS/AgenticUsageMeter",
        )
        let resourcesDirectory = applicationBundle.appending(
            path: "Contents/Resources",
        )
        for directory in [
            installer,
            downloader,
            updater,
            applicationExecutable.deletingLastPathComponent(),
            resourcesDirectory,
        ] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
        }
        try Data().write(to: autoupdate)
        try Data().write(to: applicationExecutable)

        let fakeCodesign = temporaryRoot.appending(path: "codesign")
        let invocationLog = temporaryRoot.appending(path: "invocations.log")
        try Data(
            """
            #!/bin/zsh
            /usr/bin/printf '%s\\n' "${@[-1]}" >> "$INVOCATION_LOG"

            """.utf8,
        ).write(to: fakeCodesign)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeCodesign.path,
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            repositoryRoot.appending(path: "Scripts/sign-app.sh").path,
            applicationBundle.path,
            "Developer ID Application: Example (TEAMID)",
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "CODESIGN_BIN": fakeCodesign.path,
            "INVOCATION_LOG": invocationLog.path,
        ]) { _, new in new }
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let targets = try String(contentsOf: invocationLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let applicationIndex = try #require(
            targets.firstIndex(of: applicationBundle.path),
        )
        let installerIndex = try #require(
            targets.firstIndex(where: { $0.hasSuffix("Installer.xpc") }),
        )
        let frameworkIndex = try #require(
            targets.firstIndex(where: { $0.hasSuffix("Sparkle.framework") }),
        )
        #expect(targets.last == applicationBundle.path)
        #expect(installerIndex < applicationIndex)
        #expect(frameworkIndex < applicationIndex)
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
