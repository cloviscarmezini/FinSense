import SwiftUI
import AppKit

public struct MainContentView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService
    @ObservedObject public var syncService: CloudSyncService
    @AppStorage("is_patrimony_hidden") private var isPatrimonyHidden: Bool = false

    public init(store: FinancialDataStore, llmService: LocalLLMService, syncService: CloudSyncService) {
        self.store = store
        self.llmService = llmService
        self.syncService = syncService
    }

    public var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                // App Brand Header
                HStack(spacing: 10) {
                    if let appIcon = FinSenseApp.loadAppIcon() {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#EC7000"), Color(hex: "#6366F1")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 34, height: 34)
                            Image(systemName: "brazilianrealsign.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("FinSense")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            if store.persistenceEnvironment.isDebug {
                                Text(store.persistenceEnvironment.badgeTitle)
                                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color(hex: "#F59E0B").opacity(0.18)))
                                    .foregroundStyle(Color(hex: "#F59E0B"))
                                    .help("Ambiente de Desenvolvimento isolado: \(store.databaseFileURL.path)")
                            }
                            SyncStatusIndicatorView(syncService: syncService)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                // Sidebar Menu Items
                List(selection: $store.selectedDestination) {
                    Section("Visão Geral & Fluxo") {
                        sidebarRow(.dashboard)

                        Button {
                            store.selectedDestination = .transactions
                            store.selectedTransactionsSubmenu = .all
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: SidebarDestination.transactions.icon)
                                    .foregroundStyle(
                                        store.selectedDestination == .transactions && store.selectedTransactionsSubmenu == .all
                                            ? Color.accentColor
                                            : .primary
                                    )
                                Text(SidebarDestination.transactions.title)
                                    .font(.system(size: 13.5, weight: .medium))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tag(SidebarDestination.transactions)

                        ForEach([TransactionsSubmenu.expenses, TransactionsSubmenu.incomes]) { sub in
                            Button {
                                store.selectedDestination = .transactions
                                store.selectedTransactionsSubmenu = sub
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: sub.icon)
                                        .font(.caption)
                                        .foregroundStyle(
                                            store.selectedDestination == .transactions && store.selectedTransactionsSubmenu == sub
                                                ? (sub == .expenses ? Color(hex: "#EF4444") : Color(hex: "#10B981"))
                                                : .secondary
                                        )
                                        .frame(width: 18)
                                    Text(sub.title)
                                        .font(.caption)
                                        .fontWeight(
                                            store.selectedDestination == .transactions && store.selectedTransactionsSubmenu == sub
                                                ? .semibold
                                                : .regular
                                        )
                                        .foregroundStyle(
                                            store.selectedDestination == .transactions && store.selectedTransactionsSubmenu == sub
                                                ? Color.primary
                                                : .secondary
                                        )
                                    Spacer()
                                }
                                .padding(.leading, 18)
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        sidebarRow(.investments)
                    }

                    Section("Passivos & Contratos") {
                        sidebarRow(.loans)
                        sidebarRow(.financings)
                        sidebarRow(.debts)
                    }

                    Section("Configurações") {
                        sidebarRow(.settings)

                        ForEach(SettingsSection.allCases) { sec in
                            Button {
                                store.selectedDestination = .settings
                                store.selectedSettingsSection = sec
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: sec.icon)
                                        .font(.caption)
                                        .foregroundStyle(
                                            store.selectedDestination == .settings && store.selectedSettingsSection == sec
                                                ? Color.accentColor
                                                : .secondary
                                        )
                                        .frame(width: 18)
                                    Text(sec.title)
                                        .font(.caption)
                                        .foregroundStyle(
                                            store.selectedDestination == .settings && store.selectedSettingsSection == sec
                                                ? Color.primary
                                                : .secondary
                                        )
                                    Spacer()
                                }
                                .padding(.leading, 18)
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                // Bottom Consolidated Status & Quick AI Chat Button
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Saldo Consolidado")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if isPatrimonyHidden {
                                Text("Oculto")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(BRLFormatters.currency(store.totalConsolidatedPatrimonyNow))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(store.totalConsolidatedPatrimonyNow >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444"))
                                    .monospacedDigit()
                            }
                        }
                        Spacer()
                        Button {
                            isPatrimonyHidden.toggle()
                        } label: {
                            Image(systemName: isPatrimonyHidden ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isPatrimonyHidden ? "Exibir valores de patrimônio" : "Ocultar valores de patrimônio (privacidade)")
                    }

                    Button {
                        store.openAIChat()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles.bubble.fill")
                            Text("Abrir Chat IA Local")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#6366F1"), Color(hex: "#8B5CF6")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if store.persistenceEnvironment.isDebug {
                        HStack(spacing: 4) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 9))
                            Text("\(store.persistenceEnvironment.badgeTitle) • \(store.databaseFileURL.lastPathComponent)")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color(hex: "#F59E0B"))
                        .help("Banco de desenvolvimento isolado em: \(store.databaseFileURL.path)")
                    }
                }
                .padding(14)
            }
            .navigationSplitViewColumnWidth(min: 235, ideal: 250, max: 290)
        } detail: {
            Group {
                switch store.selectedDestination {
                case .dashboard:
                    DashboardView(store: store, llmService: llmService)
                case .transactions:
                    TransactionsView(store: store, llmService: llmService)
                case .investments:
                    InvestmentsView(store: store)
                case .loans:
                    LoansAndFinancingsView(store: store, llmService: llmService, kind: .loan)
                case .financings:
                    LoansAndFinancingsView(store: store, llmService: llmService, kind: .financing)
                case .debts:
                    DebtsView(store: store, llmService: llmService)
                case .settings:
                    SettingsView(store: store, llmService: llmService)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SyncStatusIndicatorView(syncService: syncService)
                }
            }
        }
        .sheet(isPresented: $store.isAIChatPresented) {
            AIChatSheetView(store: store, llmService: llmService)
        }
        .sheet(isPresented: $store.isLLMInstallAlertPresented) {
            LLMInstallRequiredSheet(store: store, llmService: llmService)
        }
    }

    @ViewBuilder
    private func sidebarRow(_ destination: SidebarDestination) -> some View {
        NavigationLink(value: destination) {
            Label {
                Text(destination.title)
                    .font(.system(size: 13.5, weight: .medium))
            } icon: {
                Image(systemName: destination.icon)
            }
        }
    }
}

