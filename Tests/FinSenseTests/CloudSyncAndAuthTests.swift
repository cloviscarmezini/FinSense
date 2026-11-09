// Tests/FinSenseTests/CloudSyncAndAuthTests.swift
import XCTest
@testable import FinSense

@MainActor
final class CloudSyncAndAuthTests: XCTestCase {

    func testKeychainHelperOperations() {
        let keychain = KeychainHelper.shared
        let testKey = "test_auth_token_\(UUID().uuidString)"
        let testValue = "jwt_access_token_sample_12345"

        // 1. Initial read should be nil
        XCTAssertNil(keychain.read(key: testKey))

        // 2. Save and verify read
        keychain.save(key: testKey, value: testValue)
        XCTAssertEqual(keychain.read(key: testKey), testValue)

        // 3. Delete and verify nil
        keychain.delete(key: testKey)
        XCTAssertNil(keychain.read(key: testKey))
    }

    func testAuthModelsSerialization() throws {
        let userId = UUID()
        let user = UserSummary(id: userId, email: "clovis@example.com", fullName: "Clovis Test")
        let authResponse = AuthResponse(
            accessToken: "access_123",
            refreshToken: "refresh_456",
            tokenType: "Bearer",
            expiresIn: 900,
            user: user
        )

        let data = try JSONEncoder().encode(authResponse)
        let decoded = try JSONDecoder().decode(AuthResponse.self, from: data)

        XCTAssertEqual(decoded.accessToken, "access_123")
        XCTAssertEqual(decoded.refreshToken, "refresh_456")
        XCTAssertEqual(decoded.user.email, "clovis@example.com")
        XCTAssertEqual(decoded.user.fullName, "Clovis Test")
        XCTAssertEqual(decoded.user.id, userId)
    }

    func testCloudSyncModelsAndAnyCodableValue() throws {
        let mutationId = UUID()
        let entityId = UUID()
        let dateString = "2026-11-08T12:00:00Z"

        let mutation = SyncMutationDTO(
            mutationId: mutationId,
            entityName: "financial_transactions",
            entityId: entityId,
            operation: "UPSERT",
            updatedAt: dateString,
            payload: [
                "amount": .double(125.50),
                "title": .string("Mercado"),
                "isPaid": .bool(true)
            ]
        )

        let req = SyncPushPullRequest(
            clientId: "test_client_01",
            clientLastSyncRevision: 10,
            mutations: [mutation]
        )

        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(SyncPushPullRequest.self, from: data)

        XCTAssertEqual(decoded.clientId, "test_client_01")
        XCTAssertEqual(decoded.clientLastSyncRevision, 10)
        XCTAssertEqual(decoded.mutations.count, 1)
        XCTAssertEqual(decoded.mutations[0].mutationId, mutationId)
        XCTAssertEqual(decoded.mutations[0].entityName, "financial_transactions")

        if let payload = decoded.mutations[0].payload {
            XCTAssertEqual(payload["title"], .string("Mercado"))
            XCTAssertEqual(payload["isPaid"], .bool(true))
        } else {
            XCTFail("Payload should not be nil")
        }
    }

    func testSyncGatingConditionWhenNotAuthenticated() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let store = FinancialDataStore(customDirectory: tempDir)
        let syncService = CloudSyncService(store: store)
        store.cloudSyncService = syncService

        // Garantir que AuthService está deslogado para o teste
        AuthService.shared.logout()

        // 1. Mesmo se isEnabled = true, canSync DEVE ser false se deslogado
        syncService.isEnabled = true
        XCTAssertFalse(syncService.canSync, "canSync deve ser falso quando o usuário não estiver autenticado")

        // 2. Tentar registrar mutação com sincronização desabilitada não deve enfileirar nada
        syncService.isEnabled = false
        let txId = UUID()
        syncService.recordLocalMutation(entityName: "financial_transactions", entityId: txId, operation: .delete)
        XCTAssertEqual(syncService.pendingMutationsCount, 0, "Nenhuma mutação deve ser enfileirada se isEnabled for falso")

