import AppKit
import Darwin
import Foundation
import SwiftUI
import UsageMeterClaudeWeb

@main
@MainActor
enum ClaudeWebProbe {
    static func main() async {
        do {
            let command = try ClaudeWebProbeCommand.parse(
                arguments: CommandLine.arguments
            )
            switch command {
            case let .login(profileID):
                runLogin(profileID: profileID)
            case let .delete(profileID):
                try await ClaudeWebProfileStore.remove(profileID: profileID)
            }
        } catch ClaudeWebProbeCommandError.invalidArguments {
            writeError(
                "usage: ClaudeWebProbe <login|delete> <profile-uuid>"
            )
            Darwin.exit(EX_USAGE)
        } catch {
            writeError("Claude web profile operation failed")
            Darwin.exit(EX_UNAVAILABLE)
        }
    }

    private static func runLogin(profileID: UUID) {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)

        let model = ClaudeWebProbeModel(profileID: profileID) { output in
            do {
                try write(output: output)
                application.terminate(nil)
            } catch {
                writeError("could not encode normalized usage")
                Darwin.exit(EX_SOFTWARE)
            }
        }
        let controller = ClaudeWebProbeWindowController(model: model)
        controller.showWindow(nil)
        application.activate(ignoringOtherApps: true)
        model.start()
        application.run()
        withExtendedLifetime(controller) {}
    }

    private static func write(output: ClaudeWebProbeOutput) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(output))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}

@MainActor
private final class ClaudeWebProbeWindowController:
    NSWindowController,
    NSWindowDelegate
{
    private let model: ClaudeWebProbeModel
    private var isClosing = false

    init(model: ClaudeWebProbeModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Account Qualification"
        window.contentMinSize = NSSize(width: 440, height: 560)
        window.contentView = NSHostingView(
            rootView: ClaudeWebProbeView(model: model)
        )
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isClosing else {
            return false
        }
        isClosing = true
        Task { @MainActor in
            await model.cancel()
            NSApplication.shared.terminate(nil)
        }
        return false
    }
}
