import Foundation
import Testing

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
                == "com.jesse.agentic-usage-meter",
        )
        #expect(
            plist["CFBundleName"] as? String
                == "Agentic Usage Meter",
        )
        #expect(plist["CFBundleExecutable"] as? String == "AgenticUsageMeter")
        #expect(plist["CFBundlePackageType"] as? String == "APPL")
        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(plist["LSMinimumSystemVersion"] as? String == "26.0")
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

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
