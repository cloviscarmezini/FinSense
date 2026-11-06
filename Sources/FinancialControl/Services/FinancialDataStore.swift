import Foundation
import SwiftUI

// MARK: - Persistent Snapshot

public struct FinancialDatabaseSnapshot: Codable {
    public var schemaVersion: Int?
    public var accounts: [BankAccount]
    public var categories: [CategoryItem]
    public var transactions: [FinancialTransaction]
    public var investments: [InvestmentItem]
    public var debts: [DebtItem]
    public var contracts: [CreditContract]
    public var llmConfig: LLMConfiguration
    public var chatHistory: [ChatMessage]
    public var hasSeededInitialStatement: Bool

    public init(
        schemaVersion: Int? = 2,
        accounts: [BankAccount] = [],
        categories: [CategoryItem] = [],
        transactions: [FinancialTransaction] = [],
        investments: [InvestmentItem] = [],
        debts: [DebtItem] = [],
        contracts: [CreditContract] = [],
        llmConfig: LLMConfiguration = LLMConfiguration(),
        chatHistory: [ChatMessage] = [],
        hasSeededInitialStatement: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.accounts = accounts
        self.categories = categories
        self.transactions = transactions
        self.investments = investments
        self.debts = debts
        self.contracts = contracts
        self.llmConfig = llmConfig
        self.chatHistory = chatHistory
        self.hasSeededInitialStatement = hasSeededInitialStatement
    }
}

// MARK: - Dashboard Breakdown Models

public struct CategorySpendSummary: Identifiable, Hashable {
    public var id: UUID { category.id }
    public let category: CategoryItem
    public let total: Double
    public let percentage: Double
    public let count: Int
}

public struct MonthlyCashFlowPoint: Identifiable, Hashable {
    public var id: String { label }
    public let monthDate: Date
    public let label: String
    public let income: Double
    public let expense: Double
    public let net: Double
    public let accumulatedBalance: Double
}

public struct DebtLineItem: Identifiable, Hashable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let section: String
    public let nominalAmount: Double
    public let projectedPayoffAmount: Double
    public let iconSymbol: String
    public let colorHex: String
}

public struct ComprehensiveDebtSummary: Hashable {
    public let currentMonthUnpaidTransactions: [FinancialTransaction]
    public let futureUnpaidRegularTransactions: [FinancialTransaction]
    public let activeDebts: [DebtItem]
    public let activeLoans: [CreditContract]
    public let activeFinancings: [CreditContract]

    public let currentMonthUnpaidTotal: Double
    public let futureRegularExpensesTotal: Double
    public let unpaidDebtsTotal: Double
    public let loansRemainingNominalTotal: Double
    public let loansProjectedPayoffTotal: Double
    public let financingsRemainingNominalTotal: Double
    public let financingsProjectedPayoffTotal: Double

    public let grandTotalNominal: Double
    public let grandTotalWithPayoffProjection: Double
    public let itemizedLines: [DebtLineItem]
}

// MARK: - FinancialDataStore

@MainActor
public final class FinancialDataStore: ObservableObject {
    @Published public var accounts: [BankAccount] = []
    @Published public var categories: [CategoryItem] = []
    @Published public var transactions: [FinancialTransaction] = []
    @Published public var investments: [InvestmentItem] = []
    @Published public var debts: [DebtItem] = []
    @Published public var contracts: [CreditContract] = []
    @Published public var llmConfig: LLMConfiguration = LLMConfiguration()
    @Published public var chatHistory: [ChatMessage] = []
    @Published public var selectedMonth: Date = Date()
    @Published public var selectedDestination: SidebarDestination = .dashboard
    @Published public var selectedSettingsSection: SettingsSection = .general
    @Published public var isAIChatPresented: Bool = false
    @Published public var isLLMInstallAlertPresented: Bool = false
    @Published public var pendingAIFeatureName: String = ""

    public let storageDirectory: URL
    public let databaseFileURL: URL
    public let attachmentsDirectoryURL: URL
    public let modelsDirectoryURL: URL

