import Foundation
import Testing

@Suite
struct ReleaseAutomationTests {
    @Test
    func appcastValidatorAcceptsRealSparkleSiblingElements() throws {
        let result = try validateAppcast(
            """
            <?xml version="1.0" standalone="yes"?>
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
              <channel>
                <title>Agentic Usage Meter</title>
                <item>
                  <title>0.1.0</title>
                  <pubDate>Sun, 02 Aug 2026 12:23:10 -0700</pubDate>
                  <link>https://github.com/obra/agentic-usage-meter</link>
                  <sparkle:version>1000</sparkle:version>
                  <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
                  <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
                  <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
                  <sparkle:releaseNotesLink>https://github.com/obra/agentic-usage-meter/releases/latest/download/Agentic-Usage-Meter-0.1.0.md</sparkle:releaseNotesLink>
                  <enclosure
                    url="https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/Agentic-Usage-Meter-0.1.0.zip"
                    length="2466625"
                    type="application/octet-stream"
                    sparkle:edSignature="fixture-signature" />
                </item>
              </channel>
            </rss>
            """,
        )

        #expect(result.terminationStatus == 0)
    }

    @Test
    func appcastValidatorRejectsExpectedStringsOnlyInAComment() throws {
        let result = try validateAppcast(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item>
                  <link>https://github.com/obra/agentic-usage-meter</link>
                  <!--
                    <sparkle:version>1000</sparkle:version>
                    <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
                    <enclosure url="https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/Agentic-Usage-Meter-0.1.0.zip" />
                  -->
                  <sparkle:version>999</sparkle:version>
                  <sparkle:shortVersionString>9.9.9</sparkle:shortVersionString>
                  <enclosure
                    url="https://invalid.example/app.zip" />
                </item>
              </channel>
            </rss>
            """,
        )

        #expect(result.terminationStatus != 0)
    }

    @Test
    func appcastValidatorRejectsMetadataSplitAcrossItems() throws {
        let result = try validateAppcast(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item>
                  <link>https://github.com/obra/agentic-usage-meter</link>
                  <enclosure
                    url="https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/Agentic-Usage-Meter-0.1.0.zip" />
                </item>
                <item>
                  <sparkle:version>1000</sparkle:version>
                  <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
                </item>
              </channel>
            </rss>
            """,
        )

        #expect(result.terminationStatus != 0)
    }

    @Test
    func appcastValidatorRejectsMetadataOutsideTheReleaseItem() throws {
        let result = try validateAppcast(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <sparkle:version>1000</sparkle:version>
                <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
                <item>
                  <link>https://github.com/obra/agentic-usage-meter</link>
                  <enclosure
                    url="https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/Agentic-Usage-Meter-0.1.0.zip" />
                </item>
              </channel>
            </rss>
            """,
        )

        #expect(result.terminationStatus != 0)
    }

    @Test
    func appcastValidatorRejectsDuplicateMatchingItemsAndEnclosures() throws {
        let result = try validateAppcast(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item>
                  <link>https://github.com/obra/agentic-usage-meter</link>
                  <sparkle:version>1000</sparkle:version>
                  <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
                  <enclosure
                    url="https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/Agentic-Usage-Meter-0.1.0.zip" />
                </item>
                <item>
                  <link>https://github.com/obra/agentic-usage-meter</link>
                  <sparkle:version>1000</sparkle:version>
                  <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
                  <enclosure
                    url="https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/Agentic-Usage-Meter-0.1.0.zip" />
                </item>
              </channel>
            </rss>
            """,
        )

        #expect(result.terminationStatus != 0)
    }

    @Test
    func appcastValidatorRejectsWrongChannelLink() throws {
        let result = try validateAppcast(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item>
                  <link>https://invalid.example</link>
                  <sparkle:version>1000</sparkle:version>
                  <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
                  <enclosure
                    url="https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/Agentic-Usage-Meter-0.1.0.zip" />
                </item>
              </channel>
            </rss>
            """,
        )

        #expect(result.terminationStatus != 0)
    }

    @Test
    func appcastValidatorRejectsProjectLinkOnDifferentItem() throws {
        let result = try validateAppcast(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item>
                  <sparkle:version>1000</sparkle:version>
                  <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
                  <enclosure
                    url="https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/Agentic-Usage-Meter-0.1.0.zip" />
                </item>
                <item>
                  <link>https://github.com/obra/agentic-usage-meter</link>
                </item>
              </channel>
            </rss>
            """,
        )

        #expect(result.terminationStatus != 0)
    }

