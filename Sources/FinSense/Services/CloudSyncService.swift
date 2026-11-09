// Sources/FinSense/Services/CloudSyncService.swift
import Foundation
import Combine
import Network
import SwiftUI

@MainActor
public final class CloudSyncService: ObservableObject {
    @Published public var syncStatus: SyncStatus = .disabled
    @Published public var isSyncing: Bool = false
    @Published public var pendingMutationsCount: Int = 0
    @Published public var lastSyncDate: Date? = nil

    // Progressão de Envio Inicial (Seed)
    @Published public var isSeeding: Bool = false
    @Published public var seedProgress: Double = 0.0
    @Published public var seedStatusText: String = ""

    // Configurações persistidas
    @AppStorage("cloud_sync_enabled") public var isEnabled: Bool = false
    @AppStorage("cloud_sync_base_url") public var baseURLString: String = "http://localhost:8080/api/v1"
    @AppStorage("cloud_sync_client_id") public var clientId: String = UUID().uuidString
    @AppStorage("cloud_sync_last_revision") public var lastServerRevision: Int = 0

    public var canSync: Bool {
        AuthService.shared.isAuthenticated && isEnabled
    }

    private var outboxQueue: [LocalSyncMutation] = []
    private let outboxFileURL: URL
    private var debounceTimer: AnyCancellable? = nil
    private var authCancellable: AnyCancellable? = nil
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable: Bool = true
    private weak var store: FinancialDataStore?

    public init(store: FinancialDataStore) {
        self.store = store
        self.outboxFileURL = store.storageDirectory.appendingPathComponent("sync_outbox_queue.json")
        loadOutboxQueue()
        startNetworkMonitoring()
        startAuthMonitoring()
        evaluateInitialStatus()
    }

    public func resetSyncState() {
        lastServerRevision = 0
        lastSyncDate = nil
        outboxQueue.removeAll()
        saveOutboxQueue()
        pendingMutationsCount = 0
        evaluateInitialStatus()
    }