@main
public struct FinSenseApp: App {
    @StateObject private var store: FinancialDataStore
    @StateObject private var syncService: CloudSyncService
    @StateObject private var llmService = LocalLLMService()

    public init() {
        NSApplication.shared.setActivationPolicy(.regular)
        Self.configureApplicationIcon()

        let storeInstance = FinancialDataStore()
        let syncInstance = CloudSyncService(store: storeInstance)
        storeInstance.cloudSyncService = syncInstance

        _store = StateObject(wrappedValue: storeInstance)
        _syncService = StateObject(wrappedValue: syncInstance)
    }

    public static func configureApplicationIcon() {
        if let iconImage = loadAppIcon() {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }

    public static func loadAppIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        let fallbackPath = "Sources/FinSense/Resources/AppIcon.png"
        if FileManager.default.fileExists(atPath: fallbackPath),
           let img = NSImage(contentsOfFile: fallbackPath) {
            return img
        }
        return nil
    }

    public var body: some Scene {
        WindowGroup(PersistenceEnvironment.current.isDebug ? "FinSense [DEBUG DB]" : "FinSense") {
            MainContentView(store: store, llmService: llmService, syncService: syncService)
                .frame(minWidth: 1120, minHeight: 740)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Financeiro") {
                Button("Ir para Dashboard") {
                    store.selectedDestination = .dashboard
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Ir para Transações") {
                    store.selectedDestination = .transactions
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("Ir para Investimentos") {
                    store.selectedDestination = .investments
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("Ir para Empréstimos") {
                    store.selectedDestination = .loans
                }
                .keyboardShortcut("4", modifiers: [.command])

                Button("Ir para Financiamentos") {
                    store.selectedDestination = .financings
                }
                .keyboardShortcut("5", modifiers: [.command])

                Button("Ir para Dívidas") {
                    store.selectedDestination = .debts
                }
                .keyboardShortcut("6", modifiers: [.command])

                Divider()

                Button("Abrir Chat com IA Local") {
                    store.openAIChat()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}