    @Test
    func releaseOrchestrationPublishesExpectedAssetsInOrder() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseFixture(at: temporaryRoot)

        let result = try fixture.run()

        try #require(
            result.terminationStatus == 0,
            "release stderr: \(result.error)",
        )
        let events = try fixture.events()
        #expect(
            events == [
                "git:ls-remote:1",
                "gh:auth",
                "gh:user",
                "gh:release-probe",
                "security",
                "notary-history",
                "sparkle-key",
                "swift-test",
                "assemble",
                "sign",
                "ditto:notarization",
                "notary-submit",
                "staple",
                "verify",
                "ditto:final",
                "appcast",
                "git:ls-remote:2",
                "gh:release-create",
            ],
        )

        let releaseDirectory = fixture.repository.appending(
            path: "build/releases/v0.1.0",
        )
        let archive = releaseDirectory.appending(
            path: "Agentic-Usage-Meter-0.1.0.zip",
        )
        let notes = releaseDirectory.appending(
            path: "Agentic-Usage-Meter-0.1.0.md",
        )
        let appcast = releaseDirectory.appending(path: "appcast.xml")
        let releaseEntries = try FileManager.default.contentsOfDirectory(
            atPath: releaseDirectory.path,
        ).sorted()
        #expect(
            releaseEntries == [
                "Agentic-Usage-Meter-0.1.0.md",
                "Agentic-Usage-Meter-0.1.0.zip",
                "appcast.xml",
            ],
        )
        let appcastArguments = try fixture.appcastArguments()
        #expect(
            appcastArguments == [
                "--account",
                "agentic-usage-meter",
                "--download-url-prefix",
                "https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/",
                "--maximum-deltas",
                "0",
                "--maximum-versions",
                "3",
                "--link",
                "https://github.com/obra/agentic-usage-meter",
                "-o",
                appcast.path,
                releaseDirectory.path,
            ],
        )
        let githubArguments = try fixture.githubArguments()
        #expect(
            githubArguments == [
                "release",
                "create",
                "v0.1.0",
                archive.path,
                notes.path,
                appcast.path,
                "--repo",
                "obra/agentic-usage-meter",
                "--verify-tag",
                "--title",
                "Agentic Usage Meter 0.1.0",
                "--notes-file",
                notes.path,
            ],
        )
    }

    @Test
    func releaseRequiresTheAnnotatedTagToExistOnOrigin() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseFixture(at: temporaryRoot)

        let result = try fixture.run(
            environment: ["REMOTE_TAG_OBJECT": "missing"],
        )

        #expect(result.terminationStatus != 0)
        #expect(result.error.contains("must already exist on origin"))
        let events = try fixture.events()
        #expect(!events.contains("git:push"))
        #expect(!events.contains("gh:release-create"))
    }

    @Test
    func releaseRechecksCleanWorktreeAfterTests() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseFixture(at: temporaryRoot)

        let result = try fixture.run(failure: "dirty-after-tests")

        #expect(result.terminationStatus != 0)
        let events = try fixture.events()
        #expect(!events.contains("assemble"))
        #expect(!events.contains("gh:release-create"))
    }

    @Test
    func releaseRechecksHeadAndAnnotatedTagAfterTests() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseFixture(at: temporaryRoot)

        let result = try fixture.run(failure: "head-after-tests")

        #expect(result.terminationStatus != 0)
        let events = try fixture.events()
        #expect(!events.contains("assemble"))
        #expect(!events.contains("gh:release-create"))
    }

    @Test
    func releaseRefusesEveryExistingVersionedPathWithoutRemovingIt() throws {
        for kind in ["file", "directory", "symlink"] {
            let temporaryRoot = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
            defer {
                try? FileManager.default.removeItem(at: temporaryRoot)
            }
            let fixture = try makeReleaseFixture(at: temporaryRoot)
            let releasePath = fixture.repository.appending(
                path: "build/releases/v0.1.0",
            )
            try FileManager.default.createDirectory(
                at: releasePath.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            let marker: URL
            if kind == "file" {
                try Data("existing".utf8).write(to: releasePath)
                marker = releasePath
            } else if kind == "directory" {
                try FileManager.default.createDirectory(
                    at: releasePath,
                    withIntermediateDirectories: false,
                )
                marker = releasePath.appending(path: "marker")
                try Data("existing".utf8).write(to: marker)
            } else {
                let target = temporaryRoot.appending(path: "symlink-target")
                try Data("existing".utf8).write(to: target)
                try FileManager.default.createSymbolicLink(
                    at: releasePath,
                    withDestinationURL: target,
                )
                marker = target
            }

            let result = try fixture.run()

            #expect(result.terminationStatus != 0)
            #expect(FileManager.default.fileExists(atPath: marker.path))
        }
    }

    @Test
    func releaseRejectsSymlinkedParentsWithoutFollowingThem() throws {
        for parent in ["build", "build/releases"] {
            let temporaryRoot = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
            defer {
                try? FileManager.default.removeItem(at: temporaryRoot)
            }
            let fixture = try makeReleaseFixture(at: temporaryRoot)
            let outside = temporaryRoot.appending(path: "outside")
            try FileManager.default.createDirectory(
                at: outside,
                withIntermediateDirectories: true,
            )
            let marker = outside.appending(path: "marker")
            try Data("existing".utf8).write(to: marker)
            let symlink = fixture.repository.appending(path: parent)
            try FileManager.default.createDirectory(
                at: symlink.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try FileManager.default.createSymbolicLink(
                at: symlink,
                withDestinationURL: outside,
            )

            let result = try fixture.run()

            #expect(result.terminationStatus != 0)
            #expect(result.error.contains("Refusing symlinked release parent"))
            #expect(FileManager.default.fileExists(atPath: marker.path))
            let events = try fixture.events()
            #expect(!events.contains("assemble"))
        }
    }

    @Test
    func releaseRejectsHiddenAppcastInputBeforeGeneration() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseFixture(at: temporaryRoot)

        let result = try fixture.run(failure: "dotfile")

        #expect(result.terminationStatus != 0)
        let events = try fixture.events()
        #expect(!events.contains("appcast"))
        #expect(!events.contains("gh:release-create"))
    }

    @Test
    func notaryFailureStopsBeforeGitHubReleaseCreation() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseFixture(at: temporaryRoot)

        let result = try fixture.run(failure: "notary")

        #expect(result.terminationStatus != 0)
        let events = try fixture.events()
        #expect(events.contains("notary-submit"))
        #expect(!events.contains("staple"))
        #expect(!events.contains("gh:release-create"))
    }

    @Test
    func verificationFailureStopsBeforeGitHubReleaseCreation() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseFixture(at: temporaryRoot)

        let result = try fixture.run(failure: "verify")

        #expect(result.terminationStatus != 0)
        let events = try fixture.events()
        #expect(events.contains("verify"))
        #expect(!events.contains("appcast"))
        #expect(!events.contains("gh:release-create"))
    }

    @Test
    func appcastValidationFailureStopsBeforeGitHubReleaseCreation() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseFixture(at: temporaryRoot)

        let result = try fixture.run(failure: "appcast-validation")

        #expect(result.terminationStatus != 0)
        let events = try fixture.events()
        #expect(events.contains("appcast"))
        #expect(!events.contains("gh:release-create"))
    }

    @Test
    func remoteTagChangeBeforeUploadStopsGitHubReleaseCreation() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseFixture(at: temporaryRoot)

        let result = try fixture.run(
            environment: [
                "REMOTE_TAG_OBJECT_LATER": String(repeating: "0", count: 40),
            ],
        )

        #expect(result.terminationStatus != 0)
        let events = try fixture.events()
        #expect(events.contains("git:ls-remote:2"))
        #expect(!events.contains("gh:release-create"))
    }

    @Test
    func failedGitHubUploadReportsPotentialPartialRelease() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseFixture(at: temporaryRoot)

        let result = try fixture.run(failure: "github")

        #expect(result.terminationStatus != 0)
        #expect(result.error.contains("may be partial"))
        #expect(result.error.contains("inspect"))
        let releaseDirectory = fixture.repository.appending(
            path: "build/releases/v0.1.0",
        )
        #expect(FileManager.default.fileExists(atPath: releaseDirectory.path))
        let events = try fixture.events()
        #expect(events.contains("gh:release-create"))
    }

    @Test
    func actionsTokenWithPushAccessReleasesWithoutUserIdentity() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseFixture(at: temporaryRoot)

        let result = try fixture.run(
            environment: [
                "GITHUB_ACTIONS": "true",
                "GITHUB_REPOSITORY": "obra/agentic-usage-meter",
                "GH_USER_UNAVAILABLE": "1",
            ],
        )

        #expect(result.terminationStatus == 0)
        let events = try fixture.events()
        #expect(events.contains("gh:repo-access"))
        #expect(events.contains("gh:release-create"))
        #expect(!events.contains("gh:user"))
    }

    @Test
    func localRunWithoutTheObraIdentityStops() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        let fixture = try makeReleaseFixture(at: temporaryRoot)

        let result = try fixture.run(
            environment: [
                "GH_USER_UNAVAILABLE": "1",
            ],
        )

        #expect(result.terminationStatus != 0)
        #expect(result.error.contains("not authenticated as obra"))
        let events = try fixture.events()
        #expect(!events.contains("gh:release-create"))
    }

    private struct ScriptResult {
        let terminationStatus: Int32
        let output: String
        let error: String
    }

    private struct ReleaseFixture {
        let repository: URL
        let releaseScript: URL
        let environment: [String: String]
        let eventLog: URL
        let appcastArgumentsLog: URL
        let githubArgumentsLog: URL

        func run(
            failure: String? = nil,
            environment overrides: [String: String] = [:],
        ) throws -> ScriptResult {
            var runEnvironment = environment
            if let failure {
                runEnvironment["FAIL_PHASE"] = failure
            }
            runEnvironment.merge(overrides) { _, new in new }
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [releaseScript.path, "v0.1.0"]
            process.environment = ProcessInfo.processInfo.environment.merging(
                runEnvironment,
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

        func events() throws -> [String] {
            try lines(at: eventLog)
        }

        func appcastArguments() throws -> [String] {
            try lines(at: appcastArgumentsLog)
        }

        func githubArguments() throws -> [String] {
            try lines(at: githubArgumentsLog)
        }

        private func lines(at file: URL) throws -> [String] {
            try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)
        }
    }

    private func makeReleaseFixture(at root: URL) throws -> ReleaseFixture {
        let repository = root.appending(path: "repository")
        let state = root.appending(path: "state")
        let scripts = repository.appending(path: "Scripts")
        let tools = repository.appending(path: "tools")
        let sparkleTools = repository.appending(
            path: ".build/artifacts/sparkle/Sparkle/bin",
        )
        for directory in [repository, state, scripts, tools, sparkleTools] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
        }

        for scriptName in [
            "release.sh",
            "release-version.sh",
            "extract-release-notes.sh",
            "validate-appcast.sh",
        ] {
            let source = repositoryRoot.appending(path: "Scripts/\(scriptName)")
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(
                    at: source,
                    to: scripts.appending(path: scriptName),
                )
            }
        }

        let eventLog = state.appending(path: "events.log")
        let appcastArgumentsLog = state.appending(path: "appcast-arguments.log")
        let githubArgumentsLog = state.appending(path: "github-arguments.log")
        let remoteCalls = state.appending(path: "remote-calls")

        try writeExecutableScript(
            """
            #!/bin/zsh
            set -euo pipefail
            if [[ "$1" == ls-remote ]]; then
                calls=0
                if [[ -f "$REMOTE_CALLS" ]]; then
                    calls=$(/bin/cat "$REMOTE_CALLS")
                fi
                (( calls += 1 ))
                print -r -- "$calls" > "$REMOTE_CALLS"
                print -r -- "git:ls-remote:$calls" >> "$EVENT_LOG"
                remote_object="$REMOTE_TAG_OBJECT"
                if (( calls > 1 )) && [[ -n "${REMOTE_TAG_OBJECT_LATER:-}" ]]; then
                    remote_object="$REMOTE_TAG_OBJECT_LATER"
                fi
                if [[ "$remote_object" != missing ]]; then
                    /usr/bin/printf '%s\t%s\n' \
                        "$remote_object" "refs/tags/v0.1.0"
                fi
                exit 0
            fi
            if [[ "$1" == push ]]; then
                print -r -- 'git:push' >> "$EVENT_LOG"
                exit 97
            fi
            exec /usr/bin/git "$@"

            """,
            to: tools.appending(path: "git"),
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            set -euo pipefail
            if [[ "$1" == auth && "$2" == status ]]; then
                print -r -- 'gh:auth' >> "$EVENT_LOG"
                exit 0
            fi
            if [[ "$1" == api && "$2" == user ]]; then
                print -r -- 'gh:user' >> "$EVENT_LOG"
                [[ "${GH_USER_UNAVAILABLE:-}" != 1 ]] || exit 1
                print -r -- obra
                exit 0
            fi
            if [[ "$1" == api && "$2" == repos/obra/agentic-usage-meter \
                && "${3:-}" == --jq && "${4:-}" == .full_name ]]; then
                print -r -- 'gh:repo-access' >> "$EVENT_LOG"
                print -r -- obra/agentic-usage-meter
                exit 0
            fi
            if [[ "$1" == api && "$2" == repos/* ]]; then
                print -r -- 'gh:release-probe' >> "$EVENT_LOG"
                print -r -- 'HTTP/2.0 404 Not Found'
                exit 1
            fi
            if [[ "$1" == release && "$2" == create ]]; then
                print -r -- 'gh:release-create' >> "$EVENT_LOG"
                for argument in "$@"; do
                    print -r -- "$argument" >> "$GH_ARGUMENTS_LOG"
                done
                [[ "${FAIL_PHASE:-}" != github ]] || exit 96
                exit 0
            fi
            exit 95

            """,
            to: tools.appending(path: "gh"),
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            print -r -- security >> "$EVENT_LOG"
            print -r -- '  1) HASH "Developer ID Application: Fixture (TEAMID)"'

            """,
            to: tools.appending(path: "security"),
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            set -euo pipefail
            if [[ "$1" == notarytool && "$2" == history ]]; then
                print -r -- notary-history >> "$EVENT_LOG"
                exit 0
            fi
            if [[ "$1" == notarytool && "$2" == submit ]]; then
                print -r -- notary-submit >> "$EVENT_LOG"
                [[ "${FAIL_PHASE:-}" != notary ]] || exit 94
                exit 0
            fi
            if [[ "$1" == stapler && "$2" == staple ]]; then
                print -r -- staple >> "$EVENT_LOG"
                exit 0
            fi
            exit 93

            """,
            to: tools.appending(path: "xcrun"),
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            set -euo pipefail
            print -r -- swift-test >> "$EVENT_LOG"
            if [[ "${FAIL_PHASE:-}" == dirty-after-tests ]]; then
                print -r -- dirty > "$REPOSITORY_FIXTURE_ROOT/dirty-after-tests"
            fi
            if [[ "${FAIL_PHASE:-}" == head-after-tests ]]; then
                /usr/bin/git -C "$REPOSITORY_FIXTURE_ROOT" \
                    commit -q --allow-empty -m 'Changed after tests'
            fi

            """,
            to: tools.appending(path: "swift"),
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            print -r -- assemble >> "$EVENT_LOG"
            /bin/mkdir -p \
                "$REPOSITORY_FIXTURE_ROOT/build/Agentic Usage Meter.app/Contents"

            """,
            to: scripts.appending(path: "assemble-app.sh"),
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            print -r -- sign >> "$EVENT_LOG"

            """,
            to: scripts.appending(path: "sign-app.sh"),
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            print -r -- verify >> "$EVENT_LOG"
            [[ "${FAIL_PHASE:-}" != verify ]] || exit 92

            """,
            to: scripts.appending(path: "verify-release.sh"),
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            set -euo pipefail
            destination=${@[-1]}
            /bin/mkdir -p "${destination:h}"
            if [[ "${destination:t}" == notarization.zip ]]; then
                print -r -- ditto:notarization >> "$EVENT_LOG"
            else
                print -r -- ditto:final >> "$EVENT_LOG"
            fi
            print -r -- archive > "$destination"
            if [[ "${FAIL_PHASE:-}" == dotfile \
                && "${destination:t}" != notarization.zip ]]; then
                print -r -- unexpected > "${destination:h}/.unexpected"
            fi

            """,
            to: tools.appending(path: "ditto"),
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            print -r -- sparkle-key >> "$EVENT_LOG"

            """,
            to: sparkleTools.appending(path: "generate_keys"),
        )
        try writeExecutableScript(
            """
            #!/bin/zsh
            set -euo pipefail
            print -r -- appcast >> "$EVENT_LOG"
            output=
            while (( $# > 0 )); do
                print -r -- "$1" >> "$APPCAST_ARGUMENTS_LOG"
                if [[ "$1" == -o ]]; then
                    output=$2
                fi
                shift
            done
            if [[ "${FAIL_PHASE:-}" == appcast-validation ]]; then
                item='<!-- <sparkle:version>1000</sparkle:version><sparkle:shortVersionString>0.1.0</sparkle:shortVersionString><enclosure url="https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/Agentic-Usage-Meter-0.1.0.zip" /> --><link>https://github.com/obra/agentic-usage-meter</link><sparkle:version>999</sparkle:version><sparkle:shortVersionString>9.9.9</sparkle:shortVersionString><enclosure url="https://invalid.example/app.zip" />'
            else
                item='<link>https://github.com/obra/agentic-usage-meter</link><sparkle:version>1000</sparkle:version><sparkle:shortVersionString>0.1.0</sparkle:shortVersionString><enclosure url="https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/Agentic-Usage-Meter-0.1.0.zip" />'
            fi
            /usr/bin/printf '%s\n' \
                '<?xml version="1.0" encoding="UTF-8"?>' \
                '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>' \
                '<item>' \
                "$item" \
                '</item></channel></rss>' \
                > "$output"

            """,
            to: sparkleTools.appending(path: "generate_appcast"),
        )

        try Data(
            """
            # Changelog

            ## 0.1.0 - 2026-08-01

            - Fixture release.

            """.utf8,
        ).write(to: repository.appending(path: "CHANGELOG.md"))
        try Data("build\n".utf8).write(
            to: repository.appending(path: ".gitignore"),
        )

        for arguments in [
            ["-C", repository.path, "init", "-q"],
            ["-C", repository.path, "config", "user.name", "Release Test"],
            [
                "-C", repository.path, "config", "user.email",
                "release-test@example.invalid",
            ],
            ["-C", repository.path, "add", "."],
            ["-C", repository.path, "commit", "-q", "-m", "Release fixture"],
            [
                "-C", repository.path, "tag", "-a", "v0.1.0", "-m",
                "Release v0.1.0",
            ],
            [
                "-C", repository.path, "remote", "add", "origin",
                "https://github.com/obra/agentic-usage-meter.git",
            ],
        ] {
            let result = try runExecutable(
                URL(fileURLWithPath: "/usr/bin/git"),
                arguments: arguments,
            )
            try #require(result.terminationStatus == 0)
        }
        let tagObject = try runExecutable(
            URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", repository.path, "rev-parse", "v0.1.0"],
        ).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalRepositoryPath = try runExecutable(
            URL(fileURLWithPath: "/bin/zsh"),
            arguments: [
                "-f", "-c", "print -r -- ${1:A}", "_", repository.path,
            ],
        ).output.trimmingCharacters(in: .whitespacesAndNewlines)

        return ReleaseFixture(
            repository: URL(fileURLWithPath: canonicalRepositoryPath),
            releaseScript: scripts.appending(path: "release.sh"),
            environment: [
                "APPCAST_ARGUMENTS_LOG": appcastArgumentsLog.path,
                "DEVELOPER_ID_APPLICATION":
                    "Developer ID Application: Fixture (TEAMID)",
                "DITTO_BIN": tools.appending(path: "ditto").path,
                "EVENT_LOG": eventLog.path,
                "GH_ARGUMENTS_LOG": githubArgumentsLog.path,
                "GH_BIN": tools.appending(path: "gh").path,
                "GIT_BIN": tools.appending(path: "git").path,
                // The suite itself may run inside GitHub Actions; pin the
                // script under test to the local-release branch by default.
                "GITHUB_ACTIONS": "",
                "GITHUB_REPOSITORY": "",
                "NOTARYTOOL_PROFILE": "fixture-profile",
                "REMOTE_CALLS": remoteCalls.path,
                "REMOTE_TAG_OBJECT": tagObject,
                "REPOSITORY_FIXTURE_ROOT": repository.path,
                "SECURITY_BIN": tools.appending(path: "security").path,
                "SWIFT_BIN": tools.appending(path: "swift").path,
                "XCRUN_BIN": tools.appending(path: "xcrun").path,
            ],
            eventLog: eventLog,
            appcastArgumentsLog: appcastArgumentsLog,
            githubArgumentsLog: githubArgumentsLog,
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func validateAppcast(_ contents: String) throws -> ScriptResult {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true,
        )
        let appcast = temporaryRoot.appending(path: "appcast.xml")
        try Data(contents.utf8).write(to: appcast)
        return try runExecutable(
            URL(fileURLWithPath: "/bin/zsh"),
            arguments: [
                repositoryRoot.appending(
                    path: "Scripts/validate-appcast.sh",
                ).path,
                appcast.path,
                "https://github.com/obra/agentic-usage-meter/releases/download/v0.1.0/Agentic-Usage-Meter-0.1.0.zip",
                "1000",
                "0.1.0",
                "https://github.com/obra/agentic-usage-meter",
            ],
        )
    }

    private func runExecutable(
        _ executable: URL,
        arguments: [String],
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
