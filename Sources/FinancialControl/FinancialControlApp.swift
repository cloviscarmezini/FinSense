import SwiftUI
import AppKit

public struct MainContentView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService

    public init(store: FinancialDataStore, llmService: LocalLLMService) {
        self.store = store
        self.llmService = llmService
    }

    public var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                // App Brand Header
                HStack(spacing: 10) {
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

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Financial Control")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("macOS Native • IA Local")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                // Sidebar Menu Items
                List(selection: $store.selectedDestination) {
                    Section("Visão Geral & Fluxo") {
                        sidebarRow(.dashboard)
                        sidebarRow(.transactions)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saldo Consolidado")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(BRLFormatters.currency(store.totalConsolidatedPatrimonyNow))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(store.totalConsolidatedPatrimonyNow >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444"))
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
public struct FinancialControlApp: App {
    @StateObject private var store = FinancialDataStore()
    @StateObject private var llmService = LocalLLMService()

    public init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    public var body: some Scene {
        WindowGroup("Controle Financeiro macOS") {
            MainContentView(store: store, llmService: llmService)
                .frame(minWidth: 1120, minHeight: 740)
                .onAppear {
                    // Garante que cópias em PDF dos documentos anexos estejam disponíveis na pasta do usuário
                    _ = SampleItauStatementData.ensureSamplePDFExists(in: store.storageDirectory)
                    SampleContractDocumentsData.ensureSampleContractPDFsExist(in: store.storageDirectory)
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
