import Foundation
import SwiftUI

// MARK: - Navigation

public enum SidebarDestination: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case transactions
    case investments
    case loans
    case financings
    case debts
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .transactions: return "Transações"
        case .investments: return "Investimentos"
        case .loans: return "Empréstimos"
        case .financings: return "Financiamentos"
        case .debts: return "Dívidas"
        case .settings: return "Configurações"
        }
    }

    public var subtitle: String {
        switch self {
        case .dashboard: return "Insights, gráficos e visão consolidada"
        case .transactions: return "Receitas e despesas por mês"
        case .investments: return "Carteiras, aportes e resgates"
        case .loans: return "Consignados, pessoais e amortização"
        case .financings: return "Financiamentos de imóvel e carro"
        case .debts: return "Controle e negociação de dívidas em aberto"
        case .settings: return "LLM local, contas e categorias"
        }
    }

    public var icon: String {
        switch self {
        case .dashboard: return "chart.pie.fill"
        case .transactions: return "arrow.left.arrow.right.circle.fill"
        case .investments: return "chart.line.uptrend.xyaxis.circle.fill"
        case .loans: return "banknote.fill"
        case .financings: return "house.and.flag.fill"
        case .debts: return "exclamationmark.shield.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

public enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general = "general"
    case llm = "llm"
    case accounts = "accounts"
    case categories = "categories"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "Gerais"
        case .llm: return "Configuração da LLM"
        case .accounts: return "Contas"
        case .categories: return "Categorias"
        }
    }

    public var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .llm: return "cpu.fill"
        case .accounts: return "building.columns.fill"
        case .categories: return "square.grid.2x2.fill"
        }
    }
}

public enum TransactionsSubmenu: String, CaseIterable, Identifiable, Hashable {
    case all
    case expenses
    case incomes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "Transações"
        case .expenses: return "Despesas"
        case .incomes: return "Receitas"
        }
    }

    public var icon: String {
        switch self {
        case .all: return "arrow.left.arrow.right.circle.fill"
        case .expenses: return "arrow.up.right.circle.fill"
        case .incomes: return "arrow.down.left.circle.fill"
        }
    }
}

public enum DashboardPeriodMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case monthly
    case annual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .monthly: return "Visão Mensal"
        case .annual: return "Visão Anual"
        }
    }
}

public enum ResetDataTarget: String, CaseIterable, Identifiable, Hashable {
    case transactions
    case accounts
    case categories
    case investments
    case loans
    case financings
    case debts
    case aiModelsAndChat

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .transactions: return "Transações (Despesas e Receitas)"
        case .accounts: return "Contas Bancárias"
        case .categories: return "Categorias"
        case .investments: return "Investimentos"
        case .loans: return "Empréstimos"
        case .financings: return "Financiamentos"
        case .debts: return "Dívidas"
        case .aiModelsAndChat: return "Modelos Locais e Histórico da IA"
        }
    }

    public var subtitle: String {
        switch self {
        case .transactions: return "Remove todos os lançamentos passados, atuais e futuros"
        case .accounts: return "Remove todas as contas cadastradas"
        case .categories: return "Remove as categorias atuais da base"
        case .investments: return "Remove todos os grupos e saldos de investimentos"
        case .loans: return "Remove todos os contratos de empréstimos"
        case .financings: return "Remove todos os financiamentos de imóvel e carro"
        case .debts: return "Remove todos os cards de dívidas abertas e quitadas"
        case .aiModelsAndChat: return "Remove modelos baixados e histórico de conversas do chat"
        }
    }

    public var icon: String {
        switch self {
        case .transactions: return "arrow.left.arrow.right.circle.fill"
        case .accounts: return "building.columns.fill"
        case .categories: return "square.grid.2x2.fill"
        case .investments: return "chart.line.uptrend.xyaxis.circle.fill"
        case .loans: return "banknote.fill"
        case .financings: return "house.and.flag.fill"
        case .debts: return "exclamationmark.shield.fill"
        case .aiModelsAndChat: return "cpu.fill"
        }
    }
}

// MARK: - Transaction Types & Recurrence

public enum TransactionType: String, Codable, CaseIterable, Identifiable, Hashable {
    case expense
    case income

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .expense: return "Despesa"
        case .income: return "Receita"
        }
    }

    public var pluralTitle: String {
        switch self {
        case .expense: return "Despesas"
        case .income: return "Receitas"
        }
    }
}

public enum TransactionRecurrenceMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case single
    case installment
    case repeated
    case recurring

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .single: return "Único"
        case .installment: return "Parcelado"
        case .repeated: return "Repetido"
        case .recurring: return "Recorrente"
        }
    }

    public static func availableModes(for type: TransactionType) -> [TransactionRecurrenceMode] {
        switch type {
        case .expense:
            return [.single, .installment, .repeated, .recurring]
        case .income:
            return [.single, .repeated, .recurring]
        }
    }
}

public enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable, Hashable {
    case weekly
    case biweekly
    case monthly
    case bimonthly
    case quarterly
    case semiannual
    case annual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .weekly: return "Semanal"
        case .biweekly: return "Quinzenal"
        case .monthly: return "Mensal (Ex: Netflix, Energia, Água, Wellhub)"
        case .bimonthly: return "Bimestral (A cada 2 meses)"
        case .quarterly: return "Trimestral (A cada 3 meses)"
        case .semiannual: return "Semestral (A cada 6 meses)"
        case .annual: return "Anual (Ex: Prime Video, Anuidade)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .weekly: return "Semanal"
        case .biweekly: return "Quinzenal"
        case .monthly: return "Mensal"
        case .bimonthly: return "Bimestral"
        case .quarterly: return "Trimestral"
        case .semiannual: return "Semestral"
        case .annual: return "Anual"
        }
    }

    public var defaultInitialHorizonCount: Int {
        switch self {
        case .weekly: return 104 // 2 anos
        case .biweekly: return 78 // 3 anos
        case .monthly: return 60 // 5 anos
        case .bimonthly: return 36 // 6 anos
        case .quarterly: return 28 // 7 anos
        case .semiannual: return 20 // 10 anos
        case .annual: return 15 // 15 anos
        }
    }

    public func nextDate(from baseDate: Date, occurrenceIndex: Int, calendar: Calendar = .current) -> Date {
        guard occurrenceIndex > 0 else { return baseDate }
        switch self {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7 * occurrenceIndex, to: baseDate) ?? baseDate
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14 * occurrenceIndex, to: baseDate) ?? baseDate
        case .monthly:
            return calendar.date(byAdding: .month, value: occurrenceIndex, to: baseDate) ?? baseDate
        case .bimonthly:
            return calendar.date(byAdding: .month, value: 2 * occurrenceIndex, to: baseDate) ?? baseDate
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3 * occurrenceIndex, to: baseDate) ?? baseDate
        case .semiannual:
            return calendar.date(byAdding: .month, value: 6 * occurrenceIndex, to: baseDate) ?? baseDate
        case .annual:
            return calendar.date(byAdding: .year, value: occurrenceIndex, to: baseDate) ?? baseDate
        }
    }
}

public enum SeriesEditScope: String, CaseIterable, Identifiable, Hashable {
    case onlyThis
    case thisAndFuture
    case allInSeries

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .allInSeries: return "Alterar em todas as parcelas / ocorrências"
        case .onlyThis: return "Somente nesta transação"
        case .thisAndFuture: return "Da transação atual e todas no futuro"
        }
    }
}

public enum SeriesDeleteScope: String, CaseIterable, Identifiable, Hashable {
    case allInSeries
    case onlyThis
    case thisAndPending

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .allInSeries: return "Remover todas"
        case .onlyThis: return "Remover somente esta"
        case .thisAndPending: return "Remover esta e as pendentes"
        }
    }
}

public enum TransactionSortOrder: String, Codable, CaseIterable, Identifiable, Hashable {
    case dateAscending
    case dateDescending
    case amountAscending
    case amountDescending

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dateAscending: return "Data Crescente"
        case .dateDescending: return "Data Decrescente"
        case .amountAscending: return "Valor Crescente"
        case .amountDescending: return "Valor Decrescente"
        }
    }

    public func sort(_ transactions: [FinancialTransaction]) -> [FinancialTransaction] {
        transactions.sorted { a, b in
            switch self {
            case .dateAscending:
                if a.date == b.date { return a.createdAt < b.createdAt }
                return a.date < b.date
            case .dateDescending:
                if a.date == b.date { return a.createdAt > b.createdAt }
                return a.date > b.date
            case .amountAscending:
                if abs(a.amount - b.amount) < 0.001 { return a.date < b.date }
                return a.amount < b.amount
            case .amountDescending:
                if abs(a.amount - b.amount) < 0.001 { return a.date > b.date }
                return a.amount > b.amount
            }
        }
    }
}

public enum StatementImportFilterMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case hybrid
    case expensesOnly
    case incomesOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hybrid: return "Híbrido (Receitas e Despesas)"
        case .expensesOnly: return "Apenas Despesas"
        case .incomesOnly: return "Apenas Receitas"
        }
    }
}

// MARK: - Bank Account & Presets

public struct BankPreset: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let shortCode: String
    public let monogram: String
    public let primaryHex: String
    public let secondaryHex: String
    public let symbolName: String

    public init(
        id: String,
        name: String,
        shortCode: String,
        monogram: String,
        primaryHex: String,
        secondaryHex: String,
        symbolName: String
    ) {
        self.id = id
        self.name = name
        self.shortCode = shortCode
        self.monogram = monogram
        self.primaryHex = primaryHex
        self.secondaryHex = secondaryHex
        self.symbolName = symbolName
    }
}

public struct BankAccount: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var bankPresetId: String?
    public var customImagePath: String?
    public var iconSymbol: String
    public var colorHex: String
    public var initialBalance: Double
    public var agency: String
    public var accountNumber: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        bankPresetId: String? = nil,
        customImagePath: String? = nil,
        iconSymbol: String = "building.columns.fill",
        colorHex: String = "#EC7000",
        initialBalance: Double = 0.0,
        agency: String = "",
        accountNumber: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.bankPresetId = bankPresetId
        self.customImagePath = customImagePath
        self.iconSymbol = iconSymbol
        self.colorHex = colorHex
        self.initialBalance = initialBalance
        self.agency = agency
        self.accountNumber = accountNumber
        self.createdAt = createdAt
    }
}

