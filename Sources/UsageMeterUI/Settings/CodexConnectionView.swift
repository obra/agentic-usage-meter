import SwiftUI

public struct CodexConnectionView: View {
    private let model: CodexConnectionModel
    private let onComplete: () -> Void
    @State private var displayName: String

    public init(
        model: CodexConnectionModel,
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
            case .authenticating:
                ProgressView(
                    "Complete Codex sign-in in your browser…",
                )
            case let .confirmingIdentity(email, plan):
                saveForm(email: email, plan: plan)
            case let .duplicateIdentity(email):
                duplicateIdentityView(email: email)
            case .saving:
                ProgressView("Validating Codex usage…")
            case .complete:
                Label(
                    "Codex account connected",
                    systemImage: "checkmark.circle.fill",
                )
                .foregroundStyle(.green)
            case let .failed(message):
                ContentUnavailableView(
                    "Codex connection failed",
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
            Image(systemName: "terminal")
                .font(.system(size: 36))
            Text("Connect Codex")
                .font(.title2.weight(.semibold))
            Text(
                "A regular browser window will ask which ChatGPT subscription to authorize.",
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            Button("Open Browser") {
                Task {
                    await model.start()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func saveForm(
        email: String?,
        plan: String?,
    ) -> some View {
        Form {
            if let email {
                LabeledContent("Email", value: email)
                    .textSelection(.enabled)
            }
            if let plan {
                LabeledContent("Plan", value: plan)
            }
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

    private func duplicateIdentityView(
        email: String?,
    ) -> some View {
        ContentUnavailableView {
            Label(
                "Codex account already connected",
                systemImage: "person.crop.circle.badge.checkmark",
            )
        } description: {
            if let email {
                Text(
                    "\(email) is already present in the account list.",
                )
            } else {
                Text(
                    "This Codex subscription is already present in the account list.",
                )
            }
        }
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
