// Sources/FinSense/Models/CloudSyncModels.swift
import Foundation

// MARK: - 1. Estado de Sincronização
public enum SyncStatus: Equatable {
    case disabled
    case synced(lastSync: Date)
    case syncing
    case outOfSync(pendingCount: Int, reason: String)
    case authError(message: String)

    public var iconSymbol: String {
        switch self {
        case .disabled: return "icloud"
        case .synced: return "checkmark.icloud.fill"
        case .syncing: return "arrow.triangle.2.circlepath.icloud.fill"
        case .outOfSync: return "exclamationmark.icloud.fill"
        case .authError: return "xmark.icloud.fill"
        }
    }

    public var statusDescription: String {
        switch self {
        case .disabled:
            return "Sincronização em nuvem desativada"
        case .synced(let date):
            return "Sincronizado em \(BRLFormatters.shortDate(date))"
        case .syncing:
            return "Sincronizando com o servidor..."
        case .outOfSync(let count, let reason):
            return "\(count) alteração(ões) pendente(s) • \(reason)"
        case .authError(let msg):
            return "Erro de autenticação: \(msg)"
        }
    }
}

public struct AnyKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?
    public init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    public init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    public init(_ string: String) { self.stringValue = string; self.intValue = nil }
}

// MARK: - 2. Operações e Fila Outbox Local
public enum SyncOperation: String, Codable {
    case insert = "INSERT"
    case update = "UPDATE"
    case upsert = "UPSERT"
    case delete = "DELETE"
}

public struct LocalSyncMutation: Identifiable, Codable, Hashable {
    public var id: UUID // mutation_id idempotente
    public var entityName: String
    public var entityId: UUID
    public var operation: SyncOperation
    public var updatedAt: Date
    public var payloadJSON: String?

    public init(
        id: UUID = UUID(),
        entityName: String,
        entityId: UUID,
        operation: SyncOperation,
        updatedAt: Date = Date(),
        payloadJSON: String? = nil
    ) {
        self.id = id
        self.entityName = entityName
        self.entityId = entityId
        self.operation = operation
        self.updatedAt = updatedAt
        self.payloadJSON = payloadJSON
    }
}

// MARK: - 3. Payload de Envio (Push/Pull Request)
public struct SyncPushPullRequest: Codable {
    public let clientId: String
    public let sinceRevision: Int64
    public let clientLastSyncRevision: Int64
    public let mutations: [SyncMutationDTO]

    public init(clientId: String, sinceRevision: Int64, mutations: [SyncMutationDTO]) {
        self.clientId = clientId
        self.sinceRevision = sinceRevision
        self.clientLastSyncRevision = sinceRevision
        self.mutations = mutations
    }

    public init(clientId: String, clientLastSyncRevision: Int64, mutations: [SyncMutationDTO]) {
        self.clientId = clientId
        self.sinceRevision = clientLastSyncRevision
        self.clientLastSyncRevision = clientLastSyncRevision
        self.mutations = mutations
    }

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case sinceRevision = "since_revision"
        case clientLastSyncRevision = "client_last_sync_revision"
        case mutations
    }
}

public struct SyncMutationDTO: Codable {
    public let mutationId: UUID
    public let entityName: String
    public let entityId: UUID
    public let operation: String
    public let timestamp: String
    public let updatedAt: String
    public let data: [String: AnyCodableValue]?
    public let payload: [String: AnyCodableValue]?

    public init(
        mutationId: UUID,
        entityName: String,
        entityId: UUID,
        operation: String,
        timestamp: String,
        data: [String: AnyCodableValue]? = nil
    ) {
        self.mutationId = mutationId
        self.entityName = entityName
        self.entityId = entityId
        self.operation = operation
        self.timestamp = timestamp
        self.updatedAt = timestamp
        self.data = data
        self.payload = data
    }