// MARK: - Category

public struct CategoryItem: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var type: TransactionType
    public var iconSymbol: String
    public var colorHex: String
    public var keywords: [String]
    public var isSystemDefault: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        type: TransactionType,
        iconSymbol: String,
        colorHex: String,
        keywords: [String] = [],
        isSystemDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.iconSymbol = iconSymbol
        self.colorHex = colorHex
        self.keywords = keywords
        self.isSystemDefault = isSystemDefault
    }
}

// MARK: - Financial Transaction

/// Identifica a origem relacional e de domínio de uma transação financeira para permitir rollback e reversão de estado.
public enum TransactionOrigin: String, Codable, CaseIterable, Identifiable, Hashable {
    case standard
    case financingAmortization
    case loanAmortization
    case loanPayoff
    case contractSettlement
    case investmentDeposit
    case investmentRedemption
    case debtPayment
    case quotaAllocation
    case internalTransfer

    public var id: String { rawValue }
}

public struct FinancialTransaction: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var details: String
    public var amount: Double
    public var date: Date
    public var type: TransactionType
    public var isPaid: Bool
    public var categoryId: UUID
    public var accountId: UUID
    public var attachmentPath: String?
    public var attachmentName: String?
    public var ignoreInConsolidated: Bool
    public var recurrenceMode: TransactionRecurrenceMode
    public var recurrenceFrequency: RecurrenceFrequency?
    public var isCanceledRecurringSeries: Bool?
    public var seriesGroupId: UUID?
    public var installmentIndex: Int?
    public var installmentTotal: Int?
    public var rawStatementLine: String?
    public var statementOccurrenceIndex: Int
    public var linkedContractId: UUID?
    public var linkedInvestmentId: UUID?
    public var linkedDebtId: UUID?
    public var linkedQuotaId: UUID?
    public var linkedQuotaUnits: Int?
    public var linkedQuotaYearMonthKey: Int?
    public var transactionOrigin: TransactionOrigin?
    public var linkedEntityID: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
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
        recurrenceFrequency: RecurrenceFrequency? = nil,
        isCanceledRecurringSeries: Bool? = nil,
        seriesGroupId: UUID? = nil,
        installmentIndex: Int? = nil,
        installmentTotal: Int? = nil,
        rawStatementLine: String? = nil,
        statementOccurrenceIndex: Int = 1,
        linkedContractId: UUID? = nil,
        linkedInvestmentId: UUID? = nil,
        linkedDebtId: UUID? = nil,
        linkedQuotaId: UUID? = nil,
        linkedQuotaUnits: Int? = nil,
        linkedQuotaYearMonthKey: Int? = nil,
        transactionOrigin: TransactionOrigin? = nil,
        linkedEntityID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.amount = abs(amount)
        self.date = date
        self.type = type
        self.isPaid = isPaid
        self.categoryId = categoryId
        self.accountId = accountId
        self.attachmentPath = attachmentPath
        self.attachmentName = attachmentName
        self.ignoreInConsolidated = ignoreInConsolidated
        self.recurrenceMode = recurrenceMode
        self.recurrenceFrequency = recurrenceFrequency
        self.isCanceledRecurringSeries = isCanceledRecurringSeries
        self.seriesGroupId = seriesGroupId
        self.installmentIndex = installmentIndex
        self.installmentTotal = installmentTotal
        self.rawStatementLine = rawStatementLine
        self.statementOccurrenceIndex = statementOccurrenceIndex
        self.linkedContractId = linkedContractId
        self.linkedInvestmentId = linkedInvestmentId
        self.linkedDebtId = linkedDebtId
        self.linkedQuotaId = linkedQuotaId
        self.linkedQuotaUnits = linkedQuotaUnits
        self.linkedQuotaYearMonthKey = linkedQuotaYearMonthKey
        self.transactionOrigin = transactionOrigin
        self.linkedEntityID = linkedEntityID ?? linkedContractId ?? linkedInvestmentId ?? linkedDebtId ?? linkedQuotaId
        self.createdAt = createdAt
    }

    /// Origem relacional efetiva da transação (explícita ou inferida dos vínculos de domínio)
    public var effectiveOrigin: TransactionOrigin {
        if let explicit = transactionOrigin { return explicit }
        if linkedDebtId != nil { return .debtPayment }
        if linkedInvestmentId != nil {
            return type == .income ? .investmentRedemption : .investmentDeposit
        }
        if linkedContractId != nil {
            if installmentIndex == nil {
                if name.localizedCaseInsensitiveContains("quitação") || name.localizedCaseInsensitiveContains("quitacao") {
                    return .contractSettlement
                }
                return .financingAmortization
            }
        }
        if linkedQuotaId != nil { return .quotaAllocation }
        return .standard
    }

    /// ID da entidade financeira vinculada (Contrato, Investimento ou Dívida)
    public var effectiveLinkedEntityID: UUID? {
        linkedEntityID ?? linkedContractId ?? linkedInvestmentId ?? linkedDebtId ?? linkedQuotaId
    }

    public var signedAmount: Double {
        type == .income ? amount : -amount
    }

    public var installmentBadge: String? {
        if recurrenceMode == .recurring {
            return nil
        }
        if let idx = installmentIndex, let total = installmentTotal, total > 1 {
            return "\(idx)/\(total)"
        }
        return nil
    }

    public var isPartOfSeries: Bool {
        seriesGroupId != nil || recurrenceMode != .single
    }

    /// Identifica se a receita possui natureza extraordinária (ex: 13º salário, bônus, PLR, restituição de IR, rescisão).
    public var isExtraordinaryIncome: Bool {
        guard type == .income else { return false }
        let text = "\(name) \(details) \(rawStatementLine ?? "")"
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let keywords = [
            "13", "decimo terceiro", "bonus", "plr",
            "participacao nos lucros", "restituicao", "rescisao",
            "extraordinari", "heranca", "premio", "premiacao"
        ]
        return keywords.contains { text.contains($0) }
    }

    /// Identifica se a despesa é de natureza fixa / recorrente (assinaturas, financiamento, aluguel, condomínio, etc.)
    public var isFixedExpense: Bool {
        guard type == .expense else { return false }
        if recurrenceMode == .recurring { return true }
        if linkedContractId != nil { return true }
        let text = "\(name) \(details)"
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let keywords = ["fixa", "fixo", "recorrente", "assinatura", "aluguel", "condominio", "plano", "mensalidade", "prestacao", "parcela"]
        return keywords.contains { text.contains($0) }
    }

    /// Despesas de consumo variável / avulsas
    public var isVariableExpense: Bool {
        guard type == .expense else { return false }
        return !isFixedExpense
    }
}

// MARK: - Investments

public enum InvestmentMovementType: String, Codable, CaseIterable, Identifiable, Hashable {
    case deposit
    case withdrawal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .deposit: return "Aporte"
        case .withdrawal: return "Resgate"
        }
    }
}

public struct InvestmentMovement: Identifiable, Codable, Hashable {
    public var id: UUID
    public var type: InvestmentMovementType
    public var amount: Double
    public var date: Date
    public var sourceAccountId: UUID
    public var investmentAccountId: UUID
    public var notes: String
    public var generatedTransactionId: UUID?

    public init(
        id: UUID = UUID(),
        type: InvestmentMovementType = .deposit,
        amount: Double,
        date: Date = Date(),
        sourceAccountId: UUID,
        investmentAccountId: UUID,
        notes: String = "",
        generatedTransactionId: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.amount = abs(amount)
        self.date = date
        self.sourceAccountId = sourceAccountId
        self.investmentAccountId = investmentAccountId
        self.notes = notes
        self.generatedTransactionId = generatedTransactionId
    }
}

public struct InvestmentItem: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var groupName: String
    public var investmentAccountId: UUID
    public var balance: Double
    public var showInConsolidated: Bool
    public var iconSymbol: String
    public var colorHex: String
    public var notes: String
    public var movements: [InvestmentMovement]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        groupName: String,
        investmentAccountId: UUID,
        balance: Double = 0.0,
        showInConsolidated: Bool = true,
        iconSymbol: String = "chart.line.uptrend.xyaxis",
        colorHex: String = "#10B981",
        notes: String = "",
        movements: [InvestmentMovement] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.groupName = groupName
        self.investmentAccountId = investmentAccountId
        self.balance = balance
        self.showInConsolidated = showInConsolidated
        self.iconSymbol = iconSymbol
        self.colorHex = colorHex
        self.notes = notes
        self.movements = movements
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, groupName, investmentAccountId, balance, showInConsolidated
        case iconSymbol, colorHex, notes, movements, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.id = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        self.name = (try? c.decodeIfPresent(String.self, forKey: AnyKey("name"))) ?? ""
        self.groupName = (try? c.decodeIfPresent(String.self, forKey: AnyKey("groupName")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("group_name"))) ?? ""
        self.investmentAccountId = (try? c.decode(UUID.self, forKey: AnyKey("investmentAccountId")))
            ?? (try? c.decode(UUID.self, forKey: AnyKey("investment_account_id"))) ?? UUID()
        self.balance = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("balance"))) ?? 0.0
        self.showInConsolidated = (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("showInConsolidated")))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("show_in_consolidated"))) ?? true
        self.iconSymbol = (try? c.decodeIfPresent(String.self, forKey: AnyKey("iconSymbol")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("icon_symbol"))) ?? "chart.line.uptrend.xyaxis"
        self.colorHex = (try? c.decodeIfPresent(String.self, forKey: AnyKey("colorHex")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("color_hex"))) ?? "#10B981"
        self.notes = (try? c.decodeIfPresent(String.self, forKey: AnyKey("notes"))) ?? ""
        self.movements = (try? c.decodeIfPresent([InvestmentMovement].self, forKey: AnyKey("movements"))) ?? []
        self.createdAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("createdAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("created_at"))) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(groupName, forKey: .groupName)
        try c.encode(investmentAccountId, forKey: .investmentAccountId)
        try c.encode(balance, forKey: .balance)
        try c.encode(showInConsolidated, forKey: .showInConsolidated)
        try c.encode(iconSymbol, forKey: .iconSymbol)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encode(notes, forKey: .notes)
        try c.encode(movements, forKey: .movements)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Debts (Dívidas em Aberto / Negociação)

public struct DebtItem: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var customImagePath: String?
    public var bankPresetId: String?
    public var iconSymbol: String
    public var colorHex: String
    public var originalAmount: Double
    public var contractedDate: Date?
    public var notes: String
    public var isPaid: Bool
    public var negotiatedAmount: Double?
    public var paidDate: Date?
    public var paidFromAccountId: UUID?
    public var paymentTransactionId: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        customImagePath: String? = nil,
        bankPresetId: String? = nil,
        iconSymbol: String = "creditcard.trianglebadge.exclamationmark",
        colorHex: String = "#EF4444",
        originalAmount: Double,
        contractedDate: Date? = nil,
        notes: String = "",
        isPaid: Bool = false,
        negotiatedAmount: Double? = nil,
        paidDate: Date? = nil,
        paidFromAccountId: UUID? = nil,
        paymentTransactionId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.customImagePath = customImagePath
        self.bankPresetId = bankPresetId
        self.iconSymbol = iconSymbol
        self.colorHex = colorHex
        self.originalAmount = abs(originalAmount)
        self.contractedDate = contractedDate
        self.notes = notes
        self.isPaid = isPaid
        self.negotiatedAmount = negotiatedAmount
        self.paidDate = paidDate
        self.paidFromAccountId = paidFromAccountId
        self.paymentTransactionId = paymentTransactionId
        self.createdAt = createdAt
    }
}

