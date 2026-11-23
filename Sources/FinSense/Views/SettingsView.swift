import SwiftUI
import UniformTypeIdentifiers

public struct SettingsView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService

    public init(store: FinancialDataStore, llmService: LocalLLMService) {
        self.store = store
        self.llmService = llmService
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header + Section Tabs
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Configurações do Sistema")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Configure o Apple Intelligence, modo Pensando, contas bancárias, sincronização em nuvem e categorias")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Seção", selection: $store.selectedSettingsSection) {
                    ForEach(SettingsSection.allCases) { sec in
                        Label(sec.title, systemImage: sec.icon).tag(sec)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 580)
            }

            Divider()

            switch store.selectedSettingsSection {
            case .general:
                GeneralSettingsSectionView(store: store)
            case .llm:
                LLMConfigurationSectionView(store: store, llmService: llmService)
            case .accounts:
                AccountsManagementSectionView(store: store)
            case .categories:
                CategoriesManagementSectionView(store: store)
            }
        }
        .padding(24)
    }
}

// MARK: - Painel Reativo de Sincronização em Nuvem (Observador Direto de CloudSyncService)

public struct CloudSyncSettingsCardView: View {
    @ObservedObject public var sync: CloudSyncService
    @ObservedObject public var store: FinancialDataStore