    public init(
        mutationId: UUID,
        entityName: String,
        entityId: UUID,
        operation: String,
        updatedAt: String,
        payload: [String: AnyCodableValue]? = nil
    ) {
        self.mutationId = mutationId
        self.entityName = entityName
        self.entityId = entityId
        self.operation = operation
        self.timestamp = updatedAt
        self.updatedAt = updatedAt
        self.data = payload
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case mutationId = "mutation_id"
        case entityName = "entity_name"
        case entityId = "entity_id"
        case operation
        case timestamp
        case updatedAt = "updated_at"
        case data
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mutationId = try container.decode(UUID.self, forKey: .mutationId)
        self.entityName = try container.decode(String.self, forKey: .entityName)
        self.entityId = try container.decode(UUID.self, forKey: .entityId)
        self.operation = try container.decode(String.self, forKey: .operation)

        let timeStr = try? container.decode(String.self, forKey: .timestamp)
        let updateStr = try? container.decode(String.self, forKey: .updatedAt)
        let fallback = ISO8601DateFormatter().string(from: Date())
        let resolved = updateStr ?? timeStr ?? fallback

        self.timestamp = timeStr ?? resolved
        self.updatedAt = updateStr ?? resolved

        let d = try? container.decodeIfPresent([String: AnyCodableValue].self, forKey: .data)
        let p = try? container.decodeIfPresent([String: AnyCodableValue].self, forKey: .payload)
        self.data = d ?? p
        self.payload = p ?? d
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mutationId, forKey: .mutationId)
        try container.encode(entityName, forKey: .entityName)
        try container.encode(entityId, forKey: .entityId)
        try container.encode(operation, forKey: .operation)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(payload, forKey: .payload)
    }
}

// MARK: - 4. Resposta do Servidor (Push/Pull Response)
public struct SyncPushPullResponse: Codable {
    public let latestRevision: Int64
    public let appliedMutationIds: [UUID]
    public let serverChanges: [SyncMutationDTO]?
    public let deltas: SyncDeltasContainerDTO?
    public let tombstones: [SyncTombstoneDTO]?

    public var allAcknowledgedIds: [UUID] {
        appliedMutationIds
    }

    public var serverCurrentRevision: Int64 {
        latestRevision
    }

    public var acknowledgedMutationIds: [UUID] {
        appliedMutationIds
    }

    public init(
        latestRevision: Int64,
        appliedMutationIds: [UUID],
        serverChanges: [SyncMutationDTO]? = nil,
        deltas: SyncDeltasContainerDTO? = nil,
        tombstones: [SyncTombstoneDTO]? = nil
    ) {
        self.latestRevision = latestRevision
        self.appliedMutationIds = appliedMutationIds
        self.serverChanges = serverChanges
        self.deltas = deltas
        self.tombstones = tombstones
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let rev = try? container.decode(Int64.self, forKey: .latestRevision) {
            self.latestRevision = rev
        } else if let rev = try? container.decode(Int64.self, forKey: .serverCurrentRevision) {
            self.latestRevision = rev
        } else {
            self.latestRevision = 0
        }

        if let ids = try? container.decode([UUID].self, forKey: .appliedMutationIds) {
            self.appliedMutationIds = ids
        } else if let ids = try? container.decode([UUID].self, forKey: .acknowledgedMutationIds) {
            self.appliedMutationIds = ids
        } else {
            self.appliedMutationIds = []
        }

        self.serverChanges = try? container.decodeIfPresent([SyncMutationDTO].self, forKey: .serverChanges)
        self.deltas = try? container.decodeIfPresent(SyncDeltasContainerDTO.self, forKey: .deltas)
        self.tombstones = try? container.decodeIfPresent([SyncTombstoneDTO].self, forKey: .tombstones)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latestRevision, forKey: .latestRevision)
        try container.encode(latestRevision, forKey: .serverCurrentRevision)
        try container.encode(appliedMutationIds, forKey: .appliedMutationIds)
        try container.encode(appliedMutationIds, forKey: .acknowledgedMutationIds)
        try container.encodeIfPresent(serverChanges, forKey: .serverChanges)
        try container.encodeIfPresent(deltas, forKey: .deltas)
        try container.encodeIfPresent(tombstones, forKey: .tombstones)
    }

    enum CodingKeys: String, CodingKey {
        case latestRevision = "latest_revision"
        case serverCurrentRevision = "server_current_revision"
        case appliedMutationIds = "applied_mutation_ids"
        case acknowledgedMutationIds = "acknowledged_mutation_ids"
        case serverChanges = "server_changes"
        case deltas
        case tombstones
    }
}

public struct SyncRejectedMutationDTO: Codable {
    public let mutationId: UUID
    public let reason: String

    public init(mutationId: UUID, reason: String) {
        self.mutationId = mutationId
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case mutationId = "mutation_id"
        case reason
    }
}

public struct SyncTombstoneDTO: Codable {
    public let entityName: String
    public let entityId: UUID
    public let deletedAt: String