// MARK: - Loans (Empréstimos) & Financings (Financiamentos)

public enum CreditContractKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case loan
    case financing

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .loan: return "Empréstimo"
        case .financing: return "Financiamento"
        }
    }
}

public enum LoanSubtype: String, Codable, CaseIterable, Identifiable, Hashable {
    case consignado = "Consignado"
    case pessoal = "Pessoal"
    case fgts = "Antecipação FGTS"
    case empresarial = "Empresarial"
    case refinanciamento = "Refinanciamento"
    case outros = "Outros"

    public var id: String { rawValue }

    public var discountFactorMultiplier: Double {
        // Consignado e FGTS possuem taxas reguladas e desconto integral dos juros futuros (CDC Art. 52 §2º)
        switch self {
        case .consignado, .fgts:
            return 1.0
        case .pessoal, .refinanciamento:
            return 0.98
        case .empresarial, .outros:
            return 0.95
        }
    }
}

public enum FinancingSubtype: String, Codable, CaseIterable, Identifiable, Hashable {
    case imovel = "Imóvel"
    case carro = "Carro"

    public var id: String { rawValue }

    public var iconSymbol: String {
        switch self {
        case .imovel: return "house.fill"
        case .carro: return "car.fill"
        }
    }
}

public enum AmortizationSystem: String, Codable, CaseIterable, Identifiable, Hashable {
    case price = "PRICE (Parcelas Fixas)"
    case sac = "SAC (Amortização Constante)"

    public var id: String { rawValue }
}

public enum AmortizationRecalculationMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case reduceTerm = "Reduzir Prazo (Quantidade de Parcelas)"
    case reduceInstallment = "Reduzir Valor da Parcela"

    public var id: String { rawValue }
}

public struct AmortizationRecord: Identifiable, Codable, Hashable {
    public var id: UUID
    public var date: Date
    public var amountPaid: Double
    public var mode: AmortizationRecalculationMode
    public var previousInstallmentAmount: Double
    public var newInstallmentAmount: Double
    public var previousRemainingInstallments: Int
    public var newRemainingInstallments: Int
    public var accountId: UUID
    public var transactionId: UUID?
    public var notes: String
    public var effectiveAmortization: Double?
    public var previousBalance: Double?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        amountPaid: Double,
        mode: AmortizationRecalculationMode,
        previousInstallmentAmount: Double,
        newInstallmentAmount: Double,
        previousRemainingInstallments: Int,
        newRemainingInstallments: Int,
        accountId: UUID,
        transactionId: UUID? = nil,
        notes: String = "",
        effectiveAmortization: Double? = nil,
        previousBalance: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.amountPaid = amountPaid
        self.mode = mode
        self.previousInstallmentAmount = previousInstallmentAmount
        self.newInstallmentAmount = newInstallmentAmount
        self.previousRemainingInstallments = previousRemainingInstallments
        self.newRemainingInstallments = newRemainingInstallments
        self.accountId = accountId
        self.transactionId = transactionId
        self.notes = notes
        self.effectiveAmortization = effectiveAmortization
        self.previousBalance = previousBalance
    }
}

/// Métricas de Acompanhamento e Conquista de Progresso do Contrato de Crédito.
/// Adota o conceito de Prazo Original Imutável como régua mestra de progresso,
/// discriminando o avanço natural no fluxo das parcelas pagas da aceleração conquistada por amortizações extraordinárias.
public struct ContractProgressMetrics: Hashable, Identifiable {
    public var id: UUID

    /// Prazo Original Contratado imutável (Base total invariável = 100% da régua do tempo)
    public let originalTotalInstallments: Int

    /// Parcelas quitadas mês a mês no fluxo regular ao longo do tempo
    public let paidInFlowCount: Int

    /// Parcelas futuras que ainda restam ser pagas no cenário atual
    public let remainingCount: Int

    /// Parcelas eliminadas antecipadamente por amortizações extraordinárias
    public let eliminatedByAmortizationCount: Int

    /// Total de meses superados (pagos no fluxo + eliminados por amortização)
    public let totalOvercomeMonths: Int

    /// Percentual de conclusão global em relação ao plano original (0.0 a 1.0)
    public let globalCompletionPercentage: Double

    /// Proporção do progresso natural (0.0 a 1.0)
    public let naturalProgressRatio: Double

    /// Proporção da aceleração por amortização (0.0 a 1.0)
    public let amortizationAccelerationRatio: Double

    /// Proporção da dívida futura restante (0.0 a 1.0)
    public let remainingRatio: Double

    /// Anos de vida financeira poupados
    public let savedYears: Int

    /// Meses residuais poupados
    public let savedRemainingMonths: Int

    /// Texto traduzido do tempo de vida financeira recuperado (anos e meses)
    public var savedTimeString: String {
        if savedYears > 0 && savedRemainingMonths > 0 {
            return "\(savedYears) ano\(savedYears > 1 ? "s" : "") e \(savedRemainingMonths) m\(savedRemainingMonths > 1 ? "eses" : "ês")"
        } else if savedYears > 0 {
            return "\(savedYears) ano\(savedYears > 1 ? "s" : "")"
        } else {
            return "\(savedRemainingMonths) m\(savedRemainingMonths > 1 ? "eses" : "ês")"
        }
    }

    /// Novo Prazo Total Recalculado (parcelas pagas no fluxo + parcelas restantes a pagar)
    public var newRecalculatedTotalInstallments: Int {
        paidInFlowCount + remainingCount
    }

    /// Percentual de andamento do plano atual no cronograma vigente (0.0 a 1.0)
    public var currentPlanCompletionPercentage: Double {
        let total = newRecalculatedTotalInstallments
        return total > 0 ? Double(paidInFlowCount) / Double(total) : 1.0
    }

    /// Formatação amigável de total de meses e anos equivalentes (ex.: "360 meses (30 anos)" ou "251 meses (~21 anos)")
    public static func formatMonthsAndYears(_ months: Int) -> String {
        guard months > 0 else { return "0 meses" }
        if months % 12 == 0 {
            let y = months / 12
            return "\(months) meses (\(y) ano\(y > 1 ? "s" : ""))"
        } else {
            let years = Double(months) / 12.0
            let roundedYears = Int(round(years))
            if roundedYears > 0 {
                return "\(months) meses (~\(roundedYears) ano\(roundedYears > 1 ? "s" : ""))"
            } else {
                return "\(months) m\(months > 1 ? "eses" : "ês")"
            }
        }
    }

    /// Prazo Original Contratado formatado em meses e anos
    public var originalMonthsFormatted: String {
        Self.formatMonthsAndYears(originalTotalInstallments)
    }

    /// Novo Prazo Recalculado formatado em meses e anos
    public var newRecalculatedMonthsFormatted: String {
        Self.formatMonthsAndYears(newRecalculatedTotalInstallments)
    }

    public init(
        id: UUID = UUID(),
        originalTotalInstallments: Int,
        paidInFlowCount: Int,
        remainingCount: Int,
        isSettled: Bool = false
    ) {
        self.id = id
        let original = max(originalTotalInstallments, 1)
        self.originalTotalInstallments = original

        if isSettled || remainingCount <= 0 {
            let paid = min(paidInFlowCount, original)
            let eliminated = max(0, original - paid)
            self.paidInFlowCount = paid
            self.remainingCount = 0
            self.eliminatedByAmortizationCount = eliminated
            self.totalOvercomeMonths = original
            self.globalCompletionPercentage = 1.0
            self.naturalProgressRatio = Double(paid) / Double(original)
            self.amortizationAccelerationRatio = Double(eliminated) / Double(original)
            self.remainingRatio = 0.0
            self.savedYears = eliminated / 12
            self.savedRemainingMonths = eliminated % 12
        } else {
            let paid = min(paidInFlowCount, original)
            let rem = min(remainingCount, max(0, original - paid))
            let eliminated = max(0, original - (paid + rem))
            let overcome = min(paid + eliminated, original)
            self.paidInFlowCount = paid
            self.remainingCount = rem
            self.eliminatedByAmortizationCount = eliminated
            self.totalOvercomeMonths = overcome
            self.globalCompletionPercentage = Double(overcome) / Double(original)
            self.naturalProgressRatio = Double(paid) / Double(original)
            self.amortizationAccelerationRatio = Double(eliminated) / Double(original)
            self.remainingRatio = Double(rem) / Double(original)
            self.savedYears = eliminated / 12
            self.savedRemainingMonths = eliminated % 12
        }
    }
}

