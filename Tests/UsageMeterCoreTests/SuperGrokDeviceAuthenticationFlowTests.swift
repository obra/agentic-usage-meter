import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct SuperGrokDeviceAuthenticationFlowTests {
    @Test
    func processRunnerStreamsCommandOutput()
        async throws
    {
        let output = OutputRecorder()
        let status = try await CLIProcessRunner()
            .run(
                CLIProcessInvocation(
                    executableURL: URL(
                        fileURLWithPath:
                            "/bin/echo"
                    ),
                    arguments: ["device-ready"],
                    environment:
                        ProcessInfo.processInfo
                        .environment
                )
            ) { chunk in
                await output.append(chunk)
            }

        #expect(status == 0)
        #expect(
            await output.value
                == "device-ready\n"
        )
    }

    @Test
    func deviceAuthenticationUsesOnlyTheAttemptProfile()
        async throws
    {
        let profileDirectory =
            FileManager.default.temporaryDirectory
            .appending(
                path:
                    "supergrok-flow-\(UUID().uuidString)"
            )
        defer {
            try? FileManager.default.removeItem(
                at: profileDirectory
            )
        }
        let invocationRecorder =
            InvocationRecorder()
        let promptRecorder = PromptRecorder()
        let flow =
            SuperGrokDeviceAuthenticationFlow(
                executableURL: URL(
                    fileURLWithPath:
                        "/usr/bin/true"
                ),
                profileDirectory:
                    profileDirectory,
                baseEnvironment: [
                    "PATH": "/usr/local/bin:/usr/bin",
                    "GROK_HOME": "/Users/test/.grok",
                    "GROK_AUTH_FILE":
                        "/Users/test/default.json",
                    "GROK_ACCESS_TOKEN":
                        "default-token",
                    "XAI_API_KEY": "default-api-key",
                ],
                run: {
                    invocation,
                    onOutput in
                    await invocationRecorder.record(
                        invocation
                    )
                    try FileManager.default
                        .createDirectory(
                            at: profileDirectory,
                            withIntermediateDirectories:
                                true
                        )
                    try Data(
                        """
                        {
                          "https://auth.x.ai::profile": {
                            "key": "isolated-token",
                            "email": "user@example.com",
                            "user_id": "user-1",
                            "team_id": "team-1",
                            "auth_mode": "oidc"
                          }
                        }
                        """.utf8
                    ).write(
                        to:
                            profileDirectory
                            .appending(
                                path: "auth.json"
                            )
                    )
                    await onOutput(
                        """
                        To sign in, open this URL in your browser:
                          https://auth.x.ai/device
                        Confirm this code in your browser:
                          ABCD-EFGH
                        """
                    )
                    return 0
                }
            )

        let credential =
            try await flow
            .authenticate { prompt in
                await promptRecorder.record(
                    prompt
                )
            }

        #expect(
            credential.accessToken
                == "isolated-token"
        )
        let invocation = try #require(
            await invocationRecorder.invocation
        )
        #expect(
            invocation.executableURL.path
                == "/usr/bin/true"
        )
        #expect(
            invocation.arguments
                == ["login", "--device-auth"]
        )
        #expect(
            invocation.environment["GROK_HOME"]
                == profileDirectory.path
        )
        #expect(
            invocation.environment["PATH"]
                == "/usr/local/bin:/usr/bin"
        )
        #expect(
            invocation.environment[
                "GROK_AUTH_FILE"
            ] == nil
        )
        #expect(
            invocation.environment[
                "GROK_ACCESS_TOKEN"
            ] == nil
        )
        #expect(
            invocation.environment[
                "XAI_API_KEY"
            ] == nil
        )
        let prompt = try #require(
            await promptRecorder.prompt
        )
        #expect(
            prompt.verificationURL
                == URL(
                    string:
                        "https://auth.x.ai/device"
                )
        )
        #expect(prompt.userCode == "ABCD-EFGH")
    }

    @Test
    func promptCanArriveAcrossOutputChunks()
        async throws
    {
        var parser =
            SuperGrokDeviceAuthOutputParser()

        #expect(
            parser.append(
                "To sign in, open this URL in your browser:\n  https://auth.x.ai/"
            ) == nil
        )
        let parsedPrompt = parser.append(
            "device\nConfirm this code in your browser:\n  ABCD-EFGH\n"
        )
        let prompt = try #require(
            parsedPrompt
        )

        #expect(
            prompt.verificationURL
                == URL(
                    string:
                        "https://auth.x.ai/device"
                )
        )
        #expect(prompt.userCode == "ABCD-EFGH")
    }
}

private actor InvocationRecorder {
    private(set) var invocation: CLIProcessInvocation?

    func record(
        _ invocation: CLIProcessInvocation
    ) {
        self.invocation = invocation
    }
}

private actor PromptRecorder {
    private(set) var prompt: SuperGrokAuthorizationPrompt?

    func record(
        _ prompt: SuperGrokAuthorizationPrompt
    ) {
        self.prompt = prompt
    }
}

private actor OutputRecorder {
    private(set) var value = ""

    func append(_ chunk: String) {
        value.append(chunk)
    }
}