        // 3. Status deve permanecer disabled quando deslogado
        syncService.performSync()
        XCTAssertEqual(syncService.syncStatus, .disabled)
    }

    func testOutboxPersistenceAndRestoration() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let store = FinancialDataStore(customDirectory: tempDir)
        let syncService = CloudSyncService(store: store)
        store.cloudSyncService = syncService

        // Simula usuário autenticado e sync ativado
        let dummyUser = UserSummary(id: UUID(), email: "test@finsense.com", fullName: "User Test")
        let dummyAuth = AuthResponse(accessToken: "tok", refreshToken: "ref", tokenType: "Bearer", expiresIn: 900, user: dummyUser)
        AuthService.shared.saveSession(dummyAuth)
        syncService.isEnabled = true

        XCTAssertTrue(syncService.canSync)

        // Grava mutações locais
        let tx = FinancialTransaction(
            name: "Almoço",
            amount: 45.0,
            date: Date(),
            type: .expense,
            categoryId: UUID(),
            accountId: UUID()
        )
        syncService.recordLocalMutation(entityName: "financial_transactions", entityId: tx.id, operation: .upsert, entity: tx)
        XCTAssertEqual(syncService.pendingMutationsCount, 1)

        // Cria nova instância do CloudSyncService apontando para o mesmo diretório
        let restoredService = CloudSyncService(store: store)
        XCTAssertEqual(restoredService.pendingMutationsCount, 1, "A fila de mutações deve ser restaurada do disco atomicamente")

        // Limpeza
        AuthService.shared.logout()
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSyncMutationDTODecodingWithOmittedUpdatedAtOrTimestamp() throws {
        // Testa a resposta real enviada pelo backend Go onde updated_at é omitido por omitempty
        let jsonWithoutUpdatedAt = """
        {
            "mutation_id": "c948e4cf-3456-4a8d-948b-56fe9d4b94f0",
            "entity_name": "financial_transactions",
            "entity_id": "2fdb22cd-c48e-4a8d-948b-56fe9d4b94f0",
            "operation": "INSERT",
            "timestamp": "2026-11-08T22:43:21.74302+00:00",
            "data": {
                "name": "Supermercado",
                "amount": 150.0
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SyncMutationDTO.self, from: jsonWithoutUpdatedAt)
        XCTAssertEqual(decoded.entityName, "financial_transactions")
        XCTAssertEqual(decoded.operation, "INSERT")
        XCTAssertEqual(decoded.timestamp, "2026-11-08T22:43:21.74302+00:00")
        XCTAssertEqual(decoded.updatedAt, "2026-11-08T22:43:21.74302+00:00", "Deve usar timestamp como fallback quando updated_at for omitido")
        XCTAssertEqual(decoded.data?["name"], .string("Supermercado"))

        // Testa payload com apenas updated_at
        let jsonWithoutTimestamp = """
        {
            "mutation_id": "c948e4cf-3456-4a8d-948b-56fe9d4b94f0",
            "entity_name": "bank_accounts",
            "entity_id": "38d3008b-b356-4976-973a-caf0788c1b0e",
            "operation": "UPDATE",
            "updated_at": "2026-11-08T20:00:00Z"
        }
        """.data(using: .utf8)!

        let decoded2 = try decoder.decode(SyncMutationDTO.self, from: jsonWithoutTimestamp)
        XCTAssertEqual(decoded2.timestamp, "2026-11-08T20:00:00Z", "Deve usar updated_at como fallback quando timestamp for omitido")
    }

    func testSyncDeltasContainerDTODecodingFromSnakeCase() throws {
        let json = """
        {
            "bank_accounts": [
                {
                    "id": "38d3008b-b356-4976-973a-caf0788c1b0e",
                    "name": "Itaú Unibanco",
                    "bank_preset_id": "itau",
                    "icon_symbol": "building.columns.fill",
                    "color_hex": "#EC7000",
                    "initial_balance": 2500.50,
                    "agency": "1234",
                    "account_number": "56789-0",
                    "created_at": "2026-11-08T22:43:21.74302+00:00"
                }
            ],
            "categories": [
                {
                    "id": "10000000-0000-0000-0000-000000000001",
                    "name": "Alimentação",
                    "type": "expense",
                    "icon_symbol": "fork.knife",
                    "color_hex": "#EF4444",
                    "keywords": ["mercado", "comida"],
                    "is_system_default": true
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let deltas = try decoder.decode(SyncDeltasContainerDTO.self, from: json)

        XCTAssertEqual(deltas.bankAccounts?.count, 1)
        XCTAssertEqual(deltas.bankAccounts?.first?.name, "Itaú Unibanco")
        XCTAssertEqual(deltas.bankAccounts?.first?.initialBalance, 2500.50)
        XCTAssertEqual(deltas.bankAccounts?.first?.bankPresetId, "itau")

        XCTAssertEqual(deltas.categories?.count, 1)
        XCTAssertEqual(deltas.categories?.first?.name, "Alimentação")
    }

    func testCloudSyncSettingsToggleReactivityAndCombinePiping() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let store = FinancialDataStore(customDirectory: tempDir)
        let syncService = CloudSyncService(store: store)
        store.cloudSyncService = syncService

        var storeNotificationCount = 0
        let cancellable = store.objectWillChange.sink {
            storeNotificationCount += 1
        }

        // Alterar isEnabled no CloudSyncService deve propagar sinal para o store
        syncService.isEnabled = true
        XCTAssertTrue(syncService.isEnabled)
        XCTAssertGreaterThan(storeNotificationCount, 0, "Mudança de estado no CloudSyncService deve notificar o FinancialDataStore via Combine")

        cancellable.cancel()
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testAutoSeedWhenServerEmptyAndLocalStoreHasData() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let store = FinancialDataStore(customDirectory: tempDir)
        let syncService = CloudSyncService(store: store)
        store.cloudSyncService = syncService

        // Cria contas e transações locais
        let acc = BankAccount(id: UUID(), name: "Conta Teste", initialBalance: 1000.0)
        let cat = CategoryItem(id: UUID(), name: "Mercado", type: .expense, iconSymbol: "cart", colorHex: "#FF0000")
        let tx = FinancialTransaction(id: UUID(), name: "Compras", amount: 50.0, date: Date(), type: .expense, categoryId: cat.id, accountId: acc.id)

        store.accounts.append(acc)
        store.categories.append(cat)
        store.transactions.append(tx)

        // Limpa outbox para simular base pré-existente
        syncService.resetSyncState()
        XCTAssertEqual(syncService.pendingMutationsCount, 0)

        // Dispara auto-seed
        syncService.enqueueAllLocalData()

        XCTAssertGreaterThan(syncService.pendingMutationsCount, 0, "enqueueAllLocalData deve enfileirar entidades locais para envio automático")
        XCTAssertTrue(syncService.outboxMutations.contains(where: { $0.entityName == "bank_accounts" && $0.entityId == acc.id }))
        XCTAssertTrue(syncService.outboxMutations.contains(where: { $0.entityName == "categories" && $0.entityId == cat.id }))
        XCTAssertTrue(syncService.outboxMutations.contains(where: { $0.entityName == "financial_transactions" && $0.entityId == tx.id }))

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLastWriteWinsClientSideConflictResolution() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let store = FinancialDataStore(customDirectory: tempDir)
        let syncService = CloudSyncService(store: store)
        store.cloudSyncService = syncService
        syncService.isEnabled = true

        let entityId = UUID()
        let catId = UUID()
        let accId = UUID()

        // Local edit at 10:00 AM
        let localActionDate = Date()
        let localTx = FinancialTransaction(id: entityId, name: "Picolé", amount: 6.0, date: localActionDate, type: .expense, categoryId: catId, accountId: accId)
        store.transactions.append(localTx)

        let payloadData = try? JSONEncoder().encode(localTx)
        let payloadStr = payloadData.flatMap { String(data: $0, encoding: .utf8) }

        let localMutation = LocalSyncMutation(
            entityName: "financial_transactions",
            entityId: entityId,
            operation: .insert,
            updatedAt: localActionDate,
            payloadJSON: payloadStr
        )
        syncService.enqueueMutationForTesting(localMutation)

        // Simula recebimento de DELETE do servidor ocorrido às 9:00 AM (mais antigo que a edição local)
        let olderServerDate = localActionDate.addingTimeInterval(-3600)
        let olderDelete = SyncMutationDTO(
            mutationId: UUID(),
            entityName: "financial_transactions",
            entityId: entityId,
            operation: "DELETE",
            timestamp: ISO8601DateFormatter().string(from: olderServerDate)
        )

        let response = SyncPushPullResponse(
            latestRevision: 10,
            appliedMutationIds: [],
            serverChanges: [olderDelete]
        )

        syncService.applyServerChangesForTesting(response, into: store)

        // A transação NÃO deve ser deletada, pois a alteração local é mais recente (10AM vs 9AM)
        XCTAssertTrue(store.transactions.contains(where: { $0.id == entityId }), "Edição local mais recente (10AM) deve prevalecer sobre exclusão remota anterior (9AM)")
        XCTAssertEqual(store.transactions.first(where: { $0.id == entityId })?.amount, 6.0)

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testResetFromScratchOptionCloudResetDefaultStateAndSyncReset() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let store = FinancialDataStore(customDirectory: tempDir)
        let syncService = CloudSyncService(store: store)
        store.cloudSyncService = syncService

        // Popula base com transações e itens
        let acc = BankAccount(id: UUID(), name: "Conta 1", initialBalance: 500)
        let cat = CategoryItem(id: UUID(), name: "Lazer", type: .expense, iconSymbol: "star", colorHex: "#00FF00")
        let tx = FinancialTransaction(id: UUID(), name: "Cinema", amount: 40, date: Date(), type: .expense, categoryId: cat.id, accountId: acc.id)
        store.accounts = [acc]
        store.categories = [cat]
        store.transactions = [tx]

        syncService.lastServerRevision = 42
        syncService.lastSyncDate = Date()
        syncService.enqueueMutationForTesting(LocalSyncMutation(entityName: "financial_transactions", entityId: tx.id, operation: .insert, updatedAt: Date(), payloadJSON: nil))
        XCTAssertEqual(syncService.pendingMutationsCount, 1)

        // Ao recomeçar do zero localmente (opção de zerar nuvem desmarcada)
        store.resetSelectedData(Set(ResetDataTarget.allCases))

        // Verifica que localmente foi zerado e o estado de sincronização foi limpo sem enfileirar deletes indesejados
        XCTAssertTrue(store.transactions.isEmpty)
        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertTrue(store.categories.isEmpty)
        XCTAssertEqual(syncService.pendingMutationsCount, 0, "Outbox deve ser limpa para não deletar a nuvem por engano")
        XCTAssertEqual(syncService.lastServerRevision, 0, "Revisão deve ser resetada para 0 para permitir re-sync limpo")

        try? FileManager.default.removeItem(at: tempDir)
    }
}