public struct CreditContract: Identifiable, Codable, Hashable {
    public var id: UUID
    public var kind: CreditContractKind
    public var name: String
    public var contractNumber: String?
    public var loanSubtype: LoanSubtype?
    public var financingSubtype: FinancingSubtype?
    public var amortizationSystem: AmortizationSystem
    public var totalContractedAmount: Double
    public var outstandingBalance: Double?
    public var installmentAmount: Double
    public var billingDay: Int
    public var totalInstallments: Int
    public var originalTotalInstallments: Int?
    public var monthlyInterestRate: Double // percentage, e.g., 1.65 means 1.65% a.m.
    public var startDate: Date?
    public var accountId: UUID
    public var categoryId: UUID
    public var pastInstallmentsElapsedAtCreation: Int
    public var extraAmortizedTotal: Double
    public var amortizationHistory: [AmortizationRecord]
    public var isSettled: Bool
    public var settledAmount: Double?
    public var settledDate: Date?
    public var settledAccountId: UUID?
    public var notes: String
    public var createdAt: Date

    // Componentes de Financiamento Imobiliário (SFH/SFI - Padrão CAIXA)
    public var annualNominalInterestRate: Double? // Taxa Nominal Contratual Anual (ex: 8.51% a.a.)
    public var indexationRate: FinancingIndexation? // TR, IPCA, Fixo
    public var adminFee: Double? // Taxa de Administração fixa (ex: R$ 25,00)
    public var insuranceFee: Double? // Seguros MIP/DFI (ex: R$ 86,27)
    public var baseInstallmentAmount: Double? // Parcela Base Price (Amortização + Juros)
    public var financingDetails: FinancingModel?
    public var loanDetails: LoanModel?

    public init(
        id: UUID = UUID(),
        kind: CreditContractKind,
        name: String,
        contractNumber: String? = nil,
        loanSubtype: LoanSubtype? = .consignado,
        financingSubtype: FinancingSubtype? = nil,
        amortizationSystem: AmortizationSystem = .price,
        totalContractedAmount: Double,
        outstandingBalance: Double? = nil,
        installmentAmount: Double,
        billingDay: Int,
        totalInstallments: Int,
        originalTotalInstallments: Int? = nil,
        monthlyInterestRate: Double,
        startDate: Date? = nil,
        accountId: UUID,
        categoryId: UUID,
        pastInstallmentsElapsedAtCreation: Int = 0,
        extraAmortizedTotal: Double = 0.0,
        amortizationHistory: [AmortizationRecord] = [],
        isSettled: Bool = false,
        settledAmount: Double? = nil,
        settledDate: Date? = nil,
        settledAccountId: UUID? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        annualNominalInterestRate: Double? = nil,
        indexationRate: FinancingIndexation? = nil,
        adminFee: Double? = nil,
        insuranceFee: Double? = nil,
        baseInstallmentAmount: Double? = nil,
        financingDetails: FinancingModel? = nil,
        loanDetails: LoanModel? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.contractNumber = contractNumber
        self.loanSubtype = loanSubtype
        self.financingSubtype = financingSubtype
        self.amortizationSystem = amortizationSystem
        self.totalContractedAmount = abs(totalContractedAmount)
        self.outstandingBalance = outstandingBalance.map { abs($0) }
        self.installmentAmount = abs(installmentAmount)
        self.billingDay = min(max(billingDay, 1), 31)
        self.totalInstallments = max(totalInstallments, 1)
        self.originalTotalInstallments = originalTotalInstallments ?? totalInstallments
        self.monthlyInterestRate = max(monthlyInterestRate, 0.0)
        self.startDate = startDate
        self.accountId = accountId
        self.categoryId = categoryId
        self.pastInstallmentsElapsedAtCreation = max(pastInstallmentsElapsedAtCreation, 0)
        self.extraAmortizedTotal = extraAmortizedTotal
        self.amortizationHistory = amortizationHistory
        self.isSettled = isSettled
        self.settledAmount = settledAmount
        self.settledDate = settledDate
        self.settledAccountId = settledAccountId
        self.notes = notes
        self.createdAt = createdAt

        self.annualNominalInterestRate = annualNominalInterestRate
        self.indexationRate = indexationRate
        self.adminFee = adminFee
        self.insuranceFee = insuranceFee
        self.baseInstallmentAmount = baseInstallmentAmount
        self.financingDetails = financingDetails
        self.loanDetails = loanDetails

        if kind == .financing && self.financingDetails == nil {
            let effAnnual = annualNominalInterestRate ?? (monthlyInterestRate > 0 ? monthlyInterestRate * 12.0 : 8.51)
            let effAdmin = adminFee ?? 25.0
            let effInsurance = insuranceFee ?? 0.0
            let remaining = max(totalInstallments - pastInstallmentsElapsedAtCreation, 0)
            self.financingDetails = FinancingModel(
                id: id,
                balance: outstandingBalance ?? totalContractedAmount,
                annualNominalInterestRate: effAnnual,
                amortizationSystem: amortizationSystem,
                indexationRate: indexationRate ?? .tr,
                adminFee: effAdmin,
                insuranceFee: effInsurance,
                totalInstallments: totalInstallments,
                remainingInstallments: remaining,
                totalInstallmentAmount: installmentAmount,
                lastBillingDate: startDate
            )
        }

        if kind == .loan && self.loanDetails == nil {
            let remaining = max(totalInstallments - pastInstallmentsElapsedAtCreation, 0)
            let effBalance: Double
            if let explicit = outstandingBalance {
                effBalance = explicit
            } else if pastInstallmentsElapsedAtCreation > 0 {
                effBalance = LoanModel.calculatePresentValue(installment: installmentAmount, monthlyRate: monthlyInterestRate, remaining: remaining)
            } else {
                effBalance = totalContractedAmount
            }
            let type: LoanType = (loanSubtype == .consignado) ? .payrollDeductible : .personal
            self.loanDetails = LoanModel(
                id: id,
                balance: effBalance,
                monthlyInterestRate: monthlyInterestRate,
                installmentValue: installmentAmount,
                remainingInstallments: remaining,
                totalInstallments: totalInstallments,
                loanType: type,
                startDate: startDate,
                lastBillingDate: startDate,
                notes: notes
            )
        }
    }

    /// Taxa de Juros Nominal Anual efetiva (% a.a.)
    public var effectiveAnnualNominalRate: Double {
        if let annual = annualNominalInterestRate, annual > 0 {
            return annual
        }
        if let fin = financingDetails, fin.annualNominalInterestRate > 0 {
            return fin.annualNominalInterestRate
        }
        return monthlyInterestRate * 12.0
    }

    /// Taxa de juros mensal nominal em decimal calculada dinamicamente: annualRate / 12 / 100
    public var effectiveMonthlyNominalRateDecimal: Double {
        (effectiveAnnualNominalRate / 12.0) / 100.0
    }

    /// Taxa de administração mensal efetiva
    public var effectiveAdminFee: Double {
        adminFee ?? financingDetails?.adminFee ?? (kind == .financing ? 25.0 : 0.0)
    }

    /// Valor dos seguros mensais MIP/DFI efetivos
    public var effectiveInsuranceFee: Double {
        insuranceFee ?? financingDetails?.insuranceFee ?? 0.0
    }

    /// Parcela Base Price (Amortização + Juros)
    /// Base Price = Parcela Total - Seguros - Taxas
    public var effectiveBaseInstallmentPrice: Double {
        if let base = baseInstallmentAmount, base > 0 {
            return base
        }
        if let fin = financingDetails, fin.baseInstallmentPrice > 0 {
            return fin.baseInstallmentPrice
        }
        if kind == .financing {
            return max(0.0, installmentAmount - effectiveInsuranceFee - effectiveAdminFee)
        }
        return installmentAmount
    }

    /// Retorna ou gera o modelo especializado de financiamento
    public var effectiveFinancingModel: FinancingModel? {
        if let fin = financingDetails { return fin }
        guard kind == .financing else { return nil }
        let remaining = max(totalInstallments - pastInstallmentsElapsedAtCreation, 0)
        return FinancingModel(
            id: id,
            balance: outstandingBalance ?? totalContractedAmount,
            annualNominalInterestRate: effectiveAnnualNominalRate,
            amortizationSystem: amortizationSystem,
            indexationRate: indexationRate ?? .tr,
            adminFee: effectiveAdminFee,
            insuranceFee: effectiveInsuranceFee,
            totalInstallments: totalInstallments,
            remainingInstallments: remaining,
            totalInstallmentAmount: installmentAmount,
            lastBillingDate: startDate
        )
    }

    /// Retorna ou gera o modelo especializado de empréstimo (Tabela Price pura)
    public var effectiveLoanModel: LoanModel? {
        if let loan = loanDetails { return loan }
        guard kind == .loan else { return nil }
        let remaining = max(totalInstallments - pastInstallmentsElapsedAtCreation, 0)
        let effBalance: Double
        if let explicit = outstandingBalance {
            effBalance = explicit
        } else if pastInstallmentsElapsedAtCreation > 0 {
            effBalance = LoanModel.calculatePresentValue(installment: installmentAmount, monthlyRate: monthlyInterestRate, remaining: remaining)
        } else {
            effBalance = totalContractedAmount
        }
        let type: LoanType = (loanSubtype == .consignado) ? .payrollDeductible : .personal
        return LoanModel(
            id: id,
            balance: effBalance,
            monthlyInterestRate: monthlyInterestRate,
            installmentValue: installmentAmount,
            remainingInstallments: remaining,
            totalInstallments: totalInstallments,
            loanType: type,
            startDate: startDate,
            lastBillingDate: startDate,
            notes: notes
        )
    }