    public init(sync: CloudSyncService, store: FinancialDataStore) {
        self.sync = sync
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Ativar Sincronização em Nuvem", isOn: Binding(
                get: { sync.isEnabled },
                set: { newValue in
                    sync.isEnabled = newValue
                    if newValue {
                        if sync.isAutoSyncEnabled {
                            sync.performSync()
                        }
                    } else {
                        sync.syncStatus = .disabled
                    }
                }
            ))
            .font(.system(size: 14, weight: .semibold))

            Text("Quando ativado, os dados podem ser sincronizados bidirecionalmente com o seu servidor na nuvem.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Opções avançadas de sync (APENAS se ativado)
            if sync.isEnabled {
                Toggle("Sincronizar automaticamente", isOn: $sync.isAutoSyncEnabled)
                    .font(.system(size: 13, weight: .semibold))

                Text("Quando habilitada, as alterações salvas são sincronizadas em segundo plano automaticamente. Quando desabilitada, só sincroniza manualmente ao clicar em um dos botões de sincronizar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Configurações do Servidor")
                        .font(.subheadline.bold())

                    HStack(spacing: 12) {
                        Text("URL da API:")
                            .font(.caption.bold())
                            .frame(width: 80, alignment: .leading)
                        TextField("URL da API Backend", text: Binding(
                            get: { sync.baseURLString },
                            set: { sync.baseURLString = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }

                    HStack(spacing: 12) {
                        Text("Client ID:")
                            .font(.caption.bold())
                            .frame(width: 80, alignment: .leading)
                        Text(sync.clientId)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Text("Status:")
                            .font(.caption.bold())
                            .frame(width: 80, alignment: .leading)

                        if sync.isSyncing {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                                    .foregroundStyle(Color(hex: "#F59E0B"))

                                Text("Sincronizando \(Int(round(sync.syncProgress * 100)))%")
                                    .font(.caption)
                                    .fontWeight(.medium)

                                ProgressView(value: max(0.05, sync.syncProgress), total: 1.0)
                                    .progressViewStyle(.linear)
                                    .frame(width: 140)
                                    .animation(.easeInOut(duration: 0.25), value: sync.syncProgress)
                            }
                        } else if let last = sync.lastSyncDate, case .synced = sync.syncStatus {
                            HStack(spacing: 6) {
                                Image(systemName: sync.syncStatus.iconSymbol)
                                    .foregroundStyle(Color(hex: "#10B981"))
                                Text("Sincronizado em \(BRLFormatters.dateTime(last))")
                                    .font(.caption)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: sync.syncStatus.iconSymbol)
                                    .foregroundStyle(iconColor(for: sync.syncStatus))
                                Text(sync.syncStatus.statusDescription)
                                    .font(.caption)
                            }
                        }

                        Spacer()
                    }

                    Divider()

                    HStack(spacing: 12) {
                        Button {
                            sync.performSync()
                        } label: {
                            Label("Sincronizar Agora", systemImage: "arrow.clockwise")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(sync.isSyncing || sync.isSeeding || !sync.canSync)

                        Spacer()
                    }

                    if sync.isSeeding {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: sync.seedProgress, total: 1.0)
                                .progressViewStyle(.linear)
                            Text(sync.seedStatusText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func iconColor(for status: SyncStatus) -> Color {
        switch status {
        case .disabled: return .secondary.opacity(0.6)
        case .synced: return Color(hex: "#10B981")
        case .syncing: return Color(hex: "#F59E0B")
        case .remoteUpdatesAvailable: return Color(hex: "#0EA5E9")
        case .outOfSync: return Color(hex: "#F59E0B")
        case .authError: return Color(hex: "#EF4444")
        }
    }
}

// MARK: - 0. Configurações Gerais ("Recomeçar do zero")

public struct GeneralSettingsSectionView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject private var authService = AuthService.shared
    @State private var showAuthSheet: Bool = false
    @State private var authMode: AuthSheetMode = .login
    @State private var showResetFromScratchSheet: Bool = false
    @State private var lastResetBanner: String? = nil

    // Exportação Completa (Exceto Modelos de IA)
    @State private var isExportingDatabase: Bool = false
    @State private var exportProgressValue: Double = 0.0
    @State private var exportStatusBanner: String? = nil
    @State private var exportIsError: Bool = false

    // Importação Seletiva e Validada com Barra de Loading
    @State private var isPreparingImportFile: Bool = false
    @State private var preparedImportPackage: PreparedDatabaseImportPackage? = nil
    @State private var importedFileName: String = ""
    @State private var showDatabaseImportSelectionSheet: Bool = false
    @State private var importedDraftsForReview: [ImportableExpenseDraft] = []
    @State private var showExpenseImportReviewSheet: Bool = false
    @State private var importStatusBanner: String? = nil
    @State private var importIsError: Bool = false

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Card 0: Autenticação & Conta (FinSense Cloud)
                if !authService.isAuthenticated {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(hex: "#0284C7").opacity(0.14))
                                    .frame(width: 46, height: 46)
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(Color(hex: "#0284C7"))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Conta FinSense")
                                    .font(.title3.bold())
                                Text("Conecte-se para sincronizar seus dados financeiros entre seus dispositivos com segurança. Sem login, o app continua operando 100% no modo local.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            HStack(spacing: 10) {
                                Button {
                                    authMode = .login
                                    showAuthSheet = true
                                } label: {
                                    Text("Entrar na Conta")
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 6)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(hex: "#0284C7"))

                                Button {
                                    authMode = .register
                                    showAuthSheet = true
                                } label: {
                                    Text("Criar Nova Conta")
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 6)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                } else {
                    // Perfil Conectado & Sincronização em Nuvem (Visível quando Autenticado)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(hex: "#10B981").opacity(0.14))
                                    .frame(width: 46, height: 46)
                                Image(systemName: "person.crop.circle.fill.badge.checkmark")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(Color(hex: "#10B981"))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(authService.currentUser?.fullName ?? "Usuário FinSense")
                                        .font(.title3.bold())
                                    Text("Conectado")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color(hex: "#10B981").opacity(0.18)))
                                        .foregroundStyle(Color(hex: "#10B981"))
                                }
                                Text(authService.currentUser?.email ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                authService.logout()
                                store.cloudSyncService?.resetSyncState()
                                store.cloudSyncService?.syncStatus = .disabled
                            } label: {
                                Text("Sair da Conta")
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.bordered)
                            .foregroundStyle(.red)
                        }

                        Divider()

                        // Painel Reativo de Sincronização em Nuvem
                        if let sync = store.cloudSyncService {
                            CloudSyncSettingsCardView(sync: sync, store: store)
                        }
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                }

                // Card 1: Exportação Completa da Base de Dados (Exceto Modelos de IA)
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: "#6366F1").opacity(0.14))
                                .frame(width: 46, height: 46)
                            Image(systemName: "externaldrive.badge.timemachine")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Color(hex: "#6366F1"))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Exportação Completa da Base de Dados")
                                .font(.title3.bold())
                            Text("Exporta automaticamente 100% dos seus dados financeiros (Categorias, Contas, Cartões de Crédito e Faturas, Transações, Investimentos, Empréstimos, Financiamentos, Dívidas, Previsões/Cotas e Assets/Anexos) em pacote otimizado e comprimido, excluindo apenas os modelos de IA baixados.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            exportFullDatabaseBackup()
                        } label: {
                            Label(
                                isExportingDatabase ? "Exportando Base..." : "Exportar Base Completa",
                                systemImage: "square.and.arrow.up.fill"
                            )
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#6366F1"))
                        .disabled(isExportingDatabase)
                    }

                    if isExportingDatabase {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Empacotando e comprimindo registros e assets (excluindo modelos de IA)...")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(hex: "#6366F1"))
                                Spacer()
                                Text("\(Int(exportProgressValue * 100))%")
                                    .font(.caption.monospacedDigit().bold())
                                    .foregroundStyle(Color(hex: "#6366F1"))
                            }
                            ProgressView(value: exportProgressValue, total: 1.0)
                                .tint(Color(hex: "#6366F1"))
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#6366F1").opacity(0.08)))
                    }

                    Divider()

                    // Grade informativa de tudo o que é incluído na exportação completa
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 10) {
                        ForEach(ExportDataTarget.allCases) { target in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(Color(hex: "#6366F1"))

                                Image(systemName: target.icon)
                                    .font(.subheadline)
                                    .frame(width: 18)
                                    .foregroundStyle(Color(hex: "#6366F1"))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(target.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(target.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Text(exportCountLabel(for: target))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                            }
                            .padding(9)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(hex: "#6366F1").opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(hex: "#6366F1").opacity(0.22), lineWidth: 1)
                            )
                        }
                    }

                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.shield.fill")
                                .foregroundStyle(Color(hex: "#6366F1"))
                            Text("Formato Otimizado: Pacote Comprimido LZFSE (.fcbackup) ou JSON Estruturado (.json) • Modelos LLM ignorados")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if let exportBanner = exportStatusBanner {
                        HStack {
                            Image(systemName: exportIsError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                                .foregroundStyle(exportIsError ? Color(hex: "#EF4444") : .green)
                            Text(exportBanner)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill((exportIsError ? Color(hex: "#EF4444") : Color.green).opacity(0.12))
                        )
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))

                // Card 2: Importação Seletiva e Validada da Base de Dados
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: "#10B981").opacity(0.14))
                                .frame(width: 46, height: 46)
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Color(hex: "#10B981"))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Importação Seletiva e Validada de Dados")
                                .font(.title3.bold())
                            Text("Selecione um arquivo de backup (.fcbackup ou .json) e escolha quais itens deseja importar (Categorias, Contas, Cartões de Crédito/Faturas, Transações, Investimentos, Empréstimos, Financiamentos, Dívidas, Previsões e Assets). Inclui barra de progresso assíncrona, validação automática de consistência referencial e bloqueio de itens duplicados.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            pickAndPrepareDatabaseImport()
                        } label: {
                            Label(
                                isPreparingImportFile ? "Lendo Arquivo..." : "Selecionar Arquivo para Importar",
                                systemImage: "doc.badge.plus"
                            )
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#10B981"))
                        .disabled(isPreparingImportFile)
                    }

                    if isPreparingImportFile {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Lendo, descomprimindo e validando integridade referencial do arquivo selecionado...")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(hex: "#10B981"))
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#10B981").opacity(0.10)))
                    }

                    if let importBanner = importStatusBanner {
                        HStack {
                            Image(systemName: importIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(importIsError ? Color(hex: "#EF4444") : .green)
                            Text(importBanner)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill((importIsError ? Color(hex: "#EF4444") : Color.green).opacity(0.12))
                        )
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))

                // Card 3: Recomeçar do zero
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: "#EF4444").opacity(0.14))
                                .frame(width: 46, height: 46)
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Color(hex: "#EF4444"))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recomeçar do Zero")
                                .font(.title3.bold())
                            Text("Permite limpar dados da base de forma seletiva ou completa. Você poderá escolher manualmente quais itens deseja deletar (por padrão, todos vêm selecionados).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            showResetFromScratchSheet = true
                        } label: {
                            Label("Recomeçar do Zero...", systemImage: "trash.circle.fill")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#EF4444"))
                    }

                    Divider()

                    // Resumo atual da base
                    Text("Resumo Atual da Base de Dados Local:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        summaryBadge(title: "Transações", count: store.transactions.count, icon: "arrow.left.arrow.right.circle.fill")
                        summaryBadge(title: "Contas", count: store.accounts.count, icon: "building.columns.fill")
                        summaryBadge(title: "Cartões & Faturas", count: store.creditCards.count, icon: "creditcard.fill")
                        summaryBadge(title: "Categorias", count: store.categories.count, icon: "square.grid.2x2.fill")
                        summaryBadge(title: "Investimentos", count: store.investments.count, icon: "chart.line.uptrend.xyaxis.circle.fill")
                        summaryBadge(title: "Empréstimos", count: store.contracts.filter { $0.kind == .loan }.count, icon: "banknote.fill")
                        summaryBadge(title: "Financiamentos", count: store.contracts.filter { $0.kind == .financing }.count, icon: "house.and.flag.fill")
                        summaryBadge(title: "Dívidas", count: store.debts.count, icon: "exclamationmark.shield.fill")
                        summaryBadge(title: "Previsões & Cotas", count: store.provisions.count + store.categoryQuotas.count, icon: "tray.full.fill")
                    }

                    if store.categories.isEmpty {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Sua lista de categorias está vazia.")
                                .font(.caption)
                            Button("Restaurar Categorias Padrões") {
                                store.categories = DefaultCategoriesCatalog.buildInitialCategories()
                                store.save()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if let banner = lastResetBanner {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(banner)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.12)))
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }
        }
        .sheet(isPresented: $showResetFromScratchSheet) {
            ResetFromScratchConfirmationSheet(store: store) { deletedCount in
                lastResetBanner = "Operação concluída: \(deletedCount) grupo(s) de dados foram removidos da base."
            }
        }
        .sheet(isPresented: $showDatabaseImportSelectionSheet) {
            if let pkg = preparedImportPackage {
                DatabaseImportSelectionSheet(
                    store: store,
                    fileName: importedFileName,
                    package: pkg
                ) { result in
                    importIsError = false
                    var details: [String] = []
                    details.append("\(result.totalImportedItems) registro(s) novo(s) importado(s)")
                    if result.skippedDuplicatesTotal > 0 {
                        details.append("\(result.skippedDuplicatesTotal) duplicado(s) ignorado(s)")
                    }
                    if result.autoCreatedDependenciesCount > 0 {
                        details.append("\(result.autoCreatedDependenciesCount) vínculo(s) de consistência preservado(s)")
                    }
                    importStatusBanner = "Importação concluída com sucesso: " + details.joined(separator: " • ") + "."
                }
            }
        }
        .sheet(isPresented: $showExpenseImportReviewSheet) {
            ExpenseJSONImportReviewSheet(
                store: store,
                fileName: importedFileName,
                initialDrafts: importedDraftsForReview
            ) { importedCount, skippedDuplicates in
                importIsError = false
                if skippedDuplicates > 0 {
                    importStatusBanner = "Importação concluída: \(importedCount) lançamento(s) adicionado(s) e \(skippedDuplicates) duplicata(s) ignorada(s)."
                } else {
                    importStatusBanner = "Importação concluída: \(importedCount) lançamento(s) mesclado(s) com sucesso na base ativa."
                }
            }
        }
        .sheet(isPresented: $showAuthSheet) {
            AuthFormSheetView(
                mode: $authMode,
                baseURL: store.cloudSyncService?.baseURLString ?? "http://localhost:8080/api/v1"
            )
        }
    }

    private func exportCountLabel(for target: ExportDataTarget) -> String {
        switch target {
        case .transactions: return "\(store.transactions.count)"
        case .accounts: return "\(store.accounts.count)"
        case .creditCards:
            return store.creditCardInvoices.isEmpty
                ? "\(store.creditCards.count)"
                : "\(store.creditCards.count) (\(store.creditCardInvoices.count) fat.)"
        case .categories: return "\(store.categories.count)"
        case .investments: return "\(store.investments.count)"
        case .loans:
            let loanContracts = store.contracts.filter { $0.kind == .loan }
            let loanIds = Set(loanContracts.map(\.id))
            let planCount = store.amortizationPlans.filter { loanIds.contains($0.contractId) }.count
            return planCount > 0 ? "\(loanContracts.count) (\(planCount) plano\(planCount == 1 ? "" : "s"))" : "\(loanContracts.count)"
        case .financings:
            let finContracts = store.contracts.filter { $0.kind == .financing }
            let finIds = Set(finContracts.map(\.id))
            let planCount = store.amortizationPlans.filter { finIds.contains($0.contractId) }.count
            return planCount > 0 ? "\(finContracts.count) (\(planCount) plano\(planCount == 1 ? "" : "s"))" : "\(finContracts.count)"
        case .debts: return "\(store.debts.count)"
        case .provisions: return "\(store.provisions.count + store.categoryQuotas.count)"
        case .assets:
            return "\(store.collectExportableAssets().count)"
        }
    }

    private func exportFullDatabaseBackup() {
        let dateStamp = BRLFormatters.shortDate(Date()).replacingOccurrences(of: "/", with: "-")
        let defaultName = "financial_backup_completo_\(dateStamp).fcbackup"

        guard let destinationURL = MacFilePicker.saveDatabaseBackupFile(defaultFileName: defaultName) else {
            return
        }

        isExportingDatabase = true
        exportProgressValue = 0.2
        exportStatusBanner = nil

        let shouldCompress = destinationURL.pathExtension.lowercased() != "json"

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 40_000_000)
            exportProgressValue = 0.55

            guard let data = store.exportFullDatabaseArchive(compress: shouldCompress) else {
                isExportingDatabase = false
                exportIsError = true
                exportStatusBanner = "Erro ao empacotar a base de dados para exportação."
                return
            }

            exportProgressValue = 0.85
            try? await Task.sleep(nanoseconds: 30_000_000)

            do {
                try data.write(to: destinationURL, options: .atomic)
                exportProgressValue = 1.0
                isExportingDatabase = false
                exportIsError = false
                let sizeKB = max(1, data.count / 1024)
                exportStatusBanner = "Backup completo exportado com sucesso (\(sizeKB) KB, sem modelos de IA) em: \(destinationURL.lastPathComponent)"
            } catch {
                isExportingDatabase = false
                exportIsError = true
                exportStatusBanner = "Falha ao salvar o arquivo de backup: \(error.localizedDescription)"
            }
        }
    }

    private func pickAndPrepareDatabaseImport() {
        guard let url = MacFilePicker.pickDatabaseImportFile() else { return }
        isPreparingImportFile = true
        importStatusBanner = nil

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            do {
                let data = try Data(contentsOf: url)
                let pkg = try store.prepareDatabaseImportPackage(from: data)
                let totalFound = ExportDataTarget.allCases.reduce(0) { $0 + pkg.totalCount(for: $1) }
                isPreparingImportFile = false

                if totalFound == 0 {
                    importIsError = true
                    importStatusBanner = "Nenhum registro compatível foi encontrado no arquivo '\(url.lastPathComponent)'."
                    return
                }

                importedFileName = url.lastPathComponent
                preparedImportPackage = pkg
                showDatabaseImportSelectionSheet = true
            } catch {
                isPreparingImportFile = false
                importIsError = true
                importStatusBanner = "Erro ao processar arquivo de importação: \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private func summaryBadge(title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(count) registro(s)")
                    .font(.subheadline.bold())
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
    }
}

