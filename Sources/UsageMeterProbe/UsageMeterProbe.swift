import Darwin
import Foundation
import UsageMeterCore

@main
enum UsageMeterProbe {
    static func main() {
        guard
            CommandLine.arguments.count == 2,
            let provider = Provider(rawValue: CommandLine.arguments[1])
        else {
            writeError("usage: UsageMeterProbe <claude|codex|kimi>")
            Darwin.exit(EX_USAGE)
        }

        writeError(
            "\(provider.rawValue) qualification is not implemented in this build."
        )
        Darwin.exit(EX_UNAVAILABLE)
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