    /// Prazo Original Contratado imutável (régua mestra invariável do contrato).
    /// Se não foi persistido diretamente, recupera de financingDetails, loanDetails ou calcula recompondo as parcelas eliminadas por amortizações prévias.
    public var effectiveOriginalTotalInstallments: Int {
        if let original = originalTotalInstallments, original > 0 {
            return max(original, totalInstallments)
        }
        if let finTotal = financingDetails?.totalInstallments, finTotal > 0 {
            return max(finTotal, totalInstallments)
        }
        if let loanTotal = loanDetails?.totalInstallments, loanTotal > 0 {
            return max(loanTotal, totalInstallments)
        }
        let eliminatedInHistory = amortizationHistory
            .filter { $0.mode == .reduceTerm }
            .reduce(0) { $0 + max(0, $1.previousRemainingInstallments - $1.newRemainingInstallments) }
        return max(totalInstallments + eliminatedInHistory, totalInstallments)
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, name, contractNumber, loanSubtype, financingSubtype, amortizationSystem
        case totalContractedAmount, outstandingBalance, installmentAmount, billingDay
        case totalInstallments, originalTotalInstallments, monthlyInterestRate, startDate, accountId, categoryId
        case pastInstallmentsElapsedAtCreation, extraAmortizedTotal, amortizationHistory
        case isSettled, settledAmount, settledDate, settledAccountId, notes, createdAt
        case annualNominalInterestRate, indexationRate, adminFee, insuranceFee
        case baseInstallmentAmount, financingDetails, loanDetails
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.id = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        self.kind = (try? c.decode(CreditContractKind.self, forKey: AnyKey("kind"))) ?? .loan
        self.name = (try? c.decodeIfPresent(String.self, forKey: AnyKey("name"))) ?? ""
        self.contractNumber = (try? c.decodeIfPresent(String.self, forKey: AnyKey("contractNumber")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("contract_number")))
        self.loanSubtype = (try? c.decodeIfPresent(LoanSubtype.self, forKey: AnyKey("loanSubtype")))
            ?? (try? c.decodeIfPresent(LoanSubtype.self, forKey: AnyKey("loan_subtype")))
        self.financingSubtype = (try? c.decodeIfPresent(FinancingSubtype.self, forKey: AnyKey("financingSubtype")))
            ?? (try? c.decodeIfPresent(FinancingSubtype.self, forKey: AnyKey("financing_subtype")))
        self.amortizationSystem = (try? c.decodeIfPresent(AmortizationSystem.self, forKey: AnyKey("amortizationSystem")))
            ?? (try? c.decodeIfPresent(AmortizationSystem.self, forKey: AnyKey("amortization_system"))) ?? .price
        self.totalContractedAmount = abs((try? c.decodeIfPresent(Double.self, forKey: AnyKey("totalContractedAmount")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("total_contracted_amount"))) ?? 0.0)
        self.outstandingBalance = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("outstandingBalance")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("outstanding_balance")))
        self.installmentAmount = abs((try? c.decodeIfPresent(Double.self, forKey: AnyKey("installmentAmount")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("installment_amount"))) ?? 0.0)
        self.billingDay = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("billingDay")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("billing_day"))) ?? 1
        self.totalInstallments = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("totalInstallments")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("total_installments"))) ?? 1
        self.originalTotalInstallments = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("originalTotalInstallments")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("original_total_installments")))
        self.monthlyInterestRate = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("monthlyInterestRate")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("monthly_interest_rate"))) ?? 0.0
        self.startDate = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("startDate")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("start_date")))
        self.accountId = (try? c.decode(UUID.self, forKey: AnyKey("accountId")))
            ?? (try? c.decode(UUID.self, forKey: AnyKey("account_id"))) ?? UUID()
        self.categoryId = (try? c.decode(UUID.self, forKey: AnyKey("categoryId")))
            ?? (try? c.decode(UUID.self, forKey: AnyKey("category_id"))) ?? UUID()
        self.pastInstallmentsElapsedAtCreation = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("pastInstallmentsElapsedAtCreation")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("past_installments_elapsed_at_creation"))) ?? 0
        self.extraAmortizedTotal = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("extraAmortizedTotal")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("extra_amortized_total"))) ?? 0.0
        self.amortizationHistory = (try? c.decodeIfPresent([AmortizationRecord].self, forKey: AnyKey("amortizationHistory")))
            ?? (try? c.decodeIfPresent([AmortizationRecord].self, forKey: AnyKey("amortization_history"))) ?? []
        self.isSettled = (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("isSettled")))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("is_settled"))) ?? false
        self.settledAmount = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("settledAmount")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("settled_amount")))
        self.settledDate = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("settledDate")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("settled_date")))
        self.settledAccountId = (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("settledAccountId")))
            ?? (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("settled_account_id")))
        self.notes = (try? c.decodeIfPresent(String.self, forKey: AnyKey("notes"))) ?? ""
        self.createdAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("createdAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("created_at"))) ?? Date()

        self.annualNominalInterestRate = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("annualNominalInterestRate")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("annual_nominal_interest_rate")))
        self.indexationRate = (try? c.decodeIfPresent(FinancingIndexation.self, forKey: AnyKey("indexationRate")))
            ?? (try? c.decodeIfPresent(FinancingIndexation.self, forKey: AnyKey("indexation_rate")))
        self.adminFee = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("adminFee")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("admin_fee")))
        self.insuranceFee = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("insuranceFee")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("insurance_fee")))
        self.baseInstallmentAmount = (try? c.decodeIfPresent(Double.self, forKey: AnyKey("baseInstallmentAmount")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("base_installment_amount")))
        self.financingDetails = (try? c.decodeIfPresent(FinancingModel.self, forKey: AnyKey("financingDetails")))
            ?? (try? c.decodeIfPresent(FinancingModel.self, forKey: AnyKey("financing_details")))
        self.loanDetails = (try? c.decodeIfPresent(LoanModel.self, forKey: AnyKey("loanDetails")))
            ?? (try? c.decodeIfPresent(LoanModel.self, forKey: AnyKey("loan_details")))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(contractNumber, forKey: .contractNumber)
        try c.encodeIfPresent(loanSubtype, forKey: .loanSubtype)
        try c.encodeIfPresent(financingSubtype, forKey: .financingSubtype)
        try c.encode(amortizationSystem, forKey: .amortizationSystem)
        try c.encode(totalContractedAmount, forKey: .totalContractedAmount)
        try c.encodeIfPresent(outstandingBalance, forKey: .outstandingBalance)
        try c.encode(installmentAmount, forKey: .installmentAmount)
        try c.encode(billingDay, forKey: .billingDay)
        try c.encode(totalInstallments, forKey: .totalInstallments)
        try c.encodeIfPresent(originalTotalInstallments, forKey: .originalTotalInstallments)
        try c.encode(monthlyInterestRate, forKey: .monthlyInterestRate)
        try c.encodeIfPresent(startDate, forKey: .startDate)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(pastInstallmentsElapsedAtCreation, forKey: .pastInstallmentsElapsedAtCreation)
        try c.encode(extraAmortizedTotal, forKey: .extraAmortizedTotal)
        try c.encode(amortizationHistory, forKey: .amortizationHistory)
        try c.encode(isSettled, forKey: .isSettled)
        try c.encodeIfPresent(settledAmount, forKey: .settledAmount)
        try c.encodeIfPresent(settledDate, forKey: .settledDate)
        try c.encodeIfPresent(settledAccountId, forKey: .settledAccountId)
        try c.encode(notes, forKey: .notes)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(annualNominalInterestRate, forKey: .annualNominalInterestRate)
        try c.encodeIfPresent(indexationRate, forKey: .indexationRate)
        try c.encodeIfPresent(adminFee, forKey: .adminFee)
        try c.encodeIfPresent(insuranceFee, forKey: .insuranceFee)
        try c.encodeIfPresent(baseInstallmentAmount, forKey: .baseInstallmentAmount)
        try c.encodeIfPresent(financingDetails, forKey: .financingDetails)
        try c.encodeIfPresent(loanDetails, forKey: .loanDetails)
    }

    public var subtypeDisplayName: String {
        switch kind {
        case .loan:
            return loanSubtype?.rawValue ?? "Consignado"
        case .financing:
            return financingSubtype?.rawValue ?? "Imóvel"
        }
    }

    public var iconSymbol: String {
        switch kind {
        case .loan:
            switch loanSubtype ?? .consignado {
            case .consignado: return "person.badge.shield.checkmark.fill"
            case .pessoal: return "banknote.fill"
            case .fgts: return "building.2.crop.circle.fill"
            case .empresarial: return "briefcase.fill"
            case .refinanciamento: return "arrow.triangle.2.circlepath.circle.fill"
            case .outros: return "doc.text.fill"
            }
        case .financing:
            return (financingSubtype ?? .imovel).iconSymbol
        }
    }
}

// MARK: - Local LLM Configuration & Chat

public struct LocalLLMModelInfo: Identifiable, Codable, Hashable {
    public var id: String // e.g., "Qwen/Qwen2.5-3B-Instruct-GGUF"
    public var displayName: String
    public var fileName: String
    public var localPath: String
    public var sizeBytes: Int64
    public var downloadedAt: Date
    public var quantization: String

