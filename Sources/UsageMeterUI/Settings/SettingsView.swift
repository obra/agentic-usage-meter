import Foundation
import SwiftUI
import UsageMeterCore

enum AccountSheetRoute: Identifiable {
    case add
    case reconnect(SubscriptionAccount)

    var id: String {
        switch self {
        case .add:
            "add"
        case let .reconnect(account):
            "reconnect-\(account.id.uuidString)"
        }
    }

    var provider: Provider {
        switch self {
        case .add:
            .claude
        case let .reconnect(account):
            account.provider
        }
    }

    var reconnectingAccount: SubscriptionAccount? {
        guard case let .reconnect(account) = self else {
            return nil
        }
        return account
    }

    var isProviderLocked: Bool {
        reconnectingAccount != nil
    }

    var providerRequestURL: URL? {
        guard case .add = self else {
            return nil
        }
        return URL(
            string:
                "https://github.com/obra/agentic-usage-meter/issues/new",
        )
    }
}

struct AccountConnectionWizard {
    enum Step: Equatable {
        case chooseProvider
        case connect(Provider)
    }

    private(set) var step: Step
    private let isLocked: Bool

    init(route: AccountSheetRoute) {
        isLocked = route.isProviderLocked
        step = route.isProviderLocked
            ? .connect(route.provider)
            : .chooseProvider
    }

    var canGoBack: Bool {
        !isLocked && step != .chooseProvider
    }

    mutating func choose(_ provider: Provider) {
        guard !isLocked else {
            return
        }
        step = .connect(provider)
    }

    mutating func goBack() {
        guard canGoBack else {
            return
        }
        step = .chooseProvider
    }
}

struct ProviderPresentation {
    let title: String
    let detail: String
    let systemImage: String

    init(_ provider: Provider) {
        guard
            let definition = ProviderCatalog.live.definition(
                for: provider,
            )
        else {
            preconditionFailure(
                "Provider is missing from the catalog.",
            )
        }
        title = definition.displayName
        detail = definition.connectionDetail
        systemImage = definition.systemImage
    }
}

struct SettingsHeaderPresentation {
    let sampleDataLabel: String?

    init(isSampleData: Bool) {
        sampleDataLabel = isSampleData
            ? "SAMPLE DATA"
            : nil
    }
}

struct AccountConnectionFormState {
    struct ViewID: Hashable {
        let attemptID: UUID
        let reconnectingAccountID: UUID?
    }

    private(set) var attemptID: UUID

    init(attemptID: UUID = UUID()) {
        self.attemptID = attemptID
    }

    mutating func accountDidConnect(
        nextAttemptID: UUID = UUID(),
    ) {
        attemptID = nextAttemptID
    }

    func viewID(
        reconnectingAccountID: UUID?,
    ) -> ViewID {
        ViewID(
            attemptID: attemptID,
            reconnectingAccountID:
            reconnectingAccountID,
        )
    }
}

struct AccountManagementPresentation {
    var sheetRoute: AccountSheetRoute?
    private(set) var connectionForm:
        AccountConnectionFormState

    init(
        sheetRoute: AccountSheetRoute? = nil,
        connectionForm: AccountConnectionFormState =
            AccountConnectionFormState(),
    ) {
        self.sheetRoute = sheetRoute
        self.connectionForm = connectionForm
    }

    var connectionViewID:
        AccountConnectionFormState.ViewID
    {
        connectionForm.viewID(
            reconnectingAccountID:
            sheetRoute?.reconnectingAccount?.id,
        )
    }

    mutating func presentAddAccount() {
        sheetRoute = .add
    }

    mutating func presentReconnect(
        _ account: SubscriptionAccount,
    ) {
        sheetRoute = .reconnect(account)
    }

    mutating func dismissSheet() {
        sheetRoute = nil
    }

    mutating func connectionDidComplete(
        nextAttemptID: UUID = UUID(),
    ) {
        connectionForm.accountDidConnect(
            nextAttemptID: nextAttemptID,
        )
        dismissSheet()
    }
}

public struct SettingsView: View {
    private let model: AppModel
    private let windowActivation:
        SettingsWindowActivation
    private let dashboardPresenter:
        AccountDashboardPresenter
    @State private var presentation =
        AccountManagementPresentation()

    public init(model: AppModel) {
        self.model = model
        windowActivation = .shared
        dashboardPresenter = .shared
    }

