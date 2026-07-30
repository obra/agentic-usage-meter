import SwiftUI

public struct KimiConnectionView: View {
    private let model: KimiConnectionModel
    private let onComplete: () -> Void
    @State private var displayName: String

    public init(
        model: KimiConnectionModel,
        suggestedName: String,
        onComplete: @escaping () -> Void,
    ) {
        self.model = model
        self.onComplete = onComplete
        _displayName = State(initialValue: suggestedName)
    }

    public var body: some View {
        VStack(spacing: 16) {
            switch model.phase {
            case .idle:
                introduction
            case .authorizing:
                ProgressView(
                    "Requesting Kimi authorization…",
                )
            case .waitingForApproval:
                waitingView
            case .readyToSave:
                saveForm
            case .saving:
                ProgressView("Validating Kimi usage…")
            case .complete:
                Label(
                    "Kimi account connected",
                    systemImage: "checkmark.circle.fill",
                )
                .foregroundStyle(.green)
            case let .failed(message):
                ContentUnavailableView(
                    "Kimi connection failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message),
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            model.cancel()
        }
    }

    private var introduction: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.stars")
                .font(.system(size: 36))
            Text("Connect Kimi Code")
                .font(.title2.weight(.semibold))
            Text(
                "Kimi device authorization opens in your regular browser.",
            )
            .foregroundStyle(.secondary)
            Button("Open Browser") {
                Task {
                    await model.start()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var waitingView: some View {
        if let prompt = model.prompt {
            VStack(spacing: 12) {
                Text("Approve this device in Kimi")
                    .font(.headline)
                Text(prompt.userCode)
                    .font(.title.monospaced())
                    .textSelection(.enabled)
                Link(
                    "Open Kimi Authorization",
                    destination: prompt.verificationURL,
                )
                Text(
                    "Code expires \(prompt.expiresAt.formatted(.relative(presentation: .named)))",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                ProgressView()
            }
        } else {
            ProgressView("Waiting for device code…")
        }
    }

    private var saveForm: some View {
        Form {
            Text(
                "Kimi authorization succeeded. Name this subscription before saving it.",
            )
            TextField("Account name", text: $displayName)
            Button("Save Account") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                displayName.trimmingCharacters(
                    in: .whitespacesAndNewlines,
                ).isEmpty,
            )
        }
        .formStyle(.grouped)
        .frame(maxWidth: 500)
    }

    private func save() {
        Task {
            do {
                try await model.save(
                    displayName: displayName,
                )
                onComplete()
            } catch {
                return
            }
        }
    }
}