    public init(
        id: String,
        displayName: String,
        fileName: String,
        localPath: String,
        sizeBytes: Int64,
        downloadedAt: Date = Date(),
        quantization: String = "Q4_K_M / 4-bit"
    ) {
        self.id = id
        self.displayName = displayName
        self.fileName = fileName
        self.localPath = localPath
        self.sizeBytes = sizeBytes
        self.downloadedAt = downloadedAt
        self.quantization = quantization
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

public struct LLMConfiguration: Codable, Hashable {
    public var huggingFaceToken: String
    public var selectedModelId: String?
    public var downloadedModels: [LocalLLMModelInfo]
    public var localEndpointURL: String

    public init(
        huggingFaceToken: String = "",
        selectedModelId: String? = nil,
        downloadedModels: [LocalLLMModelInfo] = [],
        localEndpointURL: String = ""
    ) {
        self.huggingFaceToken = huggingFaceToken
        self.selectedModelId = selectedModelId
        self.downloadedModels = downloadedModels
        self.localEndpointURL = localEndpointURL
    }

    public var selectedModel: LocalLLMModelInfo? {
        guard let selectedModelId else { return downloadedModels.first }
        return downloadedModels.first(where: { $0.id == selectedModelId }) ?? downloadedModels.first
    }
}

public enum ChatMessageRole: String, Codable, Hashable {
    case user
    case assistant
    case system
    case tool
}

public struct ChatMessage: Identifiable, Codable, Hashable {
    public var id: UUID
    public var role: ChatMessageRole
    public var content: String
    public var timestamp: Date
    public var modelUsed: String?
    public var agentSteps: [String]?
    public var suggestedFollowUps: [String]?
    public var shouldCloseChat: Bool?
    public var toolName: String?
    public var toolCallId: String?
    public var toolCalls: [AIToolCall]?

    public init(
        id: UUID = UUID(),
        role: ChatMessageRole,
        content: String,
        timestamp: Date = Date(),
        modelUsed: String? = nil,
        agentSteps: [String]? = nil,
        suggestedFollowUps: [String]? = nil,
        shouldCloseChat: Bool? = nil,
        toolName: String? = nil,
        toolCallId: String? = nil,
        toolCalls: [AIToolCall]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.modelUsed = modelUsed
        self.agentSteps = agentSteps
        self.suggestedFollowUps = suggestedFollowUps
        self.shouldCloseChat = shouldCloseChat
        self.toolName = toolName
        self.toolCallId = toolCallId
        self.toolCalls = toolCalls
    }
}

// MARK: - Isolamento de Ambientes de Persistência (Debug vs Release)

public enum PersistenceEnvironment: String, Codable, CaseIterable, Hashable {
    case debug
    case release

    public static var current: PersistenceEnvironment {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }

    public var isDebug: Bool {
        self == .debug
    }

    public var badgeTitle: String {
        switch self {
        case .debug: return "[DEBUG DB]"
        case .release: return "RELEASE DB"
        }
    }

    public var folderName: String {
        switch self {
        case .debug: return "FinSense-Debug"
        case .release: return "FinSense"
        }
    }

    public var databaseFileName: String {
        switch self {
        case .debug: return "financial_database_debug.json"
        case .release: return "financial_database.json"
        }
    }
}

// MARK: - Provisão de Gastos Estimados & Cotas Específicas (Orçamento por Envelopes Dinâmicos)

public enum ProvisionEditScope: String, Codable, CaseIterable, Identifiable, Hashable {
    case onlyThisMonth
    case thisAndFutureMonths

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .onlyThisMonth:
            return "Aplicar somente a este mês"
        case .thisAndFutureMonths:
            return "Aplicar a este e a todos os meses futuros"
        }
    }
}

public enum ProvisionDeleteScope: String, Codable, CaseIterable, Identifiable, Hashable {
    case onlyThisMonth
    case fromThisMonthOnward
    case allOccurrences

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .onlyThisMonth:
            return "Excluir somente deste mês"
        case .fromThisMonthOnward:
            return "Excluir deste mês em diante"
        case .allOccurrences:
            return "Excluir todas as ocorrências"
        }
    }
}

public enum ProvisionStatusLevel: String, Codable, CaseIterable, Hashable {
    case normal = "Normal"      // Abaixo de 80%
    case warning = "Alerta"     // Entre 80% e 100%
    case exceeded = "Estourado" // Acima de 100% (estourado)

    public var title: String { rawValue }

    public var colorHex: String {
        switch self {
        case .normal: return "#10B981"   // Verde
        case .warning: return "#F59E0B"  // Amarelo / Laranja
        case .exceeded: return "#EF4444" // Vermelho
        }
    }

    public var iconSymbol: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .exceeded: return "xmark.octagon.fill"
        }
    }
}

public struct CategoryProvision: Identifiable, Codable, Hashable {
    public var id: UUID
    public var categoryId: UUID
    public var year: Int
    public var month: Int
    public var estimatedAmount: Double
    public var repeatForFutureMonths: Bool
    public var monthlyOverrides: [Int: Double]?
    public var excludedYearMonthKeys: Set<Int>?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        categoryId: UUID,
        year: Int,
        month: Int,
        estimatedAmount: Double,
        repeatForFutureMonths: Bool = true,
        monthlyOverrides: [Int: Double]? = nil,
        excludedYearMonthKeys: Set<Int>? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.categoryId = categoryId
        self.year = year
        self.month = min(max(month, 1), 12)
        self.estimatedAmount = max(0, estimatedAmount)
        self.repeatForFutureMonths = repeatForFutureMonths
        self.monthlyOverrides = monthlyOverrides
        self.excludedYearMonthKeys = excludedYearMonthKeys
        self.createdAt = createdAt
    }

    public var yearMonthKey: Int {
        year * 100 + month
    }
}

public struct CategoryQuotaMonthlyOverride: Codable, Hashable {
    public var name: String?
    public var plannedQuantity: Int
    public var estimatedUnitPrice: Double

    public init(
        name: String? = nil,
        plannedQuantity: Int,
        estimatedUnitPrice: Double
    ) {
        self.name = name
        self.plannedQuantity = max(0, plannedQuantity)
        self.estimatedUnitPrice = max(0, estimatedUnitPrice)
    }
}

public enum QuotaType: String, Codable, CaseIterable, Identifiable, Hashable {
    case expense = "expense"
    case investment = "investment"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .expense: return "Cota de Despesa"
        case .investment: return "Planejamento de Investimento"
        }
    }
}

public struct CategoryQuotaRule: Identifiable, Codable, Hashable {
    public var id: UUID
    public var seriesId: UUID
    public var categoryId: UUID
    public var name: String
    public var iconSymbol: String
    public var year: Int
    public var month: Int
    public var plannedQuantity: Int
    public var estimatedUnitPrice: Double
    public var repeatForFutureMonths: Bool
    public var monthlyOverrides: [Int: CategoryQuotaMonthlyOverride]?
    public var excludedYearMonthKeys: Set<Int>?
    public var quotaType: QuotaType
    public var linkedInvestmentId: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        seriesId: UUID? = nil,
        categoryId: UUID,
        name: String,
        iconSymbol: String = "shippingbox.fill",
        year: Int,
        month: Int,
        plannedQuantity: Int,
        estimatedUnitPrice: Double,
        repeatForFutureMonths: Bool = true,
        monthlyOverrides: [Int: CategoryQuotaMonthlyOverride]? = nil,
        excludedYearMonthKeys: Set<Int>? = nil,
        quotaType: QuotaType = .expense,
        linkedInvestmentId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.seriesId = seriesId ?? id
        self.categoryId = categoryId
        self.name = name
        self.iconSymbol = iconSymbol
        self.year = year
        self.month = min(max(month, 1), 12)
        self.plannedQuantity = max(0, plannedQuantity)
        self.estimatedUnitPrice = max(0, estimatedUnitPrice)
        self.repeatForFutureMonths = repeatForFutureMonths
        self.monthlyOverrides = monthlyOverrides
        self.excludedYearMonthKeys = excludedYearMonthKeys
        self.quotaType = quotaType
        self.linkedInvestmentId = linkedInvestmentId
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, seriesId, categoryId, name, iconSymbol, year, month, plannedQuantity, estimatedUnitPrice
        case repeatForFutureMonths, monthlyOverrides, excludedYearMonthKeys, quotaType, linkedInvestmentId, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.id = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        self.seriesId = (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("seriesId")))
            ?? (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("series_id"))) ?? id

        if let cat = try? c.decode(UUID.self, forKey: AnyKey("categoryId")) { self.categoryId = cat }
        else if let cat = try? c.decode(UUID.self, forKey: AnyKey("category_id")) { self.categoryId = cat }
        else { self.categoryId = UUID() }

        self.name = (try? c.decodeIfPresent(String.self, forKey: AnyKey("name"))) ?? ""
        self.iconSymbol = (try? c.decodeIfPresent(String.self, forKey: AnyKey("iconSymbol")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("icon_symbol"))) ?? "shippingbox.fill"
        self.year = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("year"))) ?? 2026
        self.month = (try? c.decodeIfPresent(Int.self, forKey: AnyKey("month"))) ?? 1
        self.plannedQuantity = max(0, (try? c.decodeIfPresent(Int.self, forKey: AnyKey("plannedQuantity")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey("planned_quantity"))) ?? 0)
        self.estimatedUnitPrice = max(0, (try? c.decodeIfPresent(Double.self, forKey: AnyKey("estimatedUnitPrice")))
            ?? (try? c.decodeIfPresent(Double.self, forKey: AnyKey("estimated_unit_price"))) ?? 0.0)
        self.repeatForFutureMonths = (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("repeatForFutureMonths")))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("repeat_for_future_months"))) ?? true
        self.monthlyOverrides = (try? c.decodeIfPresent([Int: CategoryQuotaMonthlyOverride].self, forKey: AnyKey("monthlyOverrides")))
            ?? (try? c.decodeIfPresent([Int: CategoryQuotaMonthlyOverride].self, forKey: AnyKey("monthly_overrides")))
        self.excludedYearMonthKeys = (try? c.decodeIfPresent(Set<Int>.self, forKey: AnyKey("excludedYearMonthKeys")))
            ?? (try? c.decodeIfPresent(Set<Int>.self, forKey: AnyKey("excluded_year_month_keys")))

        let rawQuotaType = (try? c.decodeIfPresent(String.self, forKey: AnyKey("quotaType")))
            ?? (try? c.decodeIfPresent(String.self, forKey: AnyKey("quota_type")))
        self.quotaType = QuotaType(rawValue: rawQuotaType ?? "expense") ?? .expense

        self.linkedInvestmentId = (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("linkedInvestmentId")))
            ?? (try? c.decodeIfPresent(UUID.self, forKey: AnyKey("linked_investment_id")))

        self.createdAt = (try? c.decodeIfPresent(Date.self, forKey: AnyKey("createdAt")))
            ?? (try? c.decodeIfPresent(Date.self, forKey: AnyKey("created_at"))) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(seriesId, forKey: .seriesId)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(name, forKey: .name)
        try c.encode(iconSymbol, forKey: .iconSymbol)
        try c.encode(year, forKey: .year)
        try c.encode(month, forKey: .month)
        try c.encode(plannedQuantity, forKey: .plannedQuantity)
        try c.encode(estimatedUnitPrice, forKey: .estimatedUnitPrice)
        try c.encode(repeatForFutureMonths, forKey: .repeatForFutureMonths)
        try c.encodeIfPresent(monthlyOverrides, forKey: .monthlyOverrides)
        try c.encodeIfPresent(excludedYearMonthKeys, forKey: .excludedYearMonthKeys)
        try c.encode(quotaType.rawValue, forKey: .quotaType)
        try c.encodeIfPresent(linkedInvestmentId, forKey: .linkedInvestmentId)
        try c.encode(createdAt, forKey: .createdAt)
    }

    public var yearMonthKey: Int {
        year * 100 + month
    }
}