    private func startAuthMonitoring() {
        authCancellable = AuthService.shared.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuth in
                guard let self else { return }
                self.evaluateInitialStatus()
                if isAuth {
                    if !self.isEnabled {
                        self.isEnabled = true
                    }
                    self.scheduleSync(delaySeconds: 0.5)
                }
            }
    }

    public func evaluateInitialStatus() {
        if !canSync {
            syncStatus = .disabled
        } else if !outboxQueue.isEmpty {
            syncStatus = .outOfSync(pendingCount: outboxQueue.count, reason: "Alterações pendentes")
        } else if let last = lastSyncDate {
            syncStatus = .synced(lastSync: last)
        } else {
            syncStatus = .synced(lastSync: Date())
        }
    }

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isNetworkAvailable = (path.status == .satisfied)
                if self.isNetworkAvailable && self.canSync {
                    self.scheduleSync(delaySeconds: 1.0)
                } else if !self.isNetworkAvailable && self.canSync {
                    self.syncStatus = .outOfSync(pendingCount: self.outboxQueue.count, reason: "Sem conexão com a internet")
                }
            }
        }
        let queue = DispatchQueue(label: "br.com.finsense.syncNetworkMonitor")
        networkMonitor.start(queue: queue)
    }

    // Helper para enfileirar sem duplicatas para a mesma entidade
    private func enqueueMutation(_ mutation: LocalSyncMutation) {
        if let existingIndex = outboxQueue.firstIndex(where: { $0.entityName == mutation.entityName && $0.entityId == mutation.entityId }) {
            outboxQueue[existingIndex] = mutation
        } else {
            outboxQueue.append(mutation)
        }
    }

    // Gravação da mutação local (acionada pelo FinancialDataStore)
    public func recordLocalMutation(
        entityName: String,
        entityId: UUID,
        operation: SyncOperation
    ) {
        recordLocalMutation(entityName: entityName, entityId: entityId, operation: operation, entity: Optional<String>.none)
    }

    public func recordLocalMutation<T: Codable>(
        entityName: String,
        entityId: UUID,
        operation: SyncOperation,
        entity: T? = nil
    ) {
        guard isEnabled else { return }

        let payloadJSON: String? = {
            guard let entity, operation != .delete else { return nil }
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(entity),
                  let str = String(data: data, encoding: .utf8) else { return nil }
            return str
        }()

        let mutation = LocalSyncMutation(
            entityName: entityName,
            entityId: entityId,
            operation: operation,
            updatedAt: Date(),
            payloadJSON: payloadJSON
        )

        enqueueMutation(mutation)
        saveOutboxQueue()
        pendingMutationsCount = outboxQueue.count
        syncStatus = .outOfSync(pendingCount: outboxQueue.count, reason: "Alterações locais pendentes")

        if canSync {
            scheduleSync(delaySeconds: 3.0)
        }
    }

    private func scheduleSync(delaySeconds: Double) {
        guard canSync, isNetworkAvailable, !isSeeding else { return }
        debounceTimer?.cancel()
        debounceTimer = Just(())
            .delay(for: .seconds(delaySeconds), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.performSync()
            }
    }

    public func performSync() {
        guard canSync else {
            syncStatus = .disabled
            return
        }
        guard isNetworkAvailable else {
            syncStatus = .outOfSync(pendingCount: outboxQueue.count, reason: "Sem conexão com a internet")
            return
        }
        guard !isSyncing, !isSeeding else { return }

        isSyncing = true
        syncStatus = .syncing

        Task {
            await executeSyncPushPull()
        }
    }

    private func executeSyncPushPull() async {
        guard let store else {
            isSyncing = false
            return
        }

        let effectiveSinceRevision: Int64
        if store.transactions.isEmpty && store.accounts.isEmpty && store.categories.isEmpty {
            effectiveSinceRevision = 0
        } else {
            effectiveSinceRevision = Int64(lastServerRevision)
        }

        let batchToSend = Array(outboxQueue.prefix(250))
        let payload = SyncPushPullRequest(
            clientId: clientId,
            sinceRevision: effectiveSinceRevision,
            mutations: batchToSend.map { mut in
                // Converte operação para padrão SQL esperado pela restrição de banco (INSERT, UPDATE, DELETE)
                let opString: String = {
                    switch mut.operation {
                    case .upsert, .insert: return "INSERT"
                    case .update: return "UPDATE"
                    case .delete: return "DELETE"
                    }
                }()

                let dataMap: [String: AnyCodableValue]? = {
                    guard let json = mut.payloadJSON, let rawData = json.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode([String: AnyCodableValue].self, from: rawData)
                }()

                return SyncMutationDTO(
                    mutationId: mut.id,
                    entityName: mut.entityName,
                    entityId: mut.entityId,
                    operation: opString,
                    timestamp: ISO8601DateFormatter().string(from: mut.updatedAt),
                    data: dataMap
                )
            }
        )

        do {
            let response = try await BackendAPIClient.shared.pushPull(
                baseURL: baseURLString,
                requestPayload: payload
            )

            let ackSet = Set(response.allAcknowledgedIds)
            outboxQueue.removeAll { ackSet.contains($0.id) }
            saveOutboxQueue()
            pendingMutationsCount = outboxQueue.count

            applyServerChanges(response, into: store)

            lastServerRevision = Int(response.latestRevision)
            let now = Date()
            lastSyncDate = now

            if outboxQueue.isEmpty {
                syncStatus = .synced(lastSync: now)
            } else {
                syncStatus = .outOfSync(pendingCount: outboxQueue.count, reason: "Enviando próximo lote...")
                scheduleSync(delaySeconds: 0.5)
            }
        } catch {
            let msg = error.localizedDescription
            syncStatus = .outOfSync(pendingCount: outboxQueue.count, reason: msg.isEmpty ? "Servidor indisponível" : msg)
        }

        isSyncing = false
    }

    private func applyServerChanges(_ response: SyncPushPullResponse, into store: FinancialDataStore) {
        let decoder = BackendAPIClient.makeFlexibleDateDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        var appliedChangesCount = 0

        if let changes = response.serverChanges, !changes.isEmpty {
            for change in changes {
                if change.operation == "DELETE" {
                    switch change.entityName {
                    case "financial_transactions": store.transactions.removeAll { $0.id == change.entityId }
                    case "bank_accounts": store.accounts.removeAll { $0.id == change.entityId }
                    case "categories": store.categories.removeAll { $0.id == change.entityId }
                    case "investment_items": store.investments.removeAll { $0.id == change.entityId }
                    case "debt_items": store.debts.removeAll { $0.id == change.entityId }
                    case "credit_contracts": store.contracts.removeAll { $0.id == change.entityId }
                    case "category_provisions": store.provisions.removeAll { $0.id == change.entityId }
                    case "category_quota_rules": store.categoryQuotas.removeAll { $0.id == change.entityId }
                    default: break
                    }
                    appliedChangesCount += 1
                } else if let dataMap = change.data ?? change.payload,
                          let rawData = try? JSONEncoder().encode(dataMap) {
                    do {
                        switch change.entityName {
                        case "financial_transactions":
                            let item = try decoder.decode(FinancialTransaction.self, from: rawData)
                            if let idx = store.transactions.firstIndex(where: { $0.id == item.id }) { store.transactions[idx] = item }
                            else { store.transactions.append(item) }
                            appliedChangesCount += 1
                        case "bank_accounts":
                            let item = try decoder.decode(BankAccount.self, from: rawData)
                            if let idx = store.accounts.firstIndex(where: { $0.id == item.id }) { store.accounts[idx] = item }
                            else { store.accounts.append(item) }
                            appliedChangesCount += 1
                        case "categories":
                            let item = try decoder.decode(CategoryItem.self, from: rawData)
                            if let idx = store.categories.firstIndex(where: { $0.id == item.id }) { store.categories[idx] = item }
                            else { store.categories.append(item) }
                            appliedChangesCount += 1
                        case "investment_items":
                            let item = try decoder.decode(InvestmentItem.self, from: rawData)
                            if let idx = store.investments.firstIndex(where: { $0.id == item.id }) { store.investments[idx] = item }
                            else { store.investments.append(item) }
                            appliedChangesCount += 1
                        case "debt_items":
                            let item = try decoder.decode(DebtItem.self, from: rawData)
                            if let idx = store.debts.firstIndex(where: { $0.id == item.id }) { store.debts[idx] = item }
                            else { store.debts.append(item) }
                            appliedChangesCount += 1
                        case "credit_contracts":
                            let item = try decoder.decode(CreditContract.self, from: rawData)
                            if let idx = store.contracts.firstIndex(where: { $0.id == item.id }) { store.contracts[idx] = item }
                            else { store.contracts.append(item) }
                            appliedChangesCount += 1
                        case "category_provisions":
                            let item = try decoder.decode(CategoryProvision.self, from: rawData)
                            if let idx = store.provisions.firstIndex(where: { $0.id == item.id }) { store.provisions[idx] = item }
                            else { store.provisions.append(item) }
                            appliedChangesCount += 1
                        case "category_quota_rules":
                            let item = try decoder.decode(CategoryQuotaRule.self, from: rawData)
                            if let idx = store.categoryQuotas.firstIndex(where: { $0.id == item.id }) { store.categoryQuotas[idx] = item }
                            else { store.categoryQuotas.append(item) }
                            appliedChangesCount += 1
                        default: break
                        }
                    } catch {
                        print("⚠️ [applyServerChanges] Falha ao decodificar \(change.entityName) id=\(change.entityId): \(error)")
                    }
                }
            }
        }

        if appliedChangesCount == 0, let deltas = response.deltas {
            applyDeltasToLocalStore(deltas, tombstones: response.tombstones ?? [], into: store)
        } else {
            store.save()
        }
    }

    private func applyDeltasToLocalStore(
        _ deltas: SyncDeltasContainerDTO,
        tombstones: [SyncTombstoneDTO],
        into store: FinancialDataStore
    ) {
        // Aplicação de tombstones
        for tomb in tombstones {
            switch tomb.entityName {
            case "financial_transactions": store.transactions.removeAll { $0.id == tomb.entityId }
            case "bank_accounts": store.accounts.removeAll { $0.id == tomb.entityId }
            case "categories": store.categories.removeAll { $0.id == tomb.entityId }
            case "investment_items": store.investments.removeAll { $0.id == tomb.entityId }
            case "debt_items": store.debts.removeAll { $0.id == tomb.entityId }
            case "credit_contracts": store.contracts.removeAll { $0.id == tomb.entityId }
            case "category_provisions": store.provisions.removeAll { $0.id == tomb.entityId }
            case "category_quota_rules": store.categoryQuotas.removeAll { $0.id == tomb.entityId }
            default: break
            }
        }

        // Aplicação de upserts
        if let txs = deltas.financialTransactions {
            for item in txs {
                if let idx = store.transactions.firstIndex(where: { $0.id == item.id }) { store.transactions[idx] = item }
                else { store.transactions.append(item) }
            }
        }
        if let accounts = deltas.bankAccounts {
            for item in accounts {
                if let idx = store.accounts.firstIndex(where: { $0.id == item.id }) { store.accounts[idx] = item }
                else { store.accounts.append(item) }
            }
        }
        if let categories = deltas.categories {
            for item in categories {
                if let idx = store.categories.firstIndex(where: { $0.id == item.id }) { store.categories[idx] = item }
                else { store.categories.append(item) }
            }
        }
        if let investments = deltas.investmentItems {
            for item in investments {
                if let idx = store.investments.firstIndex(where: { $0.id == item.id }) { store.investments[idx] = item }
                else { store.investments.append(item) }
            }
        }
        if let debts = deltas.debtItems {
            for item in debts {
                if let idx = store.debts.firstIndex(where: { $0.id == item.id }) { store.debts[idx] = item }
                else { store.debts.append(item) }
            }
        }
        if let contracts = deltas.creditContracts {
            for item in contracts {
                if let idx = store.contracts.firstIndex(where: { $0.id == item.id }) { store.contracts[idx] = item }
                else { store.contracts.append(item) }
            }
        }
        if let provisions = deltas.categoryProvisions {
            for item in provisions {
                if let idx = store.provisions.firstIndex(where: { $0.id == item.id }) { store.provisions[idx] = item }
                else { store.provisions.append(item) }
            }
        }
        if let quotas = deltas.categoryQuotaRules {
            for item in quotas {
                if let idx = store.categoryQuotas.firstIndex(where: { $0.id == item.id }) { store.categoryQuotas[idx] = item }
                else { store.categoryQuotas.append(item) }
            }
        }

        store.save()
    }

    public func triggerInitialSeed() {
        guard let store, canSync, !isSeeding else { return }

        isSeeding = true
        seedProgress = 0.0
        seedStatusText = "Iniciando preparação da base..."

        let accounts = store.accounts
        let categories = store.categories
        let transactions = store.transactions
        let investments = store.investments
        let debts = store.debts
        let contracts = store.contracts
        let provisions = store.provisions
        let quotas = store.categoryQuotas
        let totalCount = accounts.count + categories.count + transactions.count + investments.count + debts.count + contracts.count + provisions.count + quotas.count

        Task { [weak self] in
            guard let self else { return }

            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601

            var processed = 0
            var allMutations: [LocalSyncMutation] = []
            allMutations.reserveCapacity(totalCount)

            @MainActor
            func processBatch<T: Codable & Sendable>(items: [T], entityName: String, idKeyPath: KeyPath<T, UUID> & Sendable, progressLabel: String) async {
                let mutations = await Task.detached(priority: .userInitiated) { () -> [LocalSyncMutation] in
                    var batchList: [LocalSyncMutation] = []
                    batchList.reserveCapacity(items.count)
                    for item in items {
                        let entityId = item[keyPath: idKeyPath]
                        let payloadJSON: String? = {
                            guard let data = try? encoder.encode(item) else { return nil }
                            return String(data: data, encoding: .utf8)
                        }()
                        let mutation = LocalSyncMutation(
                            entityName: entityName,
                            entityId: entityId,
                            operation: .insert,
                            updatedAt: Date(),
                            payloadJSON: payloadJSON
                        )
                        batchList.append(mutation)
                    }
                    return batchList
                }.value

                allMutations.append(contentsOf: mutations)
                processed += items.count
                self.seedProgress = totalCount > 0 ? Double(processed) / Double(totalCount) : 1.0
                self.seedStatusText = "\(progressLabel) (\(processed)/\(totalCount))..."
                await Task.yield()
            }

            await processBatch(items: accounts, entityName: "bank_accounts", idKeyPath: \.id, progressLabel: "Contas")
            await processBatch(items: categories, entityName: "categories", idKeyPath: \.id, progressLabel: "Categorias")
            await processBatch(items: transactions, entityName: "financial_transactions", idKeyPath: \.id, progressLabel: "Transações")
            await processBatch(items: investments, entityName: "investment_items", idKeyPath: \.id, progressLabel: "Investimentos")
            await processBatch(items: debts, entityName: "debt_items", idKeyPath: \.id, progressLabel: "Dívidas")
            await processBatch(items: contracts, entityName: "credit_contracts", idKeyPath: \.id, progressLabel: "Contratos")
            await processBatch(items: provisions, entityName: "category_provisions", idKeyPath: \.id, progressLabel: "Provisões")
            await processBatch(items: quotas, entityName: "category_quota_rules", idKeyPath: \.id, progressLabel: "Cotas")

            for mutation in allMutations {
                self.enqueueMutation(mutation)
            }
            self.saveOutboxQueue()
            self.pendingMutationsCount = self.outboxQueue.count
            self.isSeeding = false
            self.seedProgress = 1.0
            self.seedStatusText = ""
            self.syncStatus = .outOfSync(pendingCount: self.outboxQueue.count, reason: "Pronto para sincronizar")

            self.performSync()
        }
    }

    private func saveOutboxQueue() {
        guard let data = try? JSONEncoder().encode(outboxQueue) else { return }
        try? data.write(to: outboxFileURL, options: .atomic)
    }

    private func loadOutboxQueue() {
        guard let data = try? Data(contentsOf: outboxFileURL),
              let decoded = try? JSONDecoder().decode([LocalSyncMutation].self, from: data) else {
            self.outboxQueue = []
            return
        }

        // Deduplicação automática: preserva apenas a versão mais recente de cada entidade
        var deduped: [LocalSyncMutation] = []
        var seen = Set<String>()
        for mut in decoded.reversed() {
            let key = "\(mut.entityName)_\(mut.entityId)"
            if !seen.contains(key) {
                seen.insert(key)
                deduped.append(mut)
            }
        }
        self.outboxQueue = deduped.reversed()
        self.pendingMutationsCount = self.outboxQueue.count
    }
}