    private var hasSeededInitialStatement: Bool = false
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "pt_BR")
        return cal
    }()

    public init(customDirectory: URL? = nil, seedStatementOnFirstLaunch: Bool = false) {
        if let customDirectory {
            self.storageDirectory = customDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.storageDirectory = appSupport.appendingPathComponent("FinancialControl", isDirectory: true)
        }
        self.databaseFileURL = storageDirectory.appendingPathComponent("database.json")
        self.attachmentsDirectoryURL = storageDirectory.appendingPathComponent("Attachments", isDirectory: true)
        self.modelsDirectoryURL = storageDirectory.appendingPathComponent("Models", isDirectory: true)

        createDirectoriesIfNeeded()
        loadOrInitialize(seedStatementOnFirstLaunch: seedStatementOnFirstLaunch)
    }

    private func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: attachmentsDirectoryURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
    }

    public func loadOrInitialize(seedStatementOnFirstLaunch: Bool = false) {
        let fm = FileManager.default
        if fm.fileExists(atPath: databaseFileURL.path),
           let data = try? Data(contentsOf: databaseFileURL),
           let decoded = try? JSONDecoder().decode(FinancialDatabaseSnapshot.self, from: data),
           decoded.schemaVersion == 2 {
            self.accounts = decoded.accounts
            self.categories = decoded.categories
            self.transactions = decoded.transactions
            self.investments = decoded.investments
            self.debts = decoded.debts
            self.contracts = decoded.contracts
            self.llmConfig = decoded.llmConfig
            self.chatHistory = decoded.chatHistory
            self.hasSeededInitialStatement = decoded.hasSeededInitialStatement
        } else {
            // Instalação limpa: sempre inicia zerado, apenas com as categorias padrões, sem despesas ou contas.
            self.categories = DefaultCategoriesCatalog.buildInitialCategories()
            self.accounts = []
            self.transactions = []
            self.investments = []
            self.debts = []
            self.contracts = []
            self.llmConfig = LLMConfiguration()
            self.chatHistory = [
                ChatMessage(
                    role: .assistant,
                    content: "Olá! Sou seu assistente financeiro local. Tenho acesso completo às suas contas, transações, investimentos, empréstimos, financiamentos e dívidas. Você pode me pedir análises de períodos específicos, projeções de saldo futuro ou estimativas para quitação de dívidas!"
                )
            ]
            if seedStatementOnFirstLaunch {
                self.accounts = Self.buildDefaultAccounts()
                self.investments = Self.buildDefaultInvestments(accounts: self.accounts)
                self.debts = Self.buildDefaultSampleDebts()
                seedAttachedItauStatementIfNeeded()
            }
            save()
        }
    }

    public func save() {
        let snapshot = FinancialDatabaseSnapshot(
            schemaVersion: 2,
            accounts: accounts,
            categories: categories,
            transactions: transactions,
            investments: investments,
            debts: debts,
            contracts: contracts,
            llmConfig: llmConfig,
            chatHistory: chatHistory,
            hasSeededInitialStatement: hasSeededInitialStatement
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: databaseFileURL, options: .atomic)
        }
    }

    // MARK: - Mandatory Local LLM Installation Check & Reset from Scratch ("Recomeçar do zero")

    public var hasInstalledLLMModel: Bool {
        !llmConfig.downloadedModels.isEmpty && llmConfig.selectedModel != nil
    }

    /// Qualquer opção que use IA obrigatoriamente solicita a instalação caso o usuário tente usar sem ter instalado previamente.
    @discardableResult
    public func requireInstalledLLM(forFeature featureName: String, action: () -> Void) -> Bool {
        if hasInstalledLLMModel {
            action()
            return true
        } else {
            pendingAIFeatureName = featureName
            isLLMInstallAlertPresented = true
            return false
        }
    }

    public func openAIChat() {
        _ = requireInstalledLLM(forFeature: "Chat Financeiro com IA Local") {
            isAIChatPresented = true
        }
    }

    public func navigateToLLMInstallSettings() {
        isLLMInstallAlertPresented = false
        isAIChatPresented = false
        selectedDestination = .settings
        selectedSettingsSection = .llm
    }

    /// Recomeçar do zero: deleta da base todos os itens selecionados pelo usuário.
    public func resetSelectedData(_ targets: Set<ResetDataTarget>) {
        if targets.contains(.transactions) {
            transactions.removeAll()
            hasSeededInitialStatement = false
        }
        if targets.contains(.accounts) {
            accounts.removeAll()
        }
        if targets.contains(.categories) {
            categories.removeAll()
        }
        if targets.contains(.investments) {
            investments.removeAll()
            if !targets.contains(.transactions) {
                transactions.removeAll { $0.linkedInvestmentId != nil }
            }
        }
        if targets.contains(.loans) {
            let loanIds = Set(contracts.filter { $0.kind == .loan }.map(\.id))
            contracts.removeAll { $0.kind == .loan }
            if !targets.contains(.transactions) {
                transactions.removeAll { tx in
                    guard let cid = tx.linkedContractId else { return false }
                    return loanIds.contains(cid)
                }
            }
        }
        if targets.contains(.financings) {
            let finIds = Set(contracts.filter { $0.kind == .financing }.map(\.id))
            contracts.removeAll { $0.kind == .financing }
            if !targets.contains(.transactions) {
                transactions.removeAll { tx in
                    guard let cid = tx.linkedContractId else { return false }
                    return finIds.contains(cid)
                }
            }
        }
        if targets.contains(.debts) {
            debts.removeAll()
            if !targets.contains(.transactions) {
                transactions.removeAll { $0.linkedDebtId != nil }
            }
        }
        if targets.contains(.aiModelsAndChat) {
            for model in llmConfig.downloadedModels {
                let fileURL = URL(fileURLWithPath: model.localPath)
                let parentDir = fileURL.deletingLastPathComponent()
                try? FileManager.default.removeItem(at: fileURL)
                if parentDir.lastPathComponent.contains("__") {
                    try? FileManager.default.removeItem(at: parentDir)
                }
            }
            llmConfig.downloadedModels.removeAll()
            llmConfig.selectedModelId = nil
            chatHistory = [
                ChatMessage(
                    role: .assistant,
                    content: "Olá! Sou seu assistente financeiro local. Tenho acesso completo às suas contas, transações, investimentos, empréstimos, financiamentos e dívidas."
                )
            ]
        }
        save()
    }

    // MARK: - Default Accounts & Investments

    public static func buildDefaultAccounts() -> [BankAccount] {
        [
            BankAccount(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
                name: "Itaú Unibanco",
                bankPresetId: "itau",
                iconSymbol: "building.columns.fill",
                colorHex: "#EC7000",
                initialBalance: 450.00, // Saldo em 05/09/2026 do extrato anexado
                agency: "0731",
                accountNumber: "080047-0"
            ),
            BankAccount(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
                name: "Santander",
                bankPresetId: "santander",
                iconSymbol: "flame.fill",
                colorHex: "#EC0000",
                initialBalance: 0.00,
                agency: "0001",
                accountNumber: "12345-6"
            ),
            BankAccount(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
                name: "Nubank",
                bankPresetId: "nubank",
                iconSymbol: "creditcard.fill",
                colorHex: "#820AD1",
                initialBalance: 0.00,
                agency: "0001",
                accountNumber: "998877-1"
            )
        ]
    }

    public static func buildDefaultInvestments(accounts: [BankAccount]) -> [InvestmentItem] {
        let itauId = accounts.first(where: { $0.bankPresetId == "itau" })?.id ?? accounts.first!.id
        let santanderId = accounts.first(where: { $0.bankPresetId == "santander" })?.id ?? itauId
        return [
            InvestmentItem(
                id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
                name: "Cofrinhos Itaú",
                groupName: "Caixinha Itaú",
                investmentAccountId: itauId,
                balance: 2027.49,
                showInConsolidated: true,
                iconSymbol: "lock.shield.fill",
                colorHex: "#EC7000",
                notes: "Reserva de liquidez diária 100% CDI Itaú"
            ),
            InvestmentItem(
                id: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!,
                name: "CDB DI Liquidez Diária",
                groupName: "CDB Santander",
                investmentAccountId: santanderId,
                balance: 0.00,
                showInConsolidated: true,
                iconSymbol: "chart.line.uptrend.xyaxis",
                colorHex: "#EC0000",
                notes: "CDB pós-fixado DI"
            )
        ]
    }

    public static func buildDefaultSampleDebts() -> [DebtItem] {
        [
            DebtItem(
                id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
                name: "Cartão Mercado Pago",
                bankPresetId: "mercadopago",
                iconSymbol: "creditcard.trianglebadge.exclamationmark",
                colorHex: "#009EE3",
                originalAmount: 1850.00,
                contractedDate: BRLFormatters.shortDateFormatter.date(from: "15/06/2026"),
                notes: "Fatura em aberto aguardando proposta de desconto para quitação à vista."
            )
        ]
    }

    public func seedAttachedItauStatementIfNeeded() {
        guard !hasSeededInitialStatement else { return }
        guard let itauAccount = accounts.first(where: { $0.bankPresetId == "itau" }) ?? accounts.first else { return }

        let rawText = SampleItauStatementData.rawOCRText
        let parsed = StatementImportService.parseStatementText(
            rawText,
            categories: categories,
            filterMode: .hybrid
        )
        _ = importParsedTransactions(parsed, intoAccountId: itauAccount.id, filterMode: .hybrid)
        hasSeededInitialStatement = true

        // Set selectedMonth to November 2026 or October 2026 matching the statement
        if let nov2026 = BRLFormatters.shortDateFormatter.date(from: "05/11/2026") {
            self.selectedMonth = nov2026
        }
        save()
    }

    // MARK: - File Attachment Helper

    public func copyAttachmentToStorage(from sourceURL: URL) -> (path: String, fileName: String)? {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let ext = sourceURL.pathExtension
        let safeName = "\(UUID().uuidString)_\(sourceURL.lastPathComponent)"
        let destinationURL = attachmentsDirectoryURL.appendingPathComponent(ext.isEmpty ? safeName : safeName)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return (destinationURL.path, sourceURL.lastPathComponent)
        } catch {
            if let data = try? Data(contentsOf: sourceURL) {
                try? data.write(to: destinationURL)
                return (destinationURL.path, sourceURL.lastPathComponent)
            }
            return nil
        }
    }

    // MARK: - Month Navigation

    public func changeMonth(by offset: Int) {
        if let next = calendar.date(byAdding: .month, value: offset, to: selectedMonth) {
            selectedMonth = next
        }
    }

    public func isInMonth(_ date: Date, monthReference: Date) -> Bool {
        let c1 = calendar.dateComponents([.year, .month], from: date)
        let c2 = calendar.dateComponents([.year, .month], from: monthReference)
        return c1.year == c2.year && c1.month == c2.month
    }

    public func endOfMonth(for monthReference: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: monthReference)
        guard let startOfMonth = calendar.date(from: comps),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth),
              let lastMoment = calendar.date(byAdding: .second, value: -1, to: nextMonth) else {
            return monthReference
        }
        return lastMoment
    }

    // MARK: - Account Management

    public func addAccount(
        name: String,
        bankPresetId: String?,
        customImagePath: String?,
        iconSymbol: String,
        colorHex: String,
        initialBalance: Double,
        agency: String = "",
        accountNumber: String = ""
    ) {
        let account = BankAccount(
            name: name,
            bankPresetId: bankPresetId,
            customImagePath: customImagePath,
            iconSymbol: iconSymbol,
            colorHex: colorHex,
            initialBalance: initialBalance,
            agency: agency,
            accountNumber: accountNumber
        )
        accounts.append(account)
        save()
    }

    public func updateAccount(_ account: BankAccount) {
        if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[idx] = account
            save()
        }
    }

    public func deleteAccount(_ accountId: UUID) {
        accounts.removeAll(where: { $0.id == accountId })
        save()
    }

    public func account(for id: UUID) -> BankAccount? {
        accounts.first(where: { $0.id == id })
    }

    // MARK: - Category Management

    public func categories(for type: TransactionType) -> [CategoryItem] {
        categories.filter { $0.type == type }
    }

    public func category(for id: UUID) -> CategoryItem? {
        categories.first(where: { $0.id == id })
    }

    public func fallbackCategoryId(for type: TransactionType, matchingSubstring: String? = nil) -> UUID {
        if let sub = matchingSubstring,
           let matched = categories.first(where: { $0.type == type && $0.name.localizedCaseInsensitiveContains(sub) }) {
            return matched.id
        }
        return categories(for: type).first?.id ?? categories.first?.id ?? UUID()
    }

    public func addCategory(name: String, type: TransactionType, iconSymbol: String, colorHex: String, keywords: [String] = []) {
        let item = CategoryItem(
            name: name,
            type: type,
            iconSymbol: iconSymbol,
            colorHex: colorHex,
            keywords: keywords,
            isSystemDefault: false
        )
        categories.append(item)
        save()
    }

    public func updateCategory(_ category: CategoryItem) {
        if let idx = categories.firstIndex(where: { $0.id == category.id }) {
            categories[idx] = category
            save()
        }
    }

    public func deleteCategory(_ categoryId: UUID) {
        categories.removeAll(where: { $0.id == categoryId })
        save()
    }

    // MARK: - Transaction Creation (Single, Installment, Repeated)

    @discardableResult
    public func createTransaction(
        name: String,
        details: String = "",
        amount: Double,
        date: Date,
        type: TransactionType,
        isPaid: Bool = true,
        categoryId: UUID,
        accountId: UUID,
        attachmentPath: String? = nil,
        attachmentName: String? = nil,
        ignoreInConsolidated: Bool = false,
        recurrenceMode: TransactionRecurrenceMode = .single,
        installmentsOrMonthsCount: Int = 1
    ) -> [FinancialTransaction] {
        var created: [FinancialTransaction] = []
        let cleanAmount = abs(amount)

        if type == .income || recurrenceMode == .single || installmentsOrMonthsCount <= 1 {
            let tx = FinancialTransaction(
                name: name,
                details: details,
                amount: cleanAmount,
                date: date,
                type: type,
                isPaid: isPaid,
                categoryId: categoryId,
                accountId: accountId,
                attachmentPath: attachmentPath,
                attachmentName: attachmentName,
                ignoreInConsolidated: ignoreInConsolidated,
                recurrenceMode: .single
            )
            transactions.append(tx)
            created.append(tx)
        } else if recurrenceMode == .installment {
            // Parcelada: receives total full value (`cleanAmount`) and number of installments (`count`)
            let count = max(installmentsOrMonthsCount, 2)
            let groupId = UUID()
            let baseInstallment = ((cleanAmount / Double(count)) * 100.0).rounded(.down) / 100.0
            let remainder = ((cleanAmount - (baseInstallment * Double(count))) * 100.0).rounded() / 100.0

            for index in 0..<count {
                let installmentDate = calendar.date(byAdding: .month, value: index, to: date) ?? date
                let value = index == 0 ? (baseInstallment + remainder) : baseInstallment
                let paidStatus = index == 0 ? isPaid : false
                let tx = FinancialTransaction(
                    name: "\(name) (\(index + 1)/\(count))",
                    details: details.isEmpty ? "Compra parcelada em \(count)x (Total: \(BRLFormatters.currency(cleanAmount)))" : details,
                    amount: value,
                    date: installmentDate,
                    type: .expense,
                    isPaid: paidStatus,
                    categoryId: categoryId,
                    accountId: accountId,
                    attachmentPath: attachmentPath,
                    attachmentName: attachmentName,
                    ignoreInConsolidated: ignoreInConsolidated,
                    recurrenceMode: .installment,
                    seriesGroupId: groupId,
                    installmentIndex: index + 1,
                    installmentTotal: count
                )
                transactions.append(tx)
                created.append(tx)
            }
        } else if recurrenceMode == .repeated {
            // Repetida: receives number of months (`count`) and repeats the exact same value across those months
            let count = max(installmentsOrMonthsCount, 2)
            let groupId = UUID()
            for index in 0..<count {
                let occurrenceDate = calendar.date(byAdding: .month, value: index, to: date) ?? date
                let paidStatus = index == 0 ? isPaid : false
                let tx = FinancialTransaction(
                    name: name,
                    details: details.isEmpty ? "Despesa recorrente mensal (\(index + 1)/\(count))" : details,
                    amount: cleanAmount,
                    date: occurrenceDate,
                    type: .expense,
                    isPaid: paidStatus,
                    categoryId: categoryId,
                    accountId: accountId,
                    attachmentPath: attachmentPath,
                    attachmentName: attachmentName,
                    ignoreInConsolidated: ignoreInConsolidated,
                    recurrenceMode: .repeated,
                    seriesGroupId: groupId,
                    installmentIndex: index + 1,
                    installmentTotal: count
                )
                transactions.append(tx)
                created.append(tx)
            }
        }

        sortTransactions()
        save()
        return created
    }

    public func updateTransaction(_ updated: FinancialTransaction) {
        if let idx = transactions.firstIndex(where: { $0.id == updated.id }) {
            transactions[idx] = updated
            sortTransactions()
            save()
        }
    }

    public func toggleTransactionPaid(_ id: UUID) {
        if let idx = transactions.firstIndex(where: { $0.id == id }) {
            transactions[idx].isPaid.toggle()
            save()
        }
    }

    public func toggleTransactionIgnoreInConsolidated(_ id: UUID) {
        if let idx = transactions.firstIndex(where: { $0.id == id }) {
            transactions[idx].ignoreInConsolidated.toggle()
            save()
        }
    }

    public func deleteTransaction(_ id: UUID) {
        transactions.removeAll(where: { $0.id == id })
        save()
    }

    private func sortTransactions() {
        transactions.sort { a, b in
            if a.date == b.date {
                return a.createdAt > b.createdAt
            }
            return a.date > b.date
        }
    }

    // MARK: - Statement Import with Deduplication

    public struct ImportSummary {
        public let totalEvaluated: Int
        public let addedCount: Int
        public let skippedDuplicatesCount: Int
        public let addedExpenses: Int
        public let addedIncomes: Int
    }

    public func transactionAlreadyExists(_ candidate: ParsedStatementTransaction, inAccountId accountId: UUID) -> Bool {
        transactions.contains { existing in
            guard existing.accountId == accountId else { return false }
            guard existing.type == candidate.type else { return false }
            guard calendar.isDate(existing.date, inSameDayAs: candidate.date) else { return false }
            guard abs(existing.amount - candidate.amount) < 0.009 else { return false }

            if let existingRaw = existing.rawStatementLine, !existingRaw.isEmpty {
                return existingRaw.caseInsensitiveCompare(candidate.rawLine) == .orderedSame &&
                       existing.statementOccurrenceIndex == candidate.occurrenceIndex
            }

            return existing.name.caseInsensitiveCompare(candidate.cleanTitle) == .orderedSame &&
                   existing.statementOccurrenceIndex == candidate.occurrenceIndex
        }
    }

    public func importParsedTransactions(
        _ parsedList: [ParsedStatementTransaction],
        intoAccountId accountId: UUID,
        filterMode: StatementImportFilterMode
    ) -> ImportSummary {
        let filtered = parsedList.filter { item in
            switch filterMode {
            case .hybrid: return true
            case .expensesOnly: return item.type == .expense
            case .incomesOnly: return item.type == .income
            }
        }

        var added = 0
        var skipped = 0
        var addedExp = 0
        var addedInc = 0

        for item in filtered {
            if transactionAlreadyExists(item, inAccountId: accountId) {
                skipped += 1
                continue
            }

            let fallbackCatId = fallbackCategoryId(for: item.type)
            let tx = FinancialTransaction(
                name: item.cleanTitle,
                details: item.extractedDetails,
                amount: item.amount,
                date: item.date,
                type: item.type,
                isPaid: true,
                categoryId: item.suggestedCategoryId ?? fallbackCatId,
                accountId: accountId,
                ignoreInConsolidated: false,
                recurrenceMode: .single,
                rawStatementLine: item.rawLine,
                statementOccurrenceIndex: item.occurrenceIndex
            )
            transactions.append(tx)
            added += 1
            if item.type == .expense { addedExp += 1 } else { addedInc += 1 }
        }

        sortTransactions()
        save()
        return ImportSummary(
            totalEvaluated: filtered.count,
            addedCount: added,
            skippedDuplicatesCount: skipped,
            addedExpenses: addedExp,
            addedIncomes: addedInc
        )
    }

    // MARK: - Investments Management

    public var investmentGroups: [String] {
        let names = Set(investments.map(\.groupName))
        return Array(names).sorted()
    }

    public func investments(inGroup groupName: String) -> [InvestmentItem] {
        investments.filter { $0.groupName == groupName }
    }

    public func addInvestment(
        name: String,
        groupName: String,
        investmentAccountId: UUID,
        initialBalance: Double = 0.0,
        showInConsolidated: Bool = true,
        iconSymbol: String = "chart.line.uptrend.xyaxis",
        colorHex: String = "#10B981",
        notes: String = ""
    ) {
        let item = InvestmentItem(
            name: name,
            groupName: groupName,
            investmentAccountId: investmentAccountId,
            balance: max(initialBalance, 0),
            showInConsolidated: showInConsolidated,
            iconSymbol: iconSymbol,
            colorHex: colorHex,
            notes: notes
        )
        investments.append(item)
        save()
    }

    public func toggleInvestmentConsolidated(_ investmentId: UUID) {
        if let idx = investments.firstIndex(where: { $0.id == investmentId }) {
            investments[idx].showInConsolidated.toggle()
            save()
        }
    }

    public func deleteInvestment(_ investmentId: UUID) {
        investments.removeAll(where: { $0.id == investmentId })
        save()
    }

    /// Investir (aportar) ou resgatar:
    /// Seleciona de qual conta quer tirar o valor (`sourceAccountId`) e em qual conta está o investimento (`investmentAccountId`),
    /// tirando o valor da conta de origem e adicionando no investimento.
    public func contributeToInvestment(
        investmentId: UUID,
        amount: Double,
        sourceAccountId: UUID,
        investmentAccountId: UUID,
        date: Date = Date(),
        movementType: InvestmentMovementType = .deposit,
        notes: String = ""
    ) {
        guard let idx = investments.firstIndex(where: { $0.id == investmentId }) else { return }
        let cleanAmount = abs(amount)
        guard cleanAmount > 0 else { return }

        investments[idx].investmentAccountId = investmentAccountId

        let investmentName = investments[idx].name
        let groupName = investments[idx].groupName
        let sourceAccountName = account(for: sourceAccountId)?.name ?? "Conta"
        let destAccountName = account(for: investmentAccountId)?.name ?? "Conta Investimento"

        let txType: TransactionType = movementType == .deposit ? .expense : .income
        let categoryId: UUID = {
            if movementType == .deposit {
                return fallbackCategoryId(for: .expense, matchingSubstring: "Aplicações")
            } else {
                return fallbackCategoryId(for: .income, matchingSubstring: "Resgate")
            }
        }()

        let txTitle = movementType == .deposit
            ? "Aporte: \(investmentName) (\(groupName))"
            : "Resgate: \(investmentName) (\(groupName))"
        let txDetails = movementType == .deposit
            ? "Saída de \(sourceAccountName) para investimento em \(destAccountName). \(notes)"
            : "Resgate de \(destAccountName) para \(sourceAccountName). \(notes)"

        let tx = FinancialTransaction(
            name: txTitle,
            details: txDetails.trimmingCharacters(in: .whitespaces),
            amount: cleanAmount,
            date: date,
            type: txType,
            isPaid: true,
            categoryId: categoryId,
            accountId: sourceAccountId,
            ignoreInConsolidated: false,
            recurrenceMode: .single,
            linkedInvestmentId: investmentId
        )
        transactions.append(tx)

        if movementType == .deposit {
            investments[idx].balance += cleanAmount
        } else {
            investments[idx].balance = max(0, investments[idx].balance - cleanAmount)
        }

        let movement = InvestmentMovement(
            type: movementType,
            amount: cleanAmount,
            date: date,
            sourceAccountId: sourceAccountId,
            investmentAccountId: investmentAccountId,
            notes: notes,
            generatedTransactionId: tx.id
        )
        investments[idx].movements.insert(movement, at: 0)

        sortTransactions()
        save()
    }

    // MARK: - Debts Management (Aba Dívidas)

    public var activeDebts: [DebtItem] {
        debts.filter { !$0.isPaid }
    }

    public var paidDebts: [DebtItem] {
        debts.filter { $0.isPaid }
    }

    public func addDebt(
        name: String,
        customImagePath: String?,
        bankPresetId: String?,
        iconSymbol: String,
        colorHex: String,
        originalAmount: Double,
        contractedDate: Date?,
        notes: String = ""
    ) {
        let debt = DebtItem(
            name: name,
            customImagePath: customImagePath,
            bankPresetId: bankPresetId,
            iconSymbol: iconSymbol,
            colorHex: colorHex,
            originalAmount: originalAmount,
            contractedDate: contractedDate,
            notes: notes
        )
        debts.append(debt)
        save()
    }

    public func updateDebt(_ updated: DebtItem) {
        if let idx = debts.firstIndex(where: { $0.id == updated.id }) {
            debts[idx] = updated
            save()
        }
    }

    public func deleteDebt(_ debtId: UUID) {
        debts.removeAll(where: { $0.id == debtId })
        save()
    }

    /// Pagar dívida: seleciona de qual conta vai sair o pagamento, mantém o valor original fixo e recebe o "valor da negociação".
    /// Ao confirmar, cria uma transação para esse pagamento e remove o card da listagem de dívidas ativas.
    public func payDebt(
        debtId: UUID,
        fromAccountId accountId: UUID,
        negotiatedAmount: Double,
        paymentDate: Date = Date()
    ) {
        guard let idx = debts.firstIndex(where: { $0.id == debtId }) else { return }
        let debt = debts[idx]
        let cleanNegotiated = abs(negotiatedAmount)
        let discount = debt.originalAmount - cleanNegotiated

        let debtCategoryId = fallbackCategoryId(for: .expense, matchingSubstring: "Dívidas")

        let discountText = discount > 0.01
            ? " (Desconto na negociação: \(BRLFormatters.currency(discount)) sobre valor original de \(BRLFormatters.currency(debt.originalAmount)))"
            : " (Valor original: \(BRLFormatters.currency(debt.originalAmount)))"

        let tx = FinancialTransaction(
            name: "Pagamento Dívida: \(debt.name)",
            details: "Quitação de dívida negociada\(discountText)",
            amount: cleanNegotiated,
            date: paymentDate,
            type: .expense,
            isPaid: true,
            categoryId: debtCategoryId,
            accountId: accountId,
            ignoreInConsolidated: false,
            recurrenceMode: .single,
            linkedDebtId: debt.id
        )
        transactions.append(tx)

        debts[idx].isPaid = true
        debts[idx].negotiatedAmount = cleanNegotiated
        debts[idx].paidDate = paymentDate
        debts[idx].paidFromAccountId = accountId
        debts[idx].paymentTransactionId = tx.id

        sortTransactions()
        save()
    }

    // MARK: - Loans (Empréstimos) & Financings (Financiamentos)

    public func activeContracts(for kind: CreditContractKind) -> [CreditContract] {
        contracts.filter { $0.kind == kind && !$0.isSettled }
    }

    public func settledContracts(for kind: CreditContractKind) -> [CreditContract] {
        contracts.filter { $0.kind == kind && $0.isSettled }
    }

    /// Calcula quantas parcelas ocorreram no passado caso `startDate` seja anterior a `referenceDate`,
    /// e retorna a data da próxima cobrança futura com base na data atual e no `billingDay`.
    public func computePastInstallmentsAndFirstFutureDate(
        startDate: Date?,
        billingDay: Int,
        totalInstallments: Int,
        referenceDate: Date = Date()
    ) -> (pastInstallmentsCount: Int, firstFutureBillingDate: Date) {
        let clampedDay = min(max(billingDay, 1), 28)
        let todayStart = calendar.startOfDay(for: referenceDate)

        // Determina a próxima data de cobrança a partir de hoje (inclusive hoje ou no próximo mês)
        var currentComps = calendar.dateComponents([.year, .month, .day], from: todayStart)
        currentComps.day = clampedDay
        var nextBillingDate = calendar.date(from: currentComps) ?? todayStart
        if nextBillingDate < todayStart {
            nextBillingDate = calendar.date(byAdding: .month, value: 1, to: nextBillingDate) ?? nextBillingDate
        }

        guard let startDate else {
            return (0, nextBillingDate)
        }

        let startDay = calendar.startOfDay(for: startDate)
        if startDay >= todayStart {
            // Data de início é hoje ou no futuro: nenhuma parcela ficou no passado
            var startComps = calendar.dateComponents([.year, .month], from: startDay)
            startComps.day = clampedDay
            var firstDate = calendar.date(from: startComps) ?? startDay
            if firstDate < startDay {
                firstDate = calendar.date(byAdding: .month, value: 1, to: firstDate) ?? firstDate
            }
            return (0, firstDate)
        }

        // Data de início está no passado: contamos quantas datas de cobrança já passaram estritamente antes de `todayStart`
        var firstInstallmentComps = calendar.dateComponents([.year, .month], from: startDay)
        firstInstallmentComps.day = clampedDay
        var cursorDate = calendar.date(from: firstInstallmentComps) ?? startDay
        if cursorDate < startDay {
            cursorDate = calendar.date(byAdding: .month, value: 1, to: cursorDate) ?? cursorDate
        }

        var elapsed = 0
        while cursorDate < todayStart && elapsed < totalInstallments {
            elapsed += 1
            cursorDate = calendar.date(byAdding: .month, value: 1, to: cursorDate) ?? cursorDate
        }

        return (min(elapsed, totalInstallments), cursorDate)
    }

    @discardableResult
    public func createCreditContract(
        kind: CreditContractKind,
        name: String,
        loanSubtype: LoanSubtype? = .consignado,
        financingSubtype: FinancingSubtype? = .imovel,
        amortizationSystem: AmortizationSystem = .price,
        totalContractedAmount: Double,
        installmentAmount: Double,
        billingDay: Int,
        totalInstallments: Int,
        monthlyInterestRate: Double,
        startDate: Date?,
        accountId: UUID,
        notes: String = "",
        referenceDate: Date = Date()
    ) -> CreditContract {
        let creditCategoryId = fallbackCategoryId(for: .expense, matchingSubstring: "Empréstimos")

        let scheduleInfo = computePastInstallmentsAndFirstFutureDate(
            startDate: startDate,
            billingDay: billingDay,
            totalInstallments: totalInstallments,
            referenceDate: referenceDate
        )

        let contract = CreditContract(
            kind: kind,
            name: name,
            loanSubtype: kind == .loan ? (loanSubtype ?? .consignado) : nil,
            financingSubtype: kind == .financing ? (financingSubtype ?? .imovel) : nil,
            amortizationSystem: amortizationSystem,
            totalContractedAmount: totalContractedAmount,
            installmentAmount: installmentAmount,
            billingDay: billingDay,
            totalInstallments: totalInstallments,
            monthlyInterestRate: monthlyInterestRate,
            startDate: startDate,
            accountId: accountId,
            categoryId: creditCategoryId,
            pastInstallmentsElapsedAtCreation: scheduleInfo.pastInstallmentsCount,
            notes: notes
        )
        contracts.append(contract)

        // Gera APENAS as transações futuras a partir da data atual e dia da cobrança
        let remainingToCreate = max(totalInstallments - scheduleInfo.pastInstallmentsCount, 0)
        for offset in 0..<remainingToCreate {
            let installmentNumber = scheduleInfo.pastInstallmentsCount + offset + 1
            let dueDate = calendar.date(byAdding: .month, value: offset, to: scheduleInfo.firstFutureBillingDate)
                ?? scheduleInfo.firstFutureBillingDate
            let tx = FinancialTransaction(
                name: "\(name) - Parcela \(installmentNumber)/\(totalInstallments)",
                details: "\(contract.kind.title) (\(contract.subtypeDisplayName)) • Juros \(String(format: "%.2f", monthlyInterestRate))% a.m.",
                amount: installmentAmount,
                date: dueDate,
                type: .expense,
                isPaid: false,
                categoryId: creditCategoryId,
                accountId: accountId,
                ignoreInConsolidated: false,
                recurrenceMode: .installment,
                seriesGroupId: contract.id,
                installmentIndex: installmentNumber,
                installmentTotal: totalInstallments,
                linkedContractId: contract.id
            )
            transactions.append(tx)
        }

        sortTransactions()
        save()
        return contract
    }

    public func unpaidTransactions(forContract contractId: UUID) -> [FinancialTransaction] {
        transactions
            .filter { $0.linkedContractId == contractId && !$0.isPaid }
            .sorted { $0.date < $1.date }
    }

    public func paidTransactionsCount(forContract contract: CreditContract) -> Int {
        let paidInApp = transactions.filter { $0.linkedContractId == contract.id && $0.isPaid && $0.installmentIndex != nil }.count
        return min(contract.pastInstallmentsElapsedAtCreation + paidInApp, contract.totalInstallments)
    }

    public func remainingInstallmentsCount(for contract: CreditContract) -> Int {
        guard !contract.isSettled else { return 0 }
        let unpaid = unpaidTransactions(forContract: contract.id).count
        if unpaid > 0 { return unpaid }
        return max(contract.totalInstallments - paidTransactionsCount(forContract: contract), 0)
    }

    public func remainingNominalAmount(for contract: CreditContract) -> Double {
        guard !contract.isSettled else { return 0 }
        let unpaidTxs = unpaidTransactions(forContract: contract.id)
        if !unpaidTxs.isEmpty {
            return unpaidTxs.reduce(0) { $0 + $1.amount }
        }
        return Double(remainingInstallmentsCount(for: contract)) * contract.installmentAmount
    }

    /// Calcula a "Projeção de valor para quitar" trazendo as parcelas futuras a valor presente (desconto proporcional de juros futuros)
    /// considerando a taxa de juros do contrato, o sistema de amortização (PRICE ou SAC) e o tipo do empréstimo/financiamento.
    public func projectedPayoffAmount(for contract: CreditContract) -> Double {
        guard !contract.isSettled else { return 0.0 }
        let n = remainingInstallmentsCount(for: contract)
        guard n > 0 else { return 0.0 }

        let pmt = contract.installmentAmount
        let nominalRemaining = Double(n) * pmt
        let i = contract.monthlyInterestRate / 100.0

        guard i > 0.0001 else {
            return max(nominalRemaining, 0)
        }

        // Valor Presente pelo sistema PRICE: PV = PMT * (1 - (1 + i)^(-n)) / i
        let pvPrice = pmt * (1.0 - pow(1.0 + i, -Double(n))) / i

        switch contract.amortizationSystem {
        case .price:
            if contract.kind == .loan, let subtype = contract.loanSubtype {
                let discount = max(nominalRemaining - pvPrice, 0) * subtype.discountFactorMultiplier
                return max(nominalRemaining - discount, 0)
            }
            return min(pvPrice, nominalRemaining)
        case .sac:
            // Em SAC, a amortização mensal de principal é constante e os juros incidem sobre o saldo devedor
            let proportionalPrincipal = contract.totalContractedAmount * (Double(n) / Double(max(contract.totalInstallments, 1)))
            let estimatedPrincipal = min(max(proportionalPrincipal - contract.extraAmortizedTotal, pvPrice * 0.92), nominalRemaining)
            return max(estimatedPrincipal, 0)
        }
    }

    /// Amortizar empréstimo/financiamento: registra pagamento na conta escolhida e recalcula parcelas futuras
    public func amortizeContract(
        contractId: UUID,
        amountPaid: Double,
        accountId: UUID,
        date: Date = Date(),
        mode: AmortizationRecalculationMode,
        customNewInstallmentAmount: Double? = nil,
        customNewRemainingInstallments: Int? = nil,
        notes: String = ""
    ) {
        guard let idx = contracts.firstIndex(where: { $0.id == contractId }) else { return }
        var contract = contracts[idx]
        let cleanPaid = abs(amountPaid)
        guard cleanPaid > 0 else { return }

        let prevRemaining = remainingInstallmentsCount(for: contract)
        let prevInstallment = contract.installmentAmount
        let currentPV = max(projectedPayoffAmount(for: contract), cleanPaid)
        let newPV = max(currentPV - cleanPaid, 0)
        let i = contract.monthlyInterestRate / 100.0

        var newInstallment = prevInstallment
        var newRemaining = prevRemaining

        if newPV <= 0.01 {
            newRemaining = 0
            newInstallment = 0
        } else {
            switch mode {
            case .reduceTerm:
                if let customCount = customNewRemainingInstallments, customCount > 0 {
                    newRemaining = min(customCount, prevRemaining)
                } else if i > 0.0001 && prevInstallment > newPV * i {
                    // n = -ln(1 - (PV * i) / PMT) / ln(1 + i)
                    let ratio = 1.0 - (newPV * i) / prevInstallment
                    let calcN = Int(ceil(-log(max(ratio, 0.0001)) / log(1.0 + i)))
                    newRemaining = max(1, min(calcN, prevRemaining))
                } else {
                    newRemaining = max(1, Int(ceil(newPV / max(prevInstallment, 1))))
                }
                if let customInst = customNewInstallmentAmount, customInst > 0 {
                    newInstallment = customInst
                }
            case .reduceInstallment:
                if let customInst = customNewInstallmentAmount, customInst > 0 {
                    newInstallment = customInst
                } else if i > 0.0001 && prevRemaining > 0 {
                    // PMT = PV * i / (1 - (1 + i)^(-n))
                    newInstallment = newPV * i / (1.0 - pow(1.0 + i, -Double(prevRemaining)))
                } else if prevRemaining > 0 {
                    newInstallment = newPV / Double(prevRemaining)
                }
                if let customCount = customNewRemainingInstallments, customCount > 0 {
                    newRemaining = customCount
                }
            }
        }

        // Cria transação de saída na conta selecionada
        let amortTx = FinancialTransaction(
            name: "Amortização: \(contract.name)",
            details: "Amortização extraordinária (\(mode.rawValue)). \(notes)".trimmingCharacters(in: .whitespaces),
            amount: cleanPaid,
            date: date,
            type: .expense,
            isPaid: true,
            categoryId: contract.categoryId,
            accountId: accountId,
            ignoreInConsolidated: false,
            recurrenceMode: .single,
            linkedContractId: contract.id
        )
        transactions.append(amortTx)

        // Atualiza as parcelas futuras em aberto
        let unpaidList = unpaidTransactions(forContract: contract.id)
        if newRemaining == 0 {
            let idsToRemove = Set(unpaidList.map(\.id))
            transactions.removeAll { idsToRemove.contains($0.id) }
            contract.isSettled = true
            contract.settledAmount = cleanPaid
            contract.settledDate = date
            contract.settledAccountId = accountId
        } else {
            // Se reduziu prazo, remove as últimas parcelas futuras excedentes
            if newRemaining < unpaidList.count {
                let toRemove = unpaidList.suffix(unpaidList.count - newRemaining)
                let removeIds = Set(toRemove.map(\.id))
                transactions.removeAll { removeIds.contains($0.id) }
            }
            // Atualiza o valor das parcelas futuras restantes
            let remainingUnpaidIds = Set(unpaidTransactions(forContract: contract.id).map(\.id))
            let newTotalInstallments = contract.totalInstallments - max(0, prevRemaining - newRemaining)
            contract.totalInstallments = max(newTotalInstallments, 1)
            contract.installmentAmount = newInstallment

            for tIdx in transactions.indices {
                if remainingUnpaidIds.contains(transactions[tIdx].id) {
                    transactions[tIdx].amount = newInstallment
                    transactions[tIdx].installmentTotal = contract.totalInstallments
                    if let instIdx = transactions[tIdx].installmentIndex {
                        transactions[tIdx].name = "\(contract.name) - Parcela \(instIdx)/\(contract.totalInstallments)"
                    }
                }
            }
        }

        contract.extraAmortizedTotal += cleanPaid
        let record = AmortizationRecord(
            date: date,
            amountPaid: cleanPaid,
            mode: mode,
            previousInstallmentAmount: prevInstallment,
            newInstallmentAmount: newInstallment,
            previousRemainingInstallments: prevRemaining,
            newRemainingInstallments: newRemaining,
            accountId: accountId,
            transactionId: amortTx.id,
            notes: notes
        )
        contract.amortizationHistory.insert(record, at: 0)
        contracts[idx] = contract

        sortTransactions()
        save()
    }

    /// Quitar empréstimo/financiamento: cria transação de quitação na conta selecionada e remove parcelas futuras
    public func settleContract(
        contractId: UUID,
        finalPayoffAmount: Double,
        accountId: UUID,
        date: Date = Date()
    ) {
        guard let idx = contracts.firstIndex(where: { $0.id == contractId }) else { return }
        var contract = contracts[idx]
        let cleanFinal = abs(finalPayoffAmount)
        let originalProjected = projectedPayoffAmount(for: contract)
        let nominalRemaining = remainingNominalAmount(for: contract)

        // Remove todas as parcelas futuras ainda não pagas
        let unpaidIds = Set(unpaidTransactions(forContract: contract.id).map(\.id))
        transactions.removeAll { unpaidIds.contains($0.id) }

        // Cria a transação de quitação na conta selecionada
        let settleTx = FinancialTransaction(
            name: "Quitação: \(contract.name)",
            details: "Quitação integral de \(contract.kind.title.lowercased()) (Saldo nominal: \(BRLFormatters.currency(nominalRemaining)), Projetado: \(BRLFormatters.currency(originalProjected)))",
            amount: cleanFinal,
            date: date,
            type: .expense,
            isPaid: true,
            categoryId: contract.categoryId,
            accountId: accountId,
            ignoreInConsolidated: false,
            recurrenceMode: .single,
            linkedContractId: contract.id
        )
        transactions.append(settleTx)

        contract.isSettled = true
        contract.settledAmount = cleanFinal
        contract.settledDate = date
        contract.settledAccountId = accountId
        contracts[idx] = contract

        sortTransactions()
        save()
    }

    public func deleteContract(_ contractId: UUID) {
        transactions.removeAll { $0.linkedContractId == contractId && !$0.isPaid }
        contracts.removeAll { $0.id == contractId }
        save()
    }

    // MARK: - Balances, Monthly Summaries & Insights

    public func transactionsForMonth(_ monthReference: Date) -> [FinancialTransaction] {
        transactions
            .filter { isInMonth($0.date, monthReference: monthReference) }
            .sorted { a, b in
                if a.date == b.date { return a.createdAt > b.createdAt }
                return a.date > b.date
            }
    }

    public func monthlyIncome(for monthReference: Date, onlyPaid: Bool = false) -> Double {
        transactionsForMonth(monthReference)
            .filter { $0.type == .income && !$0.ignoreInConsolidated && (!onlyPaid || $0.isPaid) }
            .reduce(0) { $0 + $1.amount }
    }

    public func monthlyExpense(for monthReference: Date, onlyPaid: Bool = false) -> Double {
        transactionsForMonth(monthReference)
            .filter { $0.type == .expense && !$0.ignoreInConsolidated && (!onlyPaid || $0.isPaid) }
            .reduce(0) { $0 + $1.amount }
    }

    public func monthlyNetBalance(for monthReference: Date, onlyPaid: Bool = false) -> Double {
        monthlyIncome(for: monthReference, onlyPaid: onlyPaid) - monthlyExpense(for: monthReference, onlyPaid: onlyPaid)
    }

    /// Saldo atual de uma conta específica considerando saldo inicial e transações pagas (não ignoradas no consolidado)
    public func currentBalance(forAccount accountId: UUID, upTo dateLimit: Date? = nil) -> Double {
        guard let acc = account(for: accountId) else { return 0.0 }
        let limit = dateLimit.map { endOfMonth(for: $0) }
        let delta = transactions
            .filter { tx in
                guard tx.accountId == accountId else { return false }
                guard !tx.ignoreInConsolidated else { return false }
                if let limit {
                    return tx.date <= limit && (tx.isPaid || tx.date <= limit)
                } else {
                    return tx.isPaid
                }
            }
            .reduce(0.0) { $0 + $1.signedAmount }
        return acc.initialBalance + delta
    }

    /// Saldo acumulado consolidado até o fim do mês informado (`monthReference`),
    /// incluindo saldo inicial das contas + movimentações até aquele mês + investimentos marcados com "Exibir no consolidado".
    public func accumulatedConsolidatedBalance(throughMonth monthReference: Date, includeProjectedUnpaid: Bool = true) -> Double {
        let cutoff = endOfMonth(for: monthReference)
        let initialAccountsSum = accounts.reduce(0.0) { $0 + $1.initialBalance }
        let transactionsDelta = transactions
            .filter { tx in
                guard !tx.ignoreInConsolidated else { return false }
                guard tx.date <= cutoff else { return false }
                return includeProjectedUnpaid ? true : tx.isPaid
            }
            .reduce(0.0) { $0 + $1.signedAmount }

        let consolidatedInvestmentsSum = investments
            .filter(\.showInConsolidated)
            .reduce(0.0) { $0 + $1.balance }

        return initialAccountsSum + transactionsDelta + consolidatedInvestmentsSum
    }

    public var totalCheckingBalanceNow: Double {
        accounts.reduce(0.0) { $0 + currentBalance(forAccount: $1.id) }
    }

    public var totalInvestmentsBalance: Double {
        investments.reduce(0.0) { $0 + $1.balance }
    }

    public var consolidatedInvestmentsBalance: Double {
        investments.filter(\.showInConsolidated).reduce(0.0) { $0 + $1.balance }
    }

    public var totalConsolidatedPatrimonyNow: Double {
        totalCheckingBalanceNow + consolidatedInvestmentsBalance
    }

    // MARK: - Category Breakdown for Charts

    public func categoryBreakdown(for monthReference: Date, type: TransactionType) -> [CategorySpendSummary] {
        let monthTxs = transactionsForMonth(monthReference)
            .filter { $0.type == type && !$0.ignoreInConsolidated }
        let grandTotal = monthTxs.reduce(0.0) { $0 + $1.amount }
        guard grandTotal > 0 else { return [] }

        var grouped: [UUID: (sum: Double, count: Int)] = [:]
        for tx in monthTxs {
            let current = grouped[tx.categoryId] ?? (0.0, 0)
            grouped[tx.categoryId] = (current.sum + tx.amount, current.count + 1)
        }

        var result: [CategorySpendSummary] = []
        for (catId, info) in grouped {
            let cat = category(for: catId) ?? CategoryItem(
                id: catId,
                name: "Outros",
                type: type,
                iconSymbol: "tag.fill",
                colorHex: "#64748B"
            )
            result.append(
                CategorySpendSummary(
                    category: cat,
                    total: info.sum,
                    percentage: (info.sum / grandTotal) * 100.0,
                    count: info.count
                )
            )
        }

        return result.sorted { $0.total > $1.total }
    }

    public func cashFlowSeries(around centerMonth: Date, monthsBack: Int = 3, monthsForward: Int = 4) -> [MonthlyCashFlowPoint] {
        var points: [MonthlyCashFlowPoint] = []
        for offset in (-monthsBack)...monthsForward {
            if let mDate = calendar.date(byAdding: .month, value: offset, to: centerMonth) {
                let inc = monthlyIncome(for: mDate)
                let exp = monthlyExpense(for: mDate)
                let acc = accumulatedConsolidatedBalance(throughMonth: mDate, includeProjectedUnpaid: true)
                points.append(
                    MonthlyCashFlowPoint(
                        monthDate: mDate,
                        label: BRLFormatters.shortMonthYearFormatter.string(from: mDate).capitalized,
                        income: inc,
                        expense: exp,
                        net: inc - exp,
                        accumulatedBalance: acc
                    )
                )
            }
        }
        return points
    }

    // MARK: - Comprehensive Dashboard Debt Breakdown

    public func buildComprehensiveDebtSummary(referenceDate: Date = Date()) -> ComprehensiveDebtSummary {
        let currentMonthUnpaid = transactions.filter { tx in
            tx.type == .expense && !tx.isPaid && !tx.ignoreInConsolidated && isInMonth(tx.date, monthReference: referenceDate)
        }

        let endOfCurrentMonth = endOfMonth(for: referenceDate)
        let futureRegularUnpaid = transactions.filter { tx in
            tx.type == .expense &&
            !tx.isPaid &&
            !tx.ignoreInConsolidated &&
            tx.date > endOfCurrentMonth &&
            tx.linkedContractId == nil
        }

        let openDebts = activeDebts
        let openLoans = activeContracts(for: .loan)
        let openFinancings = activeContracts(for: .financing)

        let currentMonthUnpaidSum = currentMonthUnpaid.reduce(0.0) { $0 + $1.amount }
        let futureRegularSum = futureRegularUnpaid.reduce(0.0) { $0 + $1.amount }
        let debtsSum = openDebts.reduce(0.0) { $0 + $1.originalAmount }

        let loansNominalSum = openLoans.reduce(0.0) { $0 + remainingNominalAmount(for: $1) }
        let loansProjectedSum = openLoans.reduce(0.0) { $0 + projectedPayoffAmount(for: $1) }

        let financingsNominalSum = openFinancings.reduce(0.0) { $0 + remainingNominalAmount(for: $1) }
        let financingsProjectedSum = openFinancings.reduce(0.0) { $0 + projectedPayoffAmount(for: $1) }

        var items: [DebtLineItem] = []

        for tx in currentMonthUnpaid {
            items.append(
                DebtLineItem(
                    id: tx.id,
                    title: tx.name,
                    subtitle: "Transação pendente do mês atual (\(BRLFormatters.shortDate(tx.date)))",
                    section: "Transações Atuais",
                    nominalAmount: tx.amount,
                    projectedPayoffAmount: tx.amount,
                    iconSymbol: "calendar.badge.exclamationmark",
                    colorHex: "#F59E0B"
                )
            )
        }

        for tx in futureRegularUnpaid {
            items.append(
                DebtLineItem(
                    id: tx.id,
                    title: tx.name,
                    subtitle: "Despesa futura agendada para \(BRLFormatters.shortDate(tx.date))",
                    section: "Transações Futuras",
                    nominalAmount: tx.amount,
                    projectedPayoffAmount: tx.amount,
                    iconSymbol: "clock.arrow.circlepath",
                    colorHex: "#3B82F6"
                )
            )
        }

        for debt in openDebts {
            let dateInfo = debt.contractedDate.map { "Contraída em \(BRLFormatters.shortDate($0))" } ?? "Dívida em aberto para negociação"
            items.append(
                DebtLineItem(
                    id: debt.id,
                    title: debt.name,
                    subtitle: dateInfo,
                    section: "Dívidas (Serasa / Acordos)",
                    nominalAmount: debt.originalAmount,
                    projectedPayoffAmount: debt.originalAmount,
                    iconSymbol: debt.iconSymbol,
                    colorHex: debt.colorHex
                )
            )
        }

        for loan in openLoans {
            let remCount = remainingInstallmentsCount(for: loan)
            let nom = remainingNominalAmount(for: loan)
            let proj = projectedPayoffAmount(for: loan)
            items.append(
                DebtLineItem(
                    id: loan.id,
                    title: "\(loan.name) (\(loan.subtypeDisplayName))",
                    subtitle: "\(remCount)x restantes de \(BRLFormatters.currency(loan.installmentAmount)) • Juros \(String(format: "%.2f", loan.monthlyInterestRate))% a.m.",
                    section: "Empréstimos",
                    nominalAmount: nom,
                    projectedPayoffAmount: proj,
                    iconSymbol: loan.iconSymbol,
                    colorHex: "#D97706"
                )
            )
        }

        for fin in openFinancings {
            let remCount = remainingInstallmentsCount(for: fin)
            let nom = remainingNominalAmount(for: fin)
            let proj = projectedPayoffAmount(for: fin)
            items.append(
                DebtLineItem(
                    id: fin.id,
                    title: "\(fin.name) (\(fin.subtypeDisplayName))",
                    subtitle: "\(remCount)x restantes de \(BRLFormatters.currency(fin.installmentAmount)) • Juros \(String(format: "%.2f", fin.monthlyInterestRate))% a.m.",
                    section: "Financiamentos",
                    nominalAmount: nom,
                    projectedPayoffAmount: proj,
                    iconSymbol: fin.iconSymbol,
                    colorHex: "#8B5CF6"
                )
            )
        }

        let grandNominal = currentMonthUnpaidSum + futureRegularSum + debtsSum + loansNominalSum + financingsNominalSum
        let grandProjected = currentMonthUnpaidSum + futureRegularSum + debtsSum + loansProjectedSum + financingsProjectedSum

        return ComprehensiveDebtSummary(
            currentMonthUnpaidTransactions: currentMonthUnpaid,
            futureUnpaidRegularTransactions: futureRegularUnpaid,
            activeDebts: openDebts,
            activeLoans: openLoans,
            activeFinancings: openFinancings,
            currentMonthUnpaidTotal: currentMonthUnpaidSum,
            futureRegularExpensesTotal: futureRegularSum,
            unpaidDebtsTotal: debtsSum,
            loansRemainingNominalTotal: loansNominalSum,
            loansProjectedPayoffTotal: loansProjectedSum,
            financingsRemainingNominalTotal: financingsNominalSum,
            financingsProjectedPayoffTotal: financingsProjectedSum,
            grandTotalNominal: grandNominal,
            grandTotalWithPayoffProjection: grandProjected,
            itemizedLines: items
        )
    }
}