public struct CategoryQuotaEnvelope: Identifiable, Hashable {
    public var id: UUID { rule.seriesId }
    public let rule: CategoryQuotaRule
    public var seriesId: UUID { rule.seriesId }
    public var categoryId: UUID { rule.categoryId }
    public var quotaType: QuotaType { rule.quotaType }
    public var linkedInvestmentId: UUID? { rule.linkedInvestmentId }
    public let name: String
    public let iconSymbol: String
    public let plannedQuantity: Int             // Quantidade Prevista_i
    public let consumedUnits: Int               // Unidades Baixadas_i
    public let pendingUnits: Int                // Unidades Pendentes_i = max(0, Quantidade Prevista_i - Unidades Baixadas_i)
    public let estimatedUnitPrice: Double       // Preço Unitário Estimado_i
    public let totalEstimatedAmount: Double     // Quantidade Prevista_i * Preço Unitário Estimado_i
    public let remainingProvision: Double       // Provisão Restante_i = Unidades Pendentes_i * Preço Unitário Estimado_i
    public let realizedExpense: Double          // Soma das transações reais geradas pela baixa desta cota no mês
    public let repeatForFutureMonths: Bool
    public let isInheritedFromPreviousMonth: Bool
    public let isLocalMonthOverride: Bool

    public var progressRatio: Double {
        guard plannedQuantity > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(consumedUnits) / Double(plannedQuantity)))
    }

    public var status: ProvisionStatusLevel {
        if consumedUnits > plannedQuantity {
            return .exceeded
        } else if plannedQuantity > 0 && Double(consumedUnits) / Double(plannedQuantity) >= 0.8 - 0.001 {
            return .warning
        } else {
            return .normal
        }
    }

    public init(
        rule: CategoryQuotaRule,
        name: String,
        iconSymbol: String,
        plannedQuantity: Int,
        consumedUnits: Int,
        estimatedUnitPrice: Double,
        realizedExpense: Double,
        repeatForFutureMonths: Bool,
        isInheritedFromPreviousMonth: Bool,
        isLocalMonthOverride: Bool = false
    ) {
        self.rule = rule
        self.name = name
        self.iconSymbol = iconSymbol
        let cleanPlanned = max(0, plannedQuantity)
        let cleanConsumed = max(0, consumedUnits)
        let cleanUnit = max(0.0, estimatedUnitPrice)
        self.plannedQuantity = cleanPlanned
        self.consumedUnits = cleanConsumed
        self.pendingUnits = max(0, cleanPlanned - cleanConsumed)
        self.estimatedUnitPrice = cleanUnit
        self.totalEstimatedAmount = Double(cleanPlanned) * cleanUnit
        self.remainingProvision = Double(max(0, cleanPlanned - cleanConsumed)) * cleanUnit
        self.realizedExpense = max(0.0, realizedExpense)
        self.repeatForFutureMonths = repeatForFutureMonths
        self.isInheritedFromPreviousMonth = isInheritedFromPreviousMonth
        self.isLocalMonthOverride = isLocalMonthOverride
    }
}

public struct CategoryProvisionEnvelope: Identifiable, Hashable {
    public var id: UUID { category.id }
    public let category: CategoryItem
    public let provision: CategoryProvision
    public var provisionId: UUID { provision.id }

    // Previsão por Categoria (Teto Geral Mensal) — 100% desacoplado das Cotas de Itens Específicos
    public let estimatedAmount: Double              // Teto Definido_c
    public let realizedExpense: Double              // Gasto Real Avulso da Categoria_c (ignora baixas de cotas)
    public let remainingProvision: Double           // Teto Restante_c = max(0, Teto Definido_c - Gasto Real Avulso_c)
    public let exceededAmount: Double               // max(0, Gasto Real Avulso_c - Teto Definido_c)
    public let rawProgressPercentage: Double        // (Gasto Real Avulso_c / Teto Definido_c) * 100
    public let clampedProgressPercentage: Double    // min(100, rawProgressPercentage)
    public let status: ProvisionStatusLevel
    public let isFreeBudgetLocalOverride: Bool
    public var repeatForFutureMonths: Bool {
        provision.repeatForFutureMonths
    }
    public let isInheritedFromPreviousMonth: Bool

    // Aliases semânticos de conveniência para o Teto Geral / Verba Livre da Categoria
    public var freeBudgetEstimated: Double { estimatedAmount }
    public var freeBudgetRealizedExpense: Double { realizedExpense }
    public var freeBudgetRemaining: Double { remainingProvision }

    public init(
        category: CategoryItem,
        provision: CategoryProvision,
        isInheritedFromPreviousMonth: Bool,
        estimatedAmount: Double,
        realizedExpense: Double,
        isFreeBudgetLocalOverride: Bool = false
    ) {
        self.category = category
        self.provision = provision
        self.isInheritedFromPreviousMonth = isInheritedFromPreviousMonth
        self.isFreeBudgetLocalOverride = isFreeBudgetLocalOverride

        let cleanEst = max(0.0, estimatedAmount)
        let cleanRealized = max(0.0, realizedExpense)
        let cleanRem = max(0.0, cleanEst - cleanRealized)

        self.estimatedAmount = cleanEst
        self.realizedExpense = cleanRealized
        self.remainingProvision = cleanRem
        self.exceededAmount = cleanEst > 0 ? max(0.0, cleanRealized - cleanEst) : 0.0

        let rawPct = cleanEst > 0.0001 ? ((cleanRealized / cleanEst) * 100.0) : 0.0
        self.rawProgressPercentage = rawPct
        self.clampedProgressPercentage = min(100.0, max(0.0, rawPct))

        if cleanEst > 0 && cleanRealized > cleanEst + 0.001 {
            self.status = .exceeded
        } else if rawPct >= 80.0 - 0.001 {
            self.status = .warning
        } else {
            self.status = .normal
        }
    }
}

// MARK: - Exportação Completa & Importação Seletiva Validada (Configurações)

public struct ExportedAssetFile: Codable, Hashable, Identifiable {
    public var id: String { fileName }
    public var fileName: String
    public var originalPath: String
    public var data: Data

    public init(fileName: String, originalPath: String, data: Data) {
        self.fileName = fileName
        self.originalPath = originalPath
        self.data = data
    }
}

public enum ExportDataTarget: String, CaseIterable, Identifiable, Hashable, Codable {
    case accounts = "accounts"
    case categories = "categories"
    case transactions = "transactions"
    case investments = "investments"
    case loans = "loans"
    case financings = "financings"
    case debts = "debts"
    case provisions = "provisions"
    case assets = "assets"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .transactions:
            return "Transações (Receitas e Despesas)"
        case .accounts:
            return "Contas Bancárias e Carteiras"
        case .categories:
            return "Categorias"
        case .investments:
            return "Investimentos"
        case .loans:
            return "Empréstimos"
        case .financings:
            return "Financiamentos"
        case .debts:
            return "Dívidas"
        case .provisions:
            return "Previsões e Cotas"
        case .assets:
            return "Assets, Ícones e Comprovantes"
        }
    }

    public var subtitle: String {
        switch self {
        case .transactions:
            return "Lançamentos de receitas e despesas do extrato"
        case .accounts:
            return "Contas correntes, carteiras e saldos iniciais"
        case .categories:
            return "Categorias personalizadas e padrões de receitas/despesas"
        case .investments:
            return "Aplicações, CDBs, cofrinhos e carteiras de investimento"
        case .loans:
            return "Contratos de empréstimo pessoal e consignado"
        case .financings:
            return "Contratos de financiamento imobiliário e veicular"
        case .debts:
            return "Dívidas em aberto e histórico de acordos"
        case .provisions:
            return "Tetos mensais por categoria e cotas de itens específicos"
        case .assets:
            return "Imagens personalizadas de contas/dívidas e anexos de transações"
        }
    }

    public var icon: String {
        switch self {
        case .transactions: return "arrow.left.arrow.right.circle.fill"
        case .accounts: return "building.columns.fill"
        case .categories: return "square.grid.2x2.fill"
        case .investments: return "chart.line.uptrend.xyaxis.circle.fill"
        case .loans: return "banknote.fill"
        case .financings: return "house.and.flag.fill"
        case .debts: return "exclamationmark.shield.fill"
        case .provisions: return "tray.full.fill"
        case .assets: return "photo.on.rectangle.angled"
        }
    }
}