// MARK: - Modal de Seleção de Entidades e Progresso de Importação da Base de Dados

public struct DatabaseImportSelectionSheet: View {
    @ObservedObject public var store: FinancialDataStore
    public let fileName: String
    public let package: PreparedDatabaseImportPackage
    public var onCompleted: ((SelectiveDatabaseImportResult) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTargets: Set<ExportDataTarget>
    @State private var isImporting: Bool = false
    @State private var importProgress: Double = 0.0
    @State private var importProgressMessage: String = "Preparando importação..."

    public init(
        store: FinancialDataStore,
        fileName: String,
        package: PreparedDatabaseImportPackage,
        onCompleted: ((SelectiveDatabaseImportResult) -> Void)? = nil
    ) {
        self.store = store
        self.fileName = fileName
        self.package = package
        self.onCompleted = onCompleted
        let nonEmptyTargets = ExportDataTarget.allCases.filter { package.totalCount(for: $0) > 0 }
        self._selectedTargets = State(initialValue: Set(nonEmptyTargets))
    }

    public var body: some View {
        let totalNewSelected = selectedTargets.reduce(0) { $0 + package.newCount(for: $1) }
        let totalDuplicatesSelected = selectedTargets.reduce(0) { $0 + package.duplicateCount(for: $1) }
        let totalItemsSelected = selectedTargets.reduce(0) { $0 + package.totalCount(for: $1) }

        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "#10B981").opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(hex: "#10B981"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Escolher Itens para Importar")
                        .font(.title3.bold())
                    Text("Arquivo: \(fileName) • Marque quais módulos deseja importar para sua base local")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isImporting {
                    Button("Selecionar Todos Disponíveis") {
                        selectedTargets = Set(ExportDataTarget.allCases.filter { package.totalCount(for: $0) > 0 })
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Limpar Seleção") {
                        selectedTargets.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Aviso de Consistência Referencial e Anti-Duplicidade
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(Color(hex: "#10B981"))
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Proteção de Consistência e Anti-Duplicidade Ativa")
                        .font(.caption.bold())
                    Text("Registros idênticos já existentes na sua base serão ignorados automaticamente sem duplicar. Caso você importe Transações, Dívidas ou Previsões sem marcar Contas ou Categorias, o sistema mapeará ou criará automaticamente apenas os vínculos necessários para evitar registros órfãos.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#10B981").opacity(0.10)))

            Divider()

            // Lista de Módulos do Backup
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 10) {
                    ForEach(ExportDataTarget.allCases) { target in
                        let total = package.totalCount(for: target)
                        let newCount = package.newCount(for: target)
                        let dupCount = package.duplicateCount(for: target)
                        let isChecked = selectedTargets.contains(target)
                        let isAvailable = total > 0

                        Button {
                            guard isAvailable && !isImporting else { return }
                            if isChecked {
                                selectedTargets.remove(target)
                            } else {
                                selectedTargets.insert(target)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                    .font(.title3)
                                    .foregroundStyle(
                                        !isAvailable ? Color.secondary.opacity(0.35) :
                                        (isChecked ? Color(hex: "#10B981") : .secondary)
                                    )

                                Image(systemName: target.icon)
                                    .font(.subheadline)
                                    .frame(width: 20)
                                    .foregroundStyle(isChecked ? Color(hex: "#10B981") : .secondary)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(target.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(isAvailable ? .primary : .secondary)
                                        .lineLimit(1)

                                    if isAvailable {
                                        HStack(spacing: 6) {
                                            Text("\(newCount) novo(s)")
                                                .font(.caption2.bold())
                                                .foregroundStyle(newCount > 0 ? Color(hex: "#10B981") : .secondary)
                                            if dupCount > 0 {
                                                Text("• \(dupCount) já existente(s)")
                                                    .font(.caption2)
                                                    .foregroundStyle(Color(hex: "#F59E0B"))
                                            }
                                        }
                                    } else {
                                        Text("Vazio neste arquivo")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Text("\(total)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        !isAvailable ? Color.primary.opacity(0.015) :
                                        (isChecked ? Color(hex: "#10B981").opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        isChecked ? Color(hex: "#10B981").opacity(0.4) : Color.primary.opacity(0.07),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!isAvailable || isImporting)
                    }
                }
            }

            if isImporting {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(importProgressMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(hex: "#10B981"))
                        Spacer()
                        Text("\(Int(importProgress * 100))%")
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(Color(hex: "#10B981"))
                    }
                    ProgressView(value: importProgress, total: 1.0)
                        .tint(Color(hex: "#10B981"))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#10B981").opacity(0.10)))
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Módulos marcados: \(selectedTargets.count) • Total no arquivo: \(totalItemsSelected) registro(s)")
                        .font(.caption.weight(.semibold))
                    Text("Serão inseridos: \(totalNewSelected) novo(s) • Ignorados por duplicidade: \(totalDuplicatesSelected)")
                        .font(.caption)
                        .foregroundStyle(totalNewSelected > 0 ? Color(hex: "#10B981") : .secondary)
                }

                Spacer()

                Button("Cancelar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isImporting)

                Button {
                    runSelectiveImport()
                } label: {
                    Label(
                        isImporting ? "Importando..." : "Confirmar e Importar Selecionados (\(selectedTargets.count))",
                        systemImage: "checkmark.circle.fill"
                    )
                    .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))
                .disabled(selectedTargets.isEmpty || isImporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 780, minHeight: 540)
    }

    private func runSelectiveImport() {
        guard !selectedTargets.isEmpty, !isImporting else { return }
        isImporting = true
        importProgress = 0.05
        importProgressMessage = "Iniciando validação de consistência..."

        Task { @MainActor in
            let result = await store.executeSelectiveDatabaseImport(
                package: package,
                selectedTargets: selectedTargets
            ) { progress, message in
                self.importProgress = progress
                self.importProgressMessage = message
            }
            isImporting = false
            onCompleted?(result)
            dismiss()
        }
    }
}

// MARK: - Modal de Revisão Pré-Importação de Gastos / Transações (JSON)

public struct ExpenseJSONImportReviewSheet: View {
    @ObservedObject public var store: FinancialDataStore
    public let fileName: String
    @State private var drafts: [ImportableExpenseDraft]
    public var onCompleted: ((Int, Int) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    public init(
        store: FinancialDataStore,
        fileName: String,
        initialDrafts: [ImportableExpenseDraft],
        onCompleted: ((Int, Int) -> Void)? = nil
    ) {
        self.store = store
        self.fileName = fileName
        self._drafts = State(initialValue: initialDrafts)
        self.onCompleted = onCompleted
    }

    public var body: some View {
        let duplicateCount = drafts.filter(\.isDuplicate).count
        let selectedCount = drafts.filter(\.isSelected).count
        let selectedTotalAmount = drafts.filter(\.isSelected).reduce(0.0) { $0 + $1.amount }

        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "#10B981").opacity(0.16))
                        .frame(width: 42, height: 42)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: "#10B981"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Revisão Pré-Importação de Gastos")
                        .font(.title3.bold())
                    Text("Arquivo: \(fileName) • \(drafts.count) registro(s) encontrado(s) • Valide Data, Descrição, Valor, Categoria e Conta antes de confirmar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Selecionar Não-Duplicados") {
                    for idx in drafts.indices {
                        drafts[idx].isSelected = !drafts[idx].isDuplicate
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Limpar Seleção") {
                    for idx in drafts.indices {
                        drafts[idx].isSelected = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if duplicateCount > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(hex: "#F59E0B"))
                    Text("Verificação Anti-Duplicidade: \(duplicateCount) lançamento(s) idêntico(s) já existe(m) na base ativa e foram desmarcados automaticamente para evitar duplicação.")
                        .font(.caption.weight(.medium))
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#F59E0B").opacity(0.14)))
            }

            Divider()

            // Lista revisável com mapeamento de Data, Descrição, Valor, Categoria e Conta
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach($drafts) { $draft in
                        HStack(spacing: 10) {
                            Toggle("", isOn: $draft.isSelected)
                                .toggleStyle(.checkbox)
                                .labelsHidden()

                            DatePicker(
                                "",
                                selection: $draft.date,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .frame(width: 105)

                            TextField("Descrição", text: $draft.description)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 160)

                            HStack(spacing: 4) {
                                Text("R$")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "0,00",
                                    value: $draft.amount,
                                    format: .number.precision(.fractionLength(2))
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                                .multilineTextAlignment(.trailing)
                            }

                            Picker("Categoria", selection: $draft.categoryId) {
                                ForEach(store.categories.filter { $0.type == draft.type }) { cat in
                                    Text(cat.name).tag(cat.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)

                            if !store.accounts.isEmpty {
                                Picker("Conta", selection: $draft.accountId) {
                                    ForEach(store.accounts) { acc in
                                        Text(acc.name).tag(acc.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 140)
                            }

                            if draft.isDuplicate {
                                Text("Duplicado")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color(hex: "#F59E0B").opacity(0.18)))
                                    .foregroundStyle(Color(hex: "#F59E0B"))
                            } else {
                                Text("Novo")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color(hex: "#10B981").opacity(0.16)))
                                    .foregroundStyle(Color(hex: "#10B981"))
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(draft.isDuplicate ? Color(hex: "#F59E0B").opacity(0.05) : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(draft.isSelected ? Color(hex: "#10B981").opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selecionados para importar: \(selectedCount) de \(drafts.count)")
                        .font(.caption.weight(.semibold))
                    Text("Soma dos itens selecionados: \(BRLFormatters.currency(selectedTotalAmount))")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color(hex: "#10B981"))
                }

                Spacer()

                Button("Cancelar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    let result = store.importReviewedExpenseDrafts(drafts, skipDuplicates: true)
                    onCompleted?(result.importedCount, result.skippedDuplicatesCount + drafts.filter { $0.isDuplicate && !$0.isSelected }.count)
                    dismiss()
                } label: {
                    Label("Confirmar e Mesclar na Base Ativa (\(selectedCount))", systemImage: "checkmark.circle.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))
                .disabled(selectedCount == 0)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 880, minHeight: 540)
    }
}

public struct ResetFromScratchConfirmationSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject private var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss

    // Por padrão todos vêm selecionados!
    @State private var selectedTargets: Set<ResetDataTarget> = Set(ResetDataTarget.allCases)
    // Opção desmarcada por padrão para zerar os dados na nuvem também!
    @State private var resetCloudData: Bool = false
    @State private var isResetting: Bool = false
    @State private var errorMessage: String? = nil
    public var onConfirmed: ((Int) -> Void)? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color(hex: "#EF4444"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirmar: Recomeçar do Zero")
                        .font(.title2.bold())
                    Text("Selecione manualmente os itens que deseja excluir da sua base de dados. Por padrão, todos estão selecionados.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Text("Itens para deletar da base:")
                    .font(.subheadline.bold())
                Spacer()
                Button("Selecionar Todos") {
                    selectedTargets = Set(ResetDataTarget.allCases)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Desmarcar Todos") {
                    selectedTargets.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ResetDataTarget.allCases) { target in
                        let isChecked = selectedTargets.contains(target)
                        Button {
                            if isChecked {
                                selectedTargets.remove(target)
                            } else {
                                selectedTargets.insert(target)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                    .font(.title3)
                                    .foregroundStyle(isChecked ? Color(hex: "#EF4444") : .secondary)

                                Image(systemName: target.icon)
                                    .frame(width: 22)
                                    .foregroundStyle(isChecked ? .primary : .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(target.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(countLabel(for: target))
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isChecked ? Color(hex: "#EF4444").opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isChecked ? Color(hex: "#EF4444").opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Opção para zerar dados na nuvem também (desmarcada por padrão)
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $resetCloudData) {
                    HStack(spacing: 8) {
                        Image(systemName: "icloud.slash.fill")
                            .font(.title3)
                            .foregroundStyle(resetCloudData ? Color(hex: "#EF4444") : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Zerar também os dados na nuvem (FinSense Cloud)")
                                .font(.subheadline.bold())
                                .foregroundStyle(resetCloudData ? Color(hex: "#EF4444") : .primary)
                            Text(authService.isAuthenticated
                                ? "Se marcado, remove os dados persistidos no servidor da sua conta conectada."
                                : "Disponível ao fazer login com uma conta FinSense.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!authService.isAuthenticated || isResetting)

                if let err = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(resetCloudData ? Color(hex: "#EF4444").opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(resetCloudData ? Color(hex: "#EF4444").opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
            )

            HStack {
                Button("Cancelar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isResetting)

                Spacer()

                Button(role: .destructive) {
                    if resetCloudData && authService.isAuthenticated {
                        isResetting = true
                        errorMessage = nil
                        Task {
                            do {
                                let targetStrings = selectedTargets.count == ResetDataTarget.allCases.count
                                    ? nil
                                    : selectedTargets.map(\.rawValue)
                                try await store.cloudSyncService?.resetCloudData(targets: targetStrings)
                                await MainActor.run {
                                    let count = selectedTargets.count
                                    store.resetSelectedData(selectedTargets)
                                    isResetting = false
                                    onConfirmed?(count)
                                    dismiss()
                                }
                            } catch {
                                await MainActor.run {
                                    isResetting = false
                                    errorMessage = "Falha ao zerar dados na nuvem: \(error.localizedDescription)"
                                }
                            }
                        }
                    } else {
                        let count = selectedTargets.count
                        store.resetSelectedData(selectedTargets)
                        onConfirmed?(count)
                        dismiss()
                    }
                } label: {
                    if isResetting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Zerando base...")
                        }
                        .fontWeight(.semibold)
                    } else {
                        Label(
                            resetCloudData ? "Confirmar e Zerar Base Local e Nuvem" : "Confirmar e Deletar Itens Selecionados (\(selectedTargets.count))",
                            systemImage: "trash.fill"
                        )
                        .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#EF4444"))
                .disabled(selectedTargets.isEmpty || isResetting)
            }
        }
        .padding(22)
        .frame(width: 600, height: 620)
    }

    private func countLabel(for target: ResetDataTarget) -> String {
        switch target {
        case .transactions: return "\(store.transactions.count)"
        case .accounts: return "\(store.accounts.count)"
        case .creditCards:
            return store.creditCardInvoices.isEmpty
                ? "\(store.creditCards.count)"
                : "\(store.creditCards.count) (\(store.creditCardInvoices.count) fat.)"
        case .categories: return "\(store.categories.count)"
        case .investments: return "\(store.investments.count)"
        case .loans:
            let loanContracts = store.contracts.filter { $0.kind == .loan }
            let loanIds = Set(loanContracts.map(\.id))
            let planCount = store.amortizationPlans.filter { loanIds.contains($0.contractId) }.count
            return planCount > 0 ? "\(loanContracts.count) (\(planCount) plano\(planCount == 1 ? "" : "s"))" : "\(loanContracts.count)"
        case .financings:
            let finContracts = store.contracts.filter { $0.kind == .financing }
            let finIds = Set(finContracts.map(\.id))
            let planCount = store.amortizationPlans.filter { finIds.contains($0.contractId) }.count
            return planCount > 0 ? "\(finContracts.count) (\(planCount) plano\(planCount == 1 ? "" : "s"))" : "\(finContracts.count)"
        case .debts: return "\(store.debts.count)"
        case .aiModelsAndChat: return "\(store.llmConfig.downloadedModels.count) mod."
        }
    }
}

// MARK: - Modal Obrigatório de Solicitação de Instalação da LLM Local

public struct LLMInstallRequiredSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService
    @Environment(\.dismiss) private var dismiss

    public init(store: FinancialDataStore, llmService: LocalLLMService) {
        self.store = store
        self.llmService = llmService
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#6366F1").opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color(hex: "#6366F1"))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ativar Apple Intelligence no FinSense")
                        .font(.title2.bold())
                    Text("Para utilizar '\(store.pendingAIFeatureName.isEmpty ? "Recursos de IA" : store.pendingAIFeatureName)', ative a integração nativa com Apple Intelligence no seu Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: LocalLLMRuntime.isAppleIntelligenceAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(LocalLLMRuntime.isAppleIntelligenceAvailable ? Color(hex: "#10B981") : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Intelligence (On-Device Apple Silicon)")
                            .font(.headline)
                        Text(LocalLLMRuntime.appleIntelligenceStatusDescription())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("• Processamento 100% privado e nativo no Neural Engine do seu Mac.\n• Acesso completo em tempo real a contas, transações, contratos e planejamento.\n• Nenhuma chave de API externa ou download extra necessário.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if store.hasInstalledLLMModel {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Apple Intelligence ativado e pronto! Você já pode utilizar o Super Agente.")
                            .font(.subheadline.bold())
                            .foregroundStyle(.green)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.12)))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))

            HStack {
                Button("Cancelar") {
                    dismiss()
                }

                Spacer()

                Button("Abrir Configurações da IA") {
                    dismiss()
                    store.navigateToLLMInstallSettings()
                }
                .buttonStyle(.bordered)

                if LocalLLMRuntime.isAppleIntelligenceAvailable {
                    Button {
                        llmService.activateBuiltInAppleIntelligence(in: store)
                        llmService.prewarmAppleIntelligence(store: store)
                        dismiss()
                    } label: {
                        Label(store.hasInstalledLLMModel ? "Concluir e Continuar" : "Ativar Apple Intelligence Agora", systemImage: "sparkles")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#6366F1"))
                }
            }
        }
        .padding(22)
        .frame(width: 560, height: 340)
    }
}

// MARK: - 1. Configuração da Apple Intelligence (Apple Silicon M1 On-Device)

public struct LLMConfigurationSectionView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Card 1: Status Nativo Apple Intelligence
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#6366F1").opacity(0.14))
                                .frame(width: 44, height: 44)
                            Image(systemName: "brain.head.profile")
                                .font(.title2)
                                .foregroundStyle(Color(hex: "#6366F1"))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Intelligence Nativo (Apple Silicon M1)")
                                .font(.title3.bold())
                            Text("Inteligência financeira 100% privada, offline e integrada ao Neural Engine do seu Mac — sem APIs externas.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        let isAvail = LocalLLMRuntime.isAppleIntelligenceAvailable
                        HStack(spacing: 5) {
                            Image(systemName: isAvail ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            Text(isAvail ? "Ativo e Integrado" : "Indisponível")
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill((isAvail ? Color(hex: "#10B981") : Color.orange).opacity(0.15)))
                        .foregroundStyle(isAvail ? Color(hex: "#10B981") : .orange)
                    }

                    Divider()

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Status do Motor no macOS:")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(LocalLLMRuntime.appleIntelligenceStatusDescription())
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()

                        Label("Pré-aquecimento Automático Ativo", systemImage: "bolt.shield.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color(hex: "#6366F1").opacity(0.12)))
                            .foregroundStyle(Color(hex: "#6366F1"))
                            .help("O FinSense pré-aquece o modelo da Apple Intelligence automaticamente em segundo plano ao abrir o app e a conversa, dispensando ação manual.")
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))

                // Card 2: Modo "Pensando" & Ajustes de Inferência
                VStack(alignment: .leading, spacing: 16) {
                    Text("Comportamento do Super Agente & Modo Pensando")
                        .font(.title3.bold())

                    Toggle(isOn: Binding(
                        get: { store.llmConfig.isThinkingModeEnabled },
                        set: { newValue in
                            store.llmConfig.isThinkingModeEnabled = newValue
                            store.save()
                            LocalLLMRuntime.shared.invalidateAppleSession()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Modo \"Pensando\" (Análise Cruzada Completa)")
                                .font(.subheadline.weight(.semibold))
                            Text("Quando ativo, o agente cruza múltiplas ferramentas (contratos, sobra líquida, projeções futuras e reserva) e exibe seu processo de trabalho em tempo real.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Toggle(isOn: Binding(
                        get: { store.llmConfig.isInternetAccessEnabled },
                        set: { newValue in
                            store.llmConfig.isInternetAccessEnabled = newValue
                            store.save()
                            LocalLLMRuntime.shared.invalidateAppleSession()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Consultas na Internet (Apenas Leitura — Cotações & Investimentos)")
                                .font(.subheadline.weight(.semibold))
                            Text("Permite consultar cotações atuais (Dólar, Euro, Bitcoin), taxas (Selic, CDI, IPCA) e recomendações conceituais públicas na web. Nenhum dado pessoal ou financeiro seu é enviado.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Divider()

                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Estilo de Raciocínio (Temperatura):")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { store.llmConfig.appleIntelligenceTemperature },
                                set: { newVal in
                                    store.llmConfig.appleIntelligenceTemperature = newVal
                                    store.save()
                                }
                            )) {
                                Text("Preciso / Analítico (0.15)").tag(0.15)
                                Text("Equilibrado (0.25 — Padrão)").tag(0.25)
                                Text("Conversacional / Aberto (0.45)").tag(0.45)
                            }
                            .frame(width: 240)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Profundidade Máxima da Resposta:")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { store.llmConfig.appleIntelligenceMaxResponseTokens },
                                set: { newVal in
                                    store.llmConfig.appleIntelligenceMaxResponseTokens = newVal
                                    store.save()
                                }
                            )) {
                                Text("Concisa (800 tokens)").tag(800)
                                Text("Detalhada (1.600 tokens — Padrão)").tag(1600)
                                Text("Máxima (2.400 tokens)").tag(2400)
                            }
                            .frame(width: 250)
                        }

                        Spacer()
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))

                // Card 3: Ferramentas Nativas Conectadas ao Banco Local
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ferramentas Nativas Conectadas ao Banco Local")
                        .font(.title3.bold())
                    Text("A Apple Intelligence possui acesso estruturado e determinístico às regras de negócio e entidades abaixo:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let capabilities: [(icon: String, title: String, desc: String)] = [
                        ("building.columns.fill", "Contas Bancárias & Cenários", "Saldos em tempo real, cenário Real (Base) vs Com Planejamento e patrimônio consolidado."),
                        ("doc.text.magnifyingglass", "Empréstimos & Financiamentos", "Parcelas pagas pelo salário, cronograma decrescente DDC, crescimento TP CAIXA e simulação de amortização."),
                        ("calendar.badge.clock", "Planejamento de Amortização & FGTS", "Engine LoanProjectionEngine, quitação antecipada, economia de juros e impacto de aportes em Dinheiro/FGTS."),
                        ("chart.line.uptrend.xyaxis", "Fluxo de Caixa, Dívidas & Transações", "Consultas e agregações por período, projeções de até 36 meses, tetos/envelopes, cotas e investimentos."),
                        ("globe", "Consultas Web (Somente Leitura)", "Cotações de câmbio (Dólar, Euro, BTC), índices (Selic, CDI, IPCA) e conceitos públicos de investimentos sem enviar dados pessoais.")
                    ]

                    ForEach(capabilities, id: \.title) { cap in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: cap.icon)
                                .foregroundStyle(Color(hex: "#6366F1"))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cap.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(cap.desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }
        }
        .onAppear {
            llmService.activateBuiltInAppleIntelligenceIfNeeded(in: store)
        }
    }
}

// MARK: - 2. Gestão de Contas (Cadastro de Conta com Nome + Ícone/Imagem da Máquina ou Base de Bancos)

public struct AccountsManagementSectionView: View {
    @ObservedObject public var store: FinancialDataStore

    @State private var showCreateAccountSheet: Bool = false
    @State private var editingAccount: BankAccount? = nil
    @State private var accountPendingDeletion: BankAccount? = nil
    @State private var draggedAccountId: UUID? = nil

    @State private var showCreateCardSheet: Bool = false
    @State private var editingCard: CreditCard? = nil
    @State private var cardPendingDeletion: CreditCard? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Contas Bancárias, Carteiras & Cartões de Crédito")
                        .font(.title3.bold())
                    Text("Base inicial com os principais bancos e ícones oficiais, gestão integrada de cartões e reordenação arrastando e soltando")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.accounts.count > 1 {
                    Label("Arraste e solte para reordenar", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                }
                Button {
                    showCreateCardSheet = true
                } label: {
                    Label("Adicionar Cartão", systemImage: "creditcard.fill")
                }
                .buttonStyle(.bordered)
                Button {
                    showCreateAccountSheet = true
                } label: {
                    Label("Adicionar Conta", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            if store.accounts.isEmpty && store.creditCards.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "building.columns")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("Nenhuma conta ou cartão cadastrado")
                        .font(.headline)
                    Text("Adicione uma conta bancária ou cartão de crédito escolhendo entre a base inicial de bancos brasileiros ou anexando um ícone/imagem da sua máquina.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Adicionar Primeira Conta") {
                            showCreateAccountSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Cadastrar Cartão de Crédito") {
                            showCreateCardSheet = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 240)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !store.accounts.isEmpty {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                                ForEach(store.accounts) { account in
                                    let currentBal = store.currentBalance(forAccount: account.id)
                                    let isDragging = draggedAccountId == account.id
                                    HStack(spacing: 14) {
                                        Image(systemName: "line.3.horizontal")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .help("Arraste para reordenar esta conta")

                                        AccountAvatarView(account: account, size: 48)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(account.name)
                                                .font(.headline)
                                            if !account.agency.isEmpty || !account.accountNumber.isEmpty {
                                                Text("Agência: \(account.agency) • Conta: \(account.accountNumber)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text("Saldo Inicial: \(BRLFormatters.currency(account.initialBalance))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        VStack(alignment: .trailing, spacing: 6) {
                                            Text(BRLFormatters.currency(currentBal))
                                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                                .foregroundStyle(currentBal >= 0 ? Color(hex: "#10B981") : Color(hex: "#EF4444"))

                                            HStack(spacing: 6) {
                                                Button {
                                                    editingAccount = account
                                                } label: {
                                                    Image(systemName: "pencil")
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)

                                                Button(role: .destructive) {
                                                    accountPendingDeletion = account
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                            }
                                        }
                                    }
                                    .padding(16)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(isDragging ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isDragging ? 2 : 1)
                                    )
                                    .opacity(isDragging ? 0.65 : 1.0)
                                    .onDrag {
                                        draggedAccountId = account.id
                                        return NSItemProvider(object: account.id.uuidString as NSString)
                                    }
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: AccountReorderDropDelegate(
                                            targetAccountId: account.id,
                                            draggedAccountId: $draggedAccountId,
                                            store: store
                                        )
                                    )
                                }
                            }
                            .animation(.easeInOut(duration: 0.18), value: store.accounts.map(\.id))
                        }

                        // MARK: Seção de Cartões de Crédito Integrada às Contas
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Cartões de Crédito (\(store.creditCards.count))", systemImage: "creditcard.fill")
                                    .font(.headline)
                                Spacer()
                                if !store.creditCards.isEmpty {
                                    Button {
                                        store.selectedDestination = .creditCards
                                    } label: {
                                        Label("Abrir Painel Completo de Faturas", systemImage: "arrow.up.right.square")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.link)
                                }
                            }

                            if store.creditCards.isEmpty {
                                HStack(spacing: 12) {
                                    Image(systemName: "creditcard")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Nenhum cartão de crédito cadastrado")
                                            .font(.subheadline.weight(.semibold))
                                        Text("Cadastre um cartão com limite total, dia de fechamento, melhor dia de compra e vencimento da fatura.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Adicionar Cartão") {
                                        showCreateCardSheet = true
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                                    ForEach(store.creditCards) { card in
                                        let used = store.usedLimit(for: card.id)
                                        let available = store.availableLimit(for: card.id)
                                        let ratio = card.totalLimit > 0 ? min(1.0, max(0.0, used / card.totalLimit)) : 0.0
                                        let payBank = card.defaultPaymentAccountId.flatMap { store.account(for: $0)?.name } ?? "Automática"

                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack(spacing: 12) {
                                                AccountAvatarView(
                                                    customImagePath: card.customImagePath,
                                                    bankPresetId: card.bankPresetId,
                                                    fallbackSymbol: card.iconSymbol,
                                                    colorHex: card.colorHex,
                                                    size: 46
                                                )
                                                VStack(alignment: .leading, spacing: 3) {
                                                    HStack(spacing: 6) {
                                                        Text(card.name)
                                                            .font(.headline)
                                                        Text(card.brand.shortBadge)
                                                            .font(.system(size: 10, weight: .bold))
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Capsule().fill(Color(hex: card.colorHex).opacity(0.16)))
                                                            .foregroundStyle(Color(hex: card.colorHex))
                                                    }
                                                    Text("Fecha dia \(card.closingDay) • Melhor compra \(card.bestPurchaseDay) • Vence dia \(card.dueDay)")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    Text("Conta débito: \(payBank)")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                            }

                                            ProgressView(value: ratio)
                                                .tint(used > card.totalLimit ? .red : Color(hex: card.colorHex))

                                            HStack {
                                                Text("Utilizado: \(BRLFormatters.currency(used))")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(used > 0 ? .orange : .secondary)
                                                Spacer()
                                                Text("Disponível: \(BRLFormatters.currency(available)) / \(BRLFormatters.currency(card.totalLimit))")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(available > 0 ? .green : .red)
                                            }

                                            HStack(spacing: 8) {
                                                Button {
                                                    store.selectedCreditCardIdForDetail = card.id
                                                    store.selectedDestination = .creditCards
                                                } label: {
                                                    Label("Ver Faturas", systemImage: "doc.text.magnifyingglass")
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)

                                                Spacer()

                                                Button {
                                                    editingCard = card
                                                } label: {
                                                    Image(systemName: "pencil")
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)

                                                Button(role: .destructive) {
                                                    cardPendingDeletion = card
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                            }
                                        }
                                        .padding(16)
                                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(Color(hex: card.colorHex).opacity(0.24), lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateAccountSheet) {
            AccountEditorSheet(store: store, existingAccount: nil)
        }
        .sheet(item: $editingAccount) { acc in
            AccountEditorSheet(store: store, existingAccount: acc)
        }
        .sheet(isPresented: $showCreateCardSheet) {
            CreditCardEditorSheet(store: store, existingCard: nil)
        }
        .sheet(item: $editingCard) { card in
            CreditCardEditorSheet(store: store, existingCard: card)
        }
        .alert(
            "Confirmar Exclusão de Cartão",
            isPresented: Binding(
                get: { cardPendingDeletion != nil },
                set: { if !$0 { cardPendingDeletion = nil } }
            ),
            presenting: cardPendingDeletion
        ) { card in
            Button("Excluir Cartão", role: .destructive) {
                store.deleteCreditCard(card.id)
                cardPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                cardPendingDeletion = nil
            }
        } message: { card in
            Text("Deseja realmente excluir o cartão \"\(card.name)\"? As compras existentes terão a vinculação removida e projeções em aberto serão canceladas.")
        }
        .alert(
            "Confirmar Exclusão de Conta",
            isPresented: Binding(
                get: { accountPendingDeletion != nil },
                set: { if !$0 { accountPendingDeletion = nil } }
            ),
            presenting: accountPendingDeletion
        ) { account in
            Button("Excluir Conta", role: .destructive) {
                store.deleteAccount(account.id)
                accountPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                accountPendingDeletion = nil
            }
        } message: { account in
            Text("Deseja realmente excluir a conta \"\(account.name)\"? Esta ação não pode ser desfeita.")
        }
    }
}

private struct AccountReorderDropDelegate: DropDelegate {
    let targetAccountId: UUID
    @Binding var draggedAccountId: UUID?
    let store: FinancialDataStore

    func dropEntered(info: DropInfo) {
        guard let draggedId = draggedAccountId, draggedId != targetAccountId else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            store.moveAccount(draggedId: draggedId, targetId: targetAccountId)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedAccountId = nil
        return true
    }
}

public struct AccountEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let existingAccount: BankAccount?

    @State private var isCreditCardMode: Bool = false
    @State private var name: String = ""
    @State private var selectedPresetId: String? = "itau"
    @State private var customImagePath: String? = nil
    @State private var showRemoveImageConfirmation: Bool = false
    @State private var colorHex: String = "#EC7000"
    @State private var initialBalanceText: String = ""
    @State private var agency: String = ""
    @State private var accountNumber: String = ""
    // Campos específicos quando isCreditCardMode == true
    @State private var closingDay: Int = 25
    @State private var bestPurchaseDay: Int = 26
    @State private var bestPurchaseManuallyEdited: Bool = false
    @State private var dueDay: Int = 5
    @State private var defaultPaymentAccountId: UUID? = nil
    @State private var cardBrand: CreditCardBrand = .mastercard
    @State private var lastFourDigits: String = ""
    @State private var errorMsg: String? = nil

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(existingAccount == nil ? (isCreditCardMode ? "Cadastro de Cartão de Crédito" : "Cadastro de Conta") : "Editar Conta")
                    .font(.title2.bold())
                Spacer()
                if existingAccount == nil {
                    Picker("Tipo", selection: $isCreditCardMode) {
                        Text("Conta Bancária / Carteira").tag(false)
                        Text("Cartão de Crédito").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 310)
                }
            }

            Form {
                if isCreditCardMode {
                    Section("Dados do Cartão de Crédito") {
                        BorderedTextField(
                            label: "Nome do Cartão",
                            placeholder: "Ex: Cartão Principal, Cartão da Mãe",
                            text: $name
                        )
                        HStack(alignment: .bottom, spacing: 12) {
                            BRLCurrencyTextField(
                                label: "Limite Total de Crédito (R$)",
                                text: $initialBalanceText
                            )
                            BorderedTextField(
                                label: "Final (4 dígitos, opc.)",
                                placeholder: "Ex: 4821",
                                text: $lastFourDigits
                            )
                            .frame(width: 155)
                            Picker("Bandeira", selection: $cardBrand) {
                                ForEach(CreditCardBrand.allCases) { b in
                                    Text(b.rawValue).tag(b)
                                }
                            }
                            .frame(width: 185)
                        }
                        HStack(alignment: .bottom, spacing: 12) {
                            EditableIntegerStepperField(
                                label: "Dia Fechamento",
                                value: $closingDay,
                                range: 1...31
                            )
                            EditableIntegerStepperField(
                                label: "Melhor Dia Compra",
                                value: $bestPurchaseDay,
                                range: 1...31
                            )
                            EditableIntegerStepperField(
                                label: "Dia Vencimento",
                                value: $dueDay,
                                range: 1...31
                            )
                        }
                        Picker("Conta Padrão de Pagamento (Opcional)", selection: $defaultPaymentAccountId) {
                            Text("Selecionar automaticamente").tag(UUID?.none)
                            ForEach(store.accounts) { acc in
                                Text(acc.name).tag(UUID?.some(acc.id))
                            }
                        }
                    }
                } else {
                    Section("Dados da Conta") {
                        BorderedTextField(
                            label: "Nome da Conta",
                            placeholder: "Ex: Itaú Unibanco, Nubank, Santander",
                            text: $name
                        )
                        HStack(alignment: .bottom, spacing: 12) {
                            BRLCurrencyTextField(
                                label: "Saldo Inicial (R$)",
                                text: $initialBalanceText
                            )
                            BorderedTextField(
                                label: "Agência (Opcional)",
                                placeholder: "Ex: 0001",
                                text: $agency
                            )
                            BorderedTextField(
                                label: "Conta (Opcional)",
                                placeholder: "Ex: 12345-6",
                                text: $accountNumber
                            )
                        }
                    }
                }

                Section("Ícone da Base de Bancos ou Imagem Anexa da Máquina") {
                    HStack(spacing: 16) {
                        AccountAvatarView(
                            customImagePath: customImagePath,
                            bankPresetId: selectedPresetId,
                            fallbackSymbol: "building.columns.fill",
                            colorHex: colorHex,
                            size: 54
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                if let url = MacFilePicker.pickImageFile(),
                                   let saved = store.copyAttachmentToStorage(from: url) {
                                    customImagePath = saved.path
                                }
                            } label: {
                                Label("Anexar Imagem / Ícone da Minha Máquina...", systemImage: "photo.badge.plus")
                            }

                            if customImagePath != nil {
                                Button("Remover imagem anexada e usar ícone do banco") {
                                    showRemoveImageConfirmation = true
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                        }
                    }

                    Text("Base Inicial dos Principais Bancos (Clique para selecionar):")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(BrazilianBanksCatalog.presets) { preset in
                                let isSelected = selectedPresetId == preset.id && customImagePath == nil
                                Button {
                                    selectedPresetId = preset.id
                                    colorHex = preset.primaryHex
                                    if name.trimmingCharacters(in: .whitespaces).isEmpty {
                                        name = preset.name
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        AccountAvatarView(
                                            customImagePath: nil,
                                            bankPresetId: preset.id,
                                            fallbackSymbol: preset.symbolName,
                                            colorHex: preset.primaryHex,
                                            size: 40
                                        )
                                        Text(preset.name)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .frame(width: 82)
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(isSelected ? Color(hex: preset.primaryHex).opacity(0.16) : Color.primary.opacity(0.03))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isSelected ? Color(hex: preset.primaryHex) : Color.clear, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMsg {
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button(existingAccount == nil ? (isCreditCardMode ? "Cadastrar Cartão" : "Salvar Conta") : "Atualizar Conta") {
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty else {
                        errorMsg = isCreditCardMode ? "Informe o nome do cartão." : "Informe o nome da conta."
                        return
                    }
                    let amountVal = BRLFormatters.parseAmount(initialBalanceText) ?? 0.0
                    let symbol = BrazilianBanksCatalog.preset(for: selectedPresetId)?.symbolName ?? (isCreditCardMode ? "creditcard.fill" : "building.columns.fill")

                    if isCreditCardMode && existingAccount == nil {
                        guard amountVal > 0 else {
                            errorMsg = "Informe um limite total maior que R$ 0,00."
                            return
                        }
                        let created = store.addCreditCard(
                            name: cleanName,
                            totalLimit: amountVal,
                            closingDay: closingDay,
                            bestPurchaseDay: bestPurchaseDay,
                            dueDay: dueDay,
                            defaultPaymentAccountId: defaultPaymentAccountId,
                            brand: cardBrand,
                            bankPresetId: selectedPresetId,
                            customImagePath: customImagePath,
                            iconSymbol: "creditcard.fill",
                            colorHex: colorHex,
                            lastFourDigits: lastFourDigits
                        )
                        store.selectedCreditCardIdForDetail = created.id
                    } else if var existing = existingAccount {
                        existing.name = cleanName
                        existing.bankPresetId = selectedPresetId
                        existing.customImagePath = customImagePath
                        existing.iconSymbol = symbol
                        existing.colorHex = colorHex
                        existing.initialBalance = amountVal
                        existing.agency = agency
                        existing.accountNumber = accountNumber
                        store.updateAccount(existing)
                    } else {
                        store.addAccount(
                            name: cleanName,
                            bankPresetId: selectedPresetId,
                            customImagePath: customImagePath,
                            iconSymbol: symbol,
                            colorHex: colorHex,
                            initialBalance: amountVal,
                            agency: agency,
                            accountNumber: accountNumber
                        )
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 660, height: isCreditCardMode ? 620 : 540)
        .onChange(of: closingDay) { _, newClosing in
            if !bestPurchaseManuallyEdited {
                bestPurchaseDay = CreditCardEngine.suggestedBestPurchaseDay(forClosingDay: newClosing)
            }
        }
        .onChange(of: bestPurchaseDay) { _, newBest in
            if newBest != CreditCardEngine.suggestedBestPurchaseDay(forClosingDay: closingDay) {
                bestPurchaseManuallyEdited = true
            }
        }
        .onChange(of: lastFourDigits) { _, newVal in
            let digits = String(newVal.filter { $0.isNumber }.prefix(4))
            if digits != newVal { lastFourDigits = digits }
        }
        .onAppear {
            if let existing = existingAccount {
                name = existing.name
                selectedPresetId = existing.bankPresetId
                customImagePath = existing.customImagePath
                colorHex = existing.colorHex
                initialBalanceText = BRLFormatters.currency(existing.initialBalance)
                agency = existing.agency
                accountNumber = existing.accountNumber
            } else {
                defaultPaymentAccountId = store.accounts.first?.id
                bestPurchaseDay = CreditCardEngine.suggestedBestPurchaseDay(forClosingDay: closingDay)
            }
        }
        .alert("Confirmar Remoção de Imagem", isPresented: $showRemoveImageConfirmation) {
            Button("Remover Imagem", role: .destructive) {
                customImagePath = nil
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Deseja realmente remover a imagem anexada da sua máquina e voltar a utilizar o ícone padrão do banco?")
        }
    }
}

// MARK: - 3. Gestão de Categorias (Separadas por Despesas e Receitas + Seletor Completo de Ícones do Mac)

public struct CategoriesManagementSectionView: View {
    @ObservedObject public var store: FinancialDataStore

    @State private var selectedTypeTab: TransactionType = .expense
    @State private var showCreateCategorySheet: Bool = false
    @State private var editingCategory: CategoryItem? = nil
    @State private var categoryPendingDeletion: CategoryItem? = nil
    @State private var draggedCategoryId: UUID? = nil

    public var body: some View {
        let filteredCategories = store.categories(for: selectedTypeTab)

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("Tipo de Categoria", selection: $selectedTypeTab) {
                    Text("Categorias de Despesas (\(store.categories(for: .expense).count))").tag(TransactionType.expense)
                    Text("Categorias de Receitas (\(store.categories(for: .income).count))").tag(TransactionType.income)
                }
                .pickerStyle(.segmented)
                .frame(width: 440)

                Spacer()

                if filteredCategories.count > 1 {
                    Label("Arraste e solte para reordenar", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                }

                Button {
                    showCreateCategorySheet = true
                } label: {
                    Label("Nova Categoria de \(selectedTypeTab.title)", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedTypeTab == .expense ? Color(hex: "#EF4444") : Color(hex: "#10B981"))
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(filteredCategories) { cat in
                        let isDragging = draggedCategoryId == cat.id
                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .help("Arraste para reordenar esta categoria")

                            CategoryBadgeView(category: cat, size: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(cat.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(cat.iconSymbol)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                editingCategory = cat
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)

                            Button(role: .destructive) {
                                categoryPendingDeletion = cat
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isDragging ? Color.accentColor : Color.primary.opacity(0.07), lineWidth: isDragging ? 2 : 1)
                        )
                        .opacity(isDragging ? 0.65 : 1.0)
                        .onDrag {
                            draggedCategoryId = cat.id
                            return NSItemProvider(object: cat.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: CategoryReorderDropDelegate(
                                targetCategoryId: cat.id,
                                draggedCategoryId: $draggedCategoryId,
                                store: store
                            )
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: filteredCategories.map(\.id))
            }
        }
        .sheet(isPresented: $showCreateCategorySheet) {
            CategoryEditorSheet(store: store, initialType: selectedTypeTab, existingCategory: nil)
        }
        .sheet(item: $editingCategory) { cat in
            CategoryEditorSheet(store: store, initialType: cat.type, existingCategory: cat)
        }
        .alert(
            "Confirmar Exclusão de Categoria",
            isPresented: Binding(
                get: { categoryPendingDeletion != nil },
                set: { if !$0 { categoryPendingDeletion = nil } }
            ),
            presenting: categoryPendingDeletion
        ) { cat in
            Button("Excluir Categoria", role: .destructive) {
                store.deleteCategory(cat.id)
                categoryPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                categoryPendingDeletion = nil
            }
        } message: { cat in
            Text("Deseja realmente excluir a categoria de \(cat.type.title.lowercased()) \"\(cat.name)\"? Esta ação não pode ser desfeita.")
        }
    }
}

private struct CategoryReorderDropDelegate: DropDelegate {
    let targetCategoryId: UUID
    @Binding var draggedCategoryId: UUID?
    let store: FinancialDataStore

    func dropEntered(info: DropInfo) {
        guard let draggedId = draggedCategoryId, draggedId != targetCategoryId else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            store.moveCategory(draggedId: draggedId, targetId: targetCategoryId)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedCategoryId = nil
        return true
    }
}

public struct CategoryEditorSheet: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.dismiss) private var dismiss

    public let existingCategory: CategoryItem?

    @State private var name: String = ""
    @State private var type: TransactionType
    @State private var selectedSymbol: String = "cart.fill"
    @State private var colorHex: String = "#F97316"
    @State private var iconSearchQuery: String = ""
    @State private var errorMsg: String? = nil

    private let colorPalette = [
        "#EF4444", "#F97316", "#EAB308", "#10B981", "#14B8A6",
        "#06B6D4", "#3B82F6", "#6366F1", "#8B5CF6", "#EC4899", "#64748B"
    ]

    public init(store: FinancialDataStore, initialType: TransactionType, existingCategory: CategoryItem?) {
        self.store = store
        self.existingCategory = existingCategory
        _type = State(initialValue: existingCategory?.type ?? initialType)
    }

    public var body: some View {
        let matchingIconGroups = MacIconCatalog.search(iconSearchQuery)

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CategoryBadgeView(symbol: selectedSymbol, colorHex: colorHex, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(existingCategory == nil ? "Cadastro de Categoria" : "Editar Categoria")
                        .font(.title2.bold())
                    Text("Escolha o nome, a cor e selecione o ícone na biblioteca completa de símbolos nativos do macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .bottom, spacing: 14) {
                BorderedTextField(
                    label: "Nome da Categoria",
                    placeholder: "Ex: Supermercado, Salário, Academia",
                    text: $name
                )

                Picker("Tipo", selection: $type) {
                    ForEach(TransactionType.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            // Color Palette
            HStack(spacing: 10) {
                Text("Cor:")
                    .font(.caption.bold())
                ForEach(colorPalette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: colorHex == hex ? 2.5 : 0)
                        )
                        .onTapGesture {
                            colorHex = hex
                        }
                }
            }

            Divider()

            // Searchable Complete macOS SF Symbols Picker
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                MacFullWidthTextInput(
                    text: $iconSearchQuery,
                    placeholder: "Buscar ícone do macOS (ex: carro, casa, comida, banco, avião, pet ou nome SF Symbol)...",
                    font: .systemFont(ofSize: 13.5)
                )
                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
                if !iconSearchQuery.isEmpty {
                    Button {
                        iconSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.32), lineWidth: 1.2))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(matchingIconGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                                ForEach(group.symbols) { item in
                                    let isSelected = selectedSymbol == item.symbol
                                    Button {
                                        selectedSymbol = item.symbol
                                    } label: {
                                        VStack(spacing: 5) {
                                            Image(systemName: item.symbol)
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(isSelected ? Color(hex: colorHex) : .primary)
                                                .frame(height: 22)
                                            Text(item.label)
                                                .font(.system(size: 10))
                                                .lineLimit(1)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 4)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(isSelected ? Color(hex: colorHex).opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? Color(hex: colorHex) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.5 : 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if let errorMsg {
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button(existingCategory == nil ? "Salvar Categoria" : "Atualizar Categoria") {
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanName.isEmpty else {
                        errorMsg = "Informe o nome da categoria."
                        return
                    }
                    if var existing = existingCategory {
                        existing.name = cleanName
                        existing.type = type
                        existing.iconSymbol = selectedSymbol
                        existing.colorHex = colorHex
                        store.updateCategory(existing)
                    } else {
                        store.addCategory(
                            name: cleanName,
                            type: type,
                            iconSymbol: selectedSymbol,
                            colorHex: colorHex
                        )
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: colorHex))
            }
        }
        .padding(22)
        .frame(width: 680, height: 600)
        .onAppear {
            if let existing = existingCategory {
                name = existing.name
                type = existing.type
                selectedSymbol = existing.iconSymbol
                colorHex = existing.colorHex
            }
        }
    }
}