    public var body: some View {
        AccountListView(
            model: model,
            onAdd: {
                presentation.presentAddAccount()
            },
            onReconnect: { account in
                presentation.presentReconnect(account)
            },
            onOpenDashboard: { state in
                dashboardPresenter.open(state)
            },
        )
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Text("Accounts")
                        .font(.headline)
                    if let sampleDataLabel =
                        SettingsHeaderPresentation(
                            isSampleData: model.isSampleData,
                        ).sampleDataLabel
                    {
                        SampleDataBadge(label: sampleDataLabel)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentation.presentAddAccount()
                } label: {
                    Label(
                        "Add Account",
                        systemImage: "plus",
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(item: $presentation.sheetRoute) { route in
            AddAccountView(
                model: model,
                route: route,
                onComplete: {
                    presentation.connectionDidComplete()
                },
            )
            .id(
                presentation.connectionViewID,
            )
        }
        .frame(minWidth: 680, minHeight: 560)
        .onAppear {
            windowActivation.settingsDidAppear()
        }
        .onDisappear {
            windowActivation.settingsDidDisappear()
        }
    }
}

private struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss

    let model: AppModel
    let route: AccountSheetRoute
    let onComplete: () -> Void

    @State private var wizard: AccountConnectionWizard
    @State private var claude: ClaudeConnectionModel
    @State private var codex: CodexConnectionModel
    @State private var kimi: KimiConnectionModel
    @State private var githubCopilot:
        GitHubCopilotConnectionModel
    @State private var superGrok:
        SuperGrokConnectionModel
    @State private var openCodeGo:
        OpenCodeConnectionModel
    @State private var openCodeZen:
        OpenCodeConnectionModel
    @State private var mimo: MiMoConnectionModel

    init(
        model: AppModel,
        route: AccountSheetRoute,
        onComplete: @escaping () -> Void,
    ) {
        self.model = model
        self.route = route
        self.onComplete = onComplete

        let provider = route.provider
        let reconnectingAccount =
            route.reconnectingAccount
        _wizard = State(
            initialValue: AccountConnectionWizard(
                route: route,
            ),
        )
        _claude = State(
            initialValue: ClaudeConnectionModel(
                appModel: model,
                reconnectingAccount:
                provider == .claude
                    ? reconnectingAccount
                    : nil,
            ),
        )
        _codex = State(
            initialValue: CodexConnectionModel(
                appModel: model,
                reconnectingAccount:
                provider == .codex
                    ? reconnectingAccount
                    : nil,
            ),
        )
        _kimi = State(
            initialValue: KimiConnectionModel.live(
                appModel: model,
                reconnectingAccount:
                provider == .kimi
                    ? reconnectingAccount
                    : nil,
            ),
        )
        _githubCopilot = State(
            initialValue:
                GitHubCopilotConnectionModel(
                    appModel: model,
                    reconnectingAccount:
                        provider == .githubCopilot
                            ? reconnectingAccount
                            : nil
                )
        )
        _superGrok = State(
            initialValue:
                SuperGrokConnectionModel(
                    appModel: model,
                    reconnectingAccount:
                        provider == .superGrok
                            ? reconnectingAccount
                            : nil
                )
        )
        _openCodeGo = State(
            initialValue:
                OpenCodeConnectionModel(
                    provider: .openCodeGo,
                    appModel: model,
                    reconnectingAccount:
                        provider == .openCodeGo
                            ? reconnectingAccount
                            : nil
                )
        )
        _openCodeZen = State(
            initialValue:
                OpenCodeConnectionModel(
                    provider: .openCodeZen,
                    appModel: model,
                    reconnectingAccount:
                        provider == .openCodeZen
                            ? reconnectingAccount
                            : nil
                )
        )
        _mimo = State(
            initialValue:
                MiMoConnectionModel(
                    appModel: model,
                    reconnectingAccount:
                        provider == .mimo
                            ? reconnectingAccount
                            : nil
                )
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sheetTitle)
                        .font(.title2.weight(.semibold))
                    Text(sheetDetail)
                        .foregroundStyle(.secondary)
                }

                switch wizard.step {
                case .chooseProvider:
                    providerSelector
                    Spacer(minLength: 0)
                case let .connect(provider):
                    connectionView(for: provider)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                        )
                }
            }
            .padding(24)
            .toolbar {
                if wizard.canGoBack {
                    ToolbarItem(placement: .navigation) {
                        Button("Back") {
                            wizard.goBack()
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 620)
    }

    @ViewBuilder
    private func connectionView(
        for provider: Provider,
    ) -> some View {
        switch provider {
        case .claude:
            ClaudeConnectionView(
                model: claude,
                suggestedName:
                route.reconnectingAccount?
                    .displayName
                    ?? "Claude",
                onComplete: complete,
            )
        case .codex:
            CodexConnectionView(
                model: codex,
                suggestedName:
                route.reconnectingAccount?
                    .displayName
                    ?? "Codex",
                onComplete: complete,
            )
        case .kimi:
            KimiConnectionView(
                model: kimi,
                suggestedName:
                route.reconnectingAccount?
                    .displayName
                    ?? "Kimi",
                onComplete: complete,
            )
        case .minimax:
            APIKeyConnectionView(
                model: model,
                provider: .minimax,
                reconnectingAccount:
                    route.reconnectingAccount,
                suggestedName:
                    route.reconnectingAccount?
                        .displayName
                        ?? "MiniMax",
                onComplete: complete
            )
        case .factory:
            APIKeyConnectionView(
                model: model,
                provider: .factory,
                reconnectingAccount:
                    route.reconnectingAccount,
                suggestedName:
                    route.reconnectingAccount?
                        .displayName
                        ?? "Factory",
                onComplete: complete
            )
        case .githubCopilot:
            GitHubCopilotConnectionView(
                model: githubCopilot,
                suggestedName:
                    route
                        .reconnectingAccount?
                        .displayName
                    ?? "GitHub Copilot",
                onComplete: complete
            )
        case .superGrok:
            SuperGrokConnectionView(
                model: superGrok,
                suggestedName:
                    route
                        .reconnectingAccount?
                        .displayName
                    ?? "SuperGrok",
                onComplete: complete
            )
        case .openCodeGo:
            OpenCodeConnectionView(
                provider: .openCodeGo,
                model: openCodeGo,
                suggestedName:
                    route
                        .reconnectingAccount?
                        .displayName
                    ?? "OpenCode Go",
                onComplete: complete
            )
        case .openCodeZen:
            OpenCodeConnectionView(
                provider: .openCodeZen,
                model: openCodeZen,
                suggestedName:
                    route
                        .reconnectingAccount?
                        .displayName
                    ?? "OpenCode Zen",
                onComplete: complete
            )
        case .zai:
            APIKeyConnectionView(
                model: model,
                provider: .zai,
                reconnectingAccount:
                    route.reconnectingAccount,
                suggestedName:
                    route.reconnectingAccount?
                        .displayName
                        ?? "Z.ai",
                onComplete: complete
            )
        case .mimo:
            MiMoConnectionView(
                model: mimo,
                suggestedName:
                    route
                        .reconnectingAccount?
                        .displayName
                    ?? "MiMo",
                onComplete: complete
            )
        case .antigravity:
            EmptyView()
        }
    }

    private func complete() {
        onComplete()
        dismiss()
    }

    private var sheetTitle: String {
        if let account = route.reconnectingAccount {
            return "Reconnect \(account.displayName)"
        }
        if case let .connect(provider) = wizard.step {
            return "Connect \(ProviderPresentation(provider).title)"
        }
        return "Add an account"
    }

    private var sheetDetail: String {
        if route.isProviderLocked {
            return
                "Sign in again to restore usage updates for this account."
        }
        if case let .connect(provider) = wizard.step {
            return ProviderPresentation(provider).detail
        }
        return
            "Choose the subscription provider you want to track."
    }

    @ViewBuilder
    private var providerSelector: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: 190,
                            maximum: 280
                        ),
                        spacing: 12
                    )
                ],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(
                    ProviderCatalog.live.connectableDefinitions(),
                ) { definition in
                    providerCard(
                        definition.provider,
                        action: {
                            wizard.choose(
                                definition.provider,
                            )
                        },
                    )
                }
            }

            if let providerRequestURL = route.providerRequestURL {
                Link(
                    "Want a provider that's not shown here? please request it.",
                    destination: providerRequestURL,
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func providerCard(
        _ provider: Provider,
        action: @escaping () -> Void,
    ) -> some View {
        let presentation = ProviderPresentation(provider)
        return Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: presentation.systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .fontWeight(.semibold)
                    Text(presentation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(
                maxWidth: .infinity,
                minHeight: 76,
                alignment: .leading,
            )
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        Color.secondary.opacity(0.22),
                        lineWidth: 1,
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(presentation.title), \(presentation.detail)",
        )
    }
}