public struct ImportableExpenseDraft: Identifiable, Hashable {
    public var id: UUID
    public var originalTransactionId: UUID?
    public var date: Date
    public var description: String
    public var details: String
    public var amount: Double
    public var type: TransactionType
    public var isPaid: Bool
    public var categoryId: UUID
    public var accountId: UUID
    public var isDuplicate: Bool
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        originalTransactionId: UUID? = nil,
        date: Date,
        description: String,
        details: String = "",
        amount: Double,
        type: TransactionType = .expense,
        isPaid: Bool = true,
        categoryId: UUID,
        accountId: UUID,
        isDuplicate: Bool = false,
        isSelected: Bool = true
    ) {
        self.id = id
        self.originalTransactionId = originalTransactionId
        self.date = date
        self.description = description
        self.details = details
        self.amount = abs(amount)
        self.type = type
        self.isPaid = isPaid
        self.categoryId = categoryId
        self.accountId = accountId
        self.isDuplicate = isDuplicate
        self.isSelected = isSelected
    }
}

// MARK: - Unified Financial KPI Architecture

/// Os seis contextos temporais padronizados da aplicação (mensais e anuais).
public enum FinancialTemporalContext: String, Codable, CaseIterable, Identifiable, Hashable {
    case pastMonth       // 1. Mês passado: mês fechado
    case currentMonth    // 2. Mês atual: mês em andamento
    case futureMonth     // 3. Mês futuro: mês projetado
    case pastYear        // 4. Ano passado: ano fechado
    case currentYear     // 5. Ano atual: ano em andamento
    case futureYear      // 6. Ano futuro: ano projetado

    public var id: String { rawValue }

    public var isClosed: Bool {
        self == .pastMonth || self == .pastYear
    }

    public var isCurrent: Bool {
        self == .currentMonth || self == .currentYear
    }

    public var isFuture: Bool {
        self == .futureMonth || self == .futureYear
    }

    public var isAnnual: Bool {
        self == .pastYear || self == .currentYear || self == .futureYear
    }

    public var title: String {
        switch self {
        case .pastMonth: return "Mês Passado (Fechado)"
        case .currentMonth: return "Mês Atual (Em Andamento)"
        case .futureMonth: return "Mês Futuro (Projetado)"
        case .pastYear: return "Ano Passado (Fechado)"
        case .currentYear: return "Ano Atual (Em Andamento)"
        case .futureYear: return "Ano Futuro (Projetado)"
        }
    }
}

/// Modelo canônico e centralizado contendo todos os indicadores de resumo (KPIs)
/// calculados estritamente pelo FinancialDataStore para as 4 telas:
/// Dashboard, Transações, Despesas e Receitas.
public struct UnifiedFinancialKPISummary: Hashable {
    public let referenceDate: Date
    public let referenceNow: Date
    public let isAnnual: Bool
    public let temporalContext: FinancialTemporalContext

    // 1. Receitas
    public let receivedIncome: Double             // Receitas efetivamente recebidas (isPaid == true)
    public let pendingIncome: Double              // Receitas pendentes cadastradas (isPaid == false)
    public let pendingIncomeOverdue: Double       // Receitas pendentes em atraso (date < today)
    public let pendingIncomeOnTime: Double        // Receitas pendentes no prazo (date >= today)
    public let unrecordedExpectedIncome: Double   // Receitas previstas sem lançamento cadastrado (R$ 0,00 documentado)
    public let projectedIncome: Double            // receivedIncome + pendingIncome + unrecordedExpectedIncome
    public let habitualIncome: Double             // Receitas habituais
    public let extraordinaryIncome: Double         // Receitas extraordinárias (13º salário, bônus, PLR, etc.)
    public let topIncomeSourceName: String?       // Categoria/fonte principal
    public let topIncomeSourceAmount: Double      // Valor da principal fonte
    public let topIncomeSourcePercentage: Double  // % da principal fonte

    // 2. Despesas
    public let paidExpense: Double                // Despesas pagas (isPaid == true)
    public let pendingExpense: Double             // Despesas pendentes cadastradas (isPaid == false)
    public let recordedExpense: Double            // Despesas lançadas = paidExpense + pendingExpense
    public let overdueExpenses: Double            // Despesas vencidas (isPaid == false && date < today)
    public let onTimePendingExpenses: Double      // Despesas pendentes no prazo (isPaid == false && date >= today)
    public let fixedExpenses: Double              // Despesas fixas / recorrentes
    public let fixedExpensesPercentage: Double    // % de despesas fixas
    public let variableExpenses: Double           // Despesas variáveis / avulsas
    public let variableExpensesPercentage: Double // % de despesas variáveis

    // 3. Orçamentos e Cotas
    public let categoryCeilingsRemaining: Double  // Tetos restantes por categoria
    public let specificQuotasRemaining: Double    // Cotas específicas restantes
    public let remainingBudgetsAndQuotas: Double  // categoryCeilingsRemaining + specificQuotasRemaining
    public let totalBudgetsOverrun: Double        // Excedente de orçamento (estouro de teto)
    public let hasBudgetOverrun: Bool             // totalBudgetsOverrun > 0.001

    // 4. Gastos Planejados e Sobra
    public let totalPlannedExpenses: Double       // recordedExpense + remainingBudgetsAndQuotas
    public let surplusAfterPlanning: Double       // projectedIncome - totalPlannedExpenses
    public let operationalNetBalance: Double      // projectedIncome - recordedExpense

    // 5. Saldo Bancário e Caixa
    public let currentAccountBalanceNow: Double   // Saldo atual consolidado das contas hoje
    public let projectedAccountBalance: Double    // Saldo inicial + movimentações futuras registradas
    public let balanceIfAllBudgetsConsumed: Double // projectedAccountBalance - remainingBudgetsAndQuotas
    public let projectedAccountBalanceTitle: String

    // 6. Estatísticas Operacionais (Transações)
    public let consolidatedEntries: Double        // Entradas consolidadas (ignora transferências internas e canceladas)
    public let consolidatedExits: Double          // Saídas consolidadas (ignora transferências internas e canceladas)
    public let transactionsNetBalance: Double     // consolidatedEntries - consolidatedExits
    public let totalPendingVolume: Double         // pendingIncome + pendingExpense
    public let paidTransactionsCount: Int         // Quantidade de transações efetivadas
    public let pendingTransactionsCount: Int      // Quantidade de transações pendentes
    public let validTransactionsCount: Int        // Quantidade total de transações válidas

    public var isPast: Bool { temporalContext.isClosed }

    public init(
        referenceDate: Date,
        referenceNow: Date,
        isAnnual: Bool,
        temporalContext: FinancialTemporalContext,
        receivedIncome: Double,
        pendingIncome: Double,
        pendingIncomeOverdue: Double,
        pendingIncomeOnTime: Double,
        unrecordedExpectedIncome: Double,
        projectedIncome: Double,
        habitualIncome: Double,
        extraordinaryIncome: Double,
        topIncomeSourceName: String?,
        topIncomeSourceAmount: Double,
        topIncomeSourcePercentage: Double,
        paidExpense: Double,
        pendingExpense: Double,
        recordedExpense: Double,
        overdueExpenses: Double,
        onTimePendingExpenses: Double,
        fixedExpenses: Double,
        fixedExpensesPercentage: Double,
        variableExpenses: Double,
        variableExpensesPercentage: Double,
        categoryCeilingsRemaining: Double,
        specificQuotasRemaining: Double,
        remainingBudgetsAndQuotas: Double,
        totalBudgetsOverrun: Double,
        hasBudgetOverrun: Bool,
        totalPlannedExpenses: Double,
        surplusAfterPlanning: Double,
        operationalNetBalance: Double,
        currentAccountBalanceNow: Double,
        projectedAccountBalance: Double,
        balanceIfAllBudgetsConsumed: Double,
        projectedAccountBalanceTitle: String,
        consolidatedEntries: Double,
        consolidatedExits: Double,
        transactionsNetBalance: Double,
        totalPendingVolume: Double,
        paidTransactionsCount: Int,
        pendingTransactionsCount: Int,
        validTransactionsCount: Int
    ) {
        self.referenceDate = referenceDate
        self.referenceNow = referenceNow
        self.isAnnual = isAnnual
        self.temporalContext = temporalContext
        self.receivedIncome = receivedIncome
        self.pendingIncome = pendingIncome
        self.pendingIncomeOverdue = pendingIncomeOverdue
        self.pendingIncomeOnTime = pendingIncomeOnTime
        self.unrecordedExpectedIncome = unrecordedExpectedIncome
        self.projectedIncome = projectedIncome
        self.habitualIncome = habitualIncome
        self.extraordinaryIncome = extraordinaryIncome
        self.topIncomeSourceName = topIncomeSourceName
        self.topIncomeSourceAmount = topIncomeSourceAmount
        self.topIncomeSourcePercentage = topIncomeSourcePercentage
        self.paidExpense = paidExpense
        self.pendingExpense = pendingExpense
        self.recordedExpense = recordedExpense
        self.overdueExpenses = overdueExpenses
        self.onTimePendingExpenses = onTimePendingExpenses
        self.fixedExpenses = fixedExpenses
        self.fixedExpensesPercentage = fixedExpensesPercentage
        self.variableExpenses = variableExpenses
        self.variableExpensesPercentage = variableExpensesPercentage
        self.categoryCeilingsRemaining = categoryCeilingsRemaining
        self.specificQuotasRemaining = specificQuotasRemaining
        self.remainingBudgetsAndQuotas = remainingBudgetsAndQuotas
        self.totalBudgetsOverrun = totalBudgetsOverrun
        self.hasBudgetOverrun = hasBudgetOverrun
        self.totalPlannedExpenses = totalPlannedExpenses
        self.surplusAfterPlanning = surplusAfterPlanning
        self.operationalNetBalance = operationalNetBalance
        self.currentAccountBalanceNow = currentAccountBalanceNow
        self.projectedAccountBalance = projectedAccountBalance
        self.balanceIfAllBudgetsConsumed = balanceIfAllBudgetsConsumed
        self.projectedAccountBalanceTitle = projectedAccountBalanceTitle
        self.consolidatedEntries = consolidatedEntries
        self.consolidatedExits = consolidatedExits
        self.transactionsNetBalance = transactionsNetBalance
        self.totalPendingVolume = totalPendingVolume
        self.paidTransactionsCount = paidTransactionsCount
        self.pendingTransactionsCount = pendingTransactionsCount
        self.validTransactionsCount = validTransactionsCount
    }
}
