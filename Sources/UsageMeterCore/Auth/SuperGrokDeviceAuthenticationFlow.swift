import Foundation

public enum SuperGrokDeviceAuthenticationError:
    Error,
    Equatable,
    Sendable
{
    case executableNotFound
    case authenticationFailed
}

public struct SuperGrokAuthorizationPrompt:
    Equatable,
    Sendable
{
    public let verificationURL: URL
    public let userCode: String

    public init(
        verificationURL: URL,
        userCode: String
    ) {
        self.verificationURL = verificationURL
        self.userCode = userCode
    }
}

public struct SuperGrokDeviceAuthOutputParser:
    Sendable
{
    private var output = ""

    public init() {}

    public mutating func append(
        _ chunk: String
    ) -> SuperGrokAuthorizationPrompt? {
        output.append(chunk)
        if output.count > 16_384 {
            output = String(
                output.suffix(16_384)
            )
        }

        guard
            let url = firstMatch(
                pattern:
                    #"https://[^\s]+"#,
                in: output
            ).flatMap(URL.init(string:)),
            let code = firstMatch(
                pattern:
                    #"[A-Z0-9]{4}-[A-Z0-9]{4}"#,
                in: output
            )
        else {
            return nil
        }
        return SuperGrokAuthorizationPrompt(
            verificationURL: url,
            userCode: code
        )
    }

    private func firstMatch(
        pattern: String,
        in value: String
    ) -> String? {
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern
            ),
            let match = expression.firstMatch(
                in: value,
                range: NSRange(
                    value.startIndex...,
                    in: value
                )
            ),
            let range = Range(
                match.range,
                in: value
            )
        else {
            return nil
        }
        return String(value[range])
    }
}

public struct SuperGrokDeviceAuthenticationFlow:
    Sendable
{
    public typealias AuthorizationUpdate =
        @Sendable (
            SuperGrokAuthorizationPrompt
        ) async -> Void
    public typealias Run =
        @Sendable (
            CLIProcessInvocation,
            @escaping @Sendable (String) async
                -> Void
        ) async throws -> Int32

    private let executableURL: URL
    private let profileDirectory: URL
    private let baseEnvironment: [String: String]
    private let run: Run
    private let decoder: SuperGrokAuthDocumentDecoder

    public init(
        executableURL: URL? =
            CLIExecutableLocator().locate("grok"),
        profileDirectory: URL =
            FileManager.default.temporaryDirectory
            .appending(
                path:
                    "AgenticUsageMeter-Grok-\(UUID().uuidString)"
            ),
        baseEnvironment: [String: String] =
            ProcessInfo.processInfo.environment,
        run: @escaping Run = {
            invocation,
            onOutput in
            try await CLIProcessRunner().run(
                invocation,
                onOutput: onOutput
            )
        },
        decoder:
            SuperGrokAuthDocumentDecoder =
            SuperGrokAuthDocumentDecoder()
    ) {
        self.executableURL =
            executableURL
            ?? URL(
                fileURLWithPath:
                    "/nonexistent/grok"
            )
        self.profileDirectory =
            profileDirectory
        self.baseEnvironment =
            baseEnvironment
        self.run = run
        self.decoder = decoder
    }

    public func authenticate(
        onPrompt:
            @escaping AuthorizationUpdate
    ) async throws -> SuperGrokCredential {
        guard
            FileManager.default.isExecutableFile(
                atPath: executableURL.path
            )
        else {
            throw SuperGrokDeviceAuthenticationError
                .executableNotFound
        }

        try FileManager.default.createDirectory(
            at: profileDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: profileDirectory
            )
        }

        let invocation =
            CLIProcessInvocation.isolated(
                executableURL: executableURL,
                arguments: [
                    "login",
                    "--device-auth",
                ],
                profileDirectory:
                    profileDirectory,
                homeVariable: "GROK_HOME",
                removingEnvironmentVariables: [
                    "GROK_AUTH_FILE",
                    "GROK_ACCESS_TOKEN",
                    "XAI_API_KEY",
                ],
                baseEnvironment:
                    baseEnvironment
            )
        let outputState =
            SuperGrokOutputState()
        let status = try await run(
            invocation
        ) { chunk in
            if let prompt =
                await outputState.append(chunk)
            {
                await onPrompt(prompt)
            }
        }
        guard status == 0 else {
            throw SuperGrokDeviceAuthenticationError
                .authenticationFailed
        }

        let authFile =
            profileDirectory
            .appending(path: "auth.json")
        guard
            FileManager.default.fileExists(
                atPath: authFile.path
            )
        else {
            throw SuperGrokDeviceAuthenticationError
                .authenticationFailed
        }
        return try decoder.decode(
            Data(contentsOf: authFile)
        )
    }
}

private actor SuperGrokOutputState {
    private var parser =
        SuperGrokDeviceAuthOutputParser()
    private var deliveredPrompt: SuperGrokAuthorizationPrompt?

    func append(
        _ chunk: String
    ) -> SuperGrokAuthorizationPrompt? {
        guard
            let prompt = parser.append(chunk),
            prompt != deliveredPrompt
        else {
            return nil
        }
        deliveredPrompt = prompt
        return prompt
    }
}
