import Foundation

public struct CLIProcessInvocation:
    Equatable,
    Sendable
{
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]

    public init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
    }

    public static func isolated(
        executableURL: URL,
        arguments: [String],
        profileDirectory: URL,
        homeVariable: String,
        removingEnvironmentVariables: Set<String>,
        baseEnvironment: [String: String]
    ) -> CLIProcessInvocation {
        var environment = baseEnvironment
        for variable in removingEnvironmentVariables {
            environment[variable] = nil
        }
        environment[homeVariable] =
            profileDirectory.path
        return CLIProcessInvocation(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment
        )
    }
}

public enum CLIProcessRunnerError:
    Error,
    Equatable,
    Sendable
{
    case executableNotFound(String)
}

public struct CLIProcessRunner: Sendable {
    public init() {}

    public func run(
        _ invocation: CLIProcessInvocation,
        onOutput:
            @escaping @Sendable (String) async
            -> Void
    ) async throws -> Int32 {
        let process = Process()
        let output = Pipe()
        process.executableURL =
            invocation.executableURL
        process.arguments = invocation.arguments
        process.environment =
            invocation.environment
        process.standardOutput = output
        process.standardError = output

        try process.run()
        output.fileHandleForWriting.closeFile()

        for try await line in output.fileHandleForReading.bytes.lines {
            await onOutput(line + "\n")
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

public struct CLIExecutableLocator: Sendable {
    public init() {}

    public func locate(
        _ executable: String,
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) -> URL? {
        var directories =
            environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        if let home = environment["HOME"] {
            directories.append(
                "\(home)/.local/bin"
            )
        }
        directories.append(
            contentsOf: [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
            ]
        )

        for directory in directories {
            let candidate = URL(
                fileURLWithPath: directory
            ).appending(path: executable)
            if FileManager.default
                .isExecutableFile(
                    atPath: candidate.path
                )
            {
                return candidate
            }
        }
        return nil
    }
}
