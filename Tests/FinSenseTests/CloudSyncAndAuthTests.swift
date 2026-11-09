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
}