    public init(entityName: String, entityId: UUID, deletedAt: String) {
        self.entityName = entityName
        self.entityId = entityId
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case entityName = "entity_name"
        case entityId = "entity_id"
        case deletedAt = "deleted_at"
    }
}

public struct SyncDeltasContainerDTO: Codable {
    public let bankAccounts: [BankAccount]?
    public let categories: [CategoryItem]?
    public let financialTransactions: [FinancialTransaction]?
    public let investmentItems: [InvestmentItem]?
    public let debtItems: [DebtItem]?
    public let creditContracts: [CreditContract]?
    public let categoryProvisions: [CategoryProvision]?
    public let categoryQuotaRules: [CategoryQuotaRule]?

    public init(
        bankAccounts: [BankAccount]? = nil,
        categories: [CategoryItem]? = nil,
        financialTransactions: [FinancialTransaction]? = nil,
        investmentItems: [InvestmentItem]? = nil,
        debtItems: [DebtItem]? = nil,
        creditContracts: [CreditContract]? = nil,
        categoryProvisions: [CategoryProvision]? = nil,
        categoryQuotaRules: [CategoryQuotaRule]? = nil
    ) {
        self.bankAccounts = bankAccounts
        self.categories = categories
        self.financialTransactions = financialTransactions
        self.investmentItems = investmentItems
        self.debtItems = debtItems
        self.creditContracts = creditContracts
        self.categoryProvisions = categoryProvisions
        self.categoryQuotaRules = categoryQuotaRules
    }

    enum CodingKeys: String, CodingKey {
        case bankAccounts = "bank_accounts"
        case categories
        case financialTransactions = "financial_transactions"
        case investmentItems = "investment_items"
        case debtItems = "debt_items"
        case creditContracts = "credit_contracts"
        case categoryProvisions = "category_provisions"
        case categoryQuotaRules = "category_quota_rules"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let snakeDecoder = JSONDecoder()
        snakeDecoder.keyDecodingStrategy = .convertFromSnakeCase
        snakeDecoder.dateDecodingStrategy = .iso8601

        func decodeItems<T: Codable>(_ key: CodingKeys) -> [T]? {
            if let direct = try? container.decodeIfPresent([T].self, forKey: key) {
                return direct
            }
            if let anyVals = try? container.decodeIfPresent([AnyCodableValue].self, forKey: key),
               let data = try? JSONEncoder().encode(anyVals),
               let items = try? snakeDecoder.decode([T].self, from: data) {
                return items
            }
            return nil
        }

        self.bankAccounts = decodeItems(.bankAccounts)
        self.categories = decodeItems(.categories)
        self.financialTransactions = decodeItems(.financialTransactions)
        self.investmentItems = decodeItems(.investmentItems)
        self.debtItems = decodeItems(.debtItems)
        self.creditContracts = decodeItems(.creditContracts)
        self.categoryProvisions = decodeItems(.categoryProvisions)
        self.categoryQuotaRules = decodeItems(.categoryQuotaRules)
    }

    public var isEmpty: Bool {
        (bankAccounts?.isEmpty ?? true) &&
        (categories?.isEmpty ?? true) &&
        (financialTransactions?.isEmpty ?? true) &&
        (investmentItems?.isEmpty ?? true) &&
        (debtItems?.isEmpty ?? true) &&
        (creditContracts?.isEmpty ?? true) &&
        (categoryProvisions?.isEmpty ?? true) &&
        (categoryQuotaRules?.isEmpty ?? true)
    }
}

// MARK: - 5. Tipo Utilitário para Payload Dinâmico
public struct AnyCodableValue: Codable, Hashable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public static func string(_ s: String) -> AnyCodableValue { AnyCodableValue(s) }
    public static func int(_ i: Int) -> AnyCodableValue { AnyCodableValue(i) }
    public static func double(_ d: Double) -> AnyCodableValue { AnyCodableValue(d) }
    public static func bool(_ b: Bool) -> AnyCodableValue { AnyCodableValue(b) }

    public static func == (lhs: AnyCodableValue, rhs: AnyCodableValue) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Tipo não suportado")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            let wrapped = array.map { AnyCodableValue($0) }
            try container.encode(wrapped)
        case let dict as [String: Any]:
            let wrapped = dict.mapValues { AnyCodableValue($0) }
            try container.encode(wrapped)
        default:
            try container.encode(String(describing: value))
        }
    }
}
