import Foundation

/// Protocolo base determinístico para ferramentas invocáveis pelo motor de IA.
@MainActor
public protocol AIToolProtocol: Sendable {
    /// Identificador único da função (ex: "simulate_amortization", "get_contract_details")
    var name: String { get }

    /// Descrição clara e concisa para o System Prompt do modelo
    var description: String { get }

    /// Esquema dos parâmetros aceitos em formato compatível com JSON Schema
    var parametersSchema: [String: Any] { get }

    /// Executa a ferramenta de forma assíncrona recebendo parâmetros e retornando resultado em dicionário
    func execute(parameters: [String: Any]) async throws -> [String: Any]
}

/// Representa uma chamada de ferramenta gerada pela LLM ou pelo orquestrador
public struct AIToolCall: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let argumentsJson: String

    public init(id: String = UUID().uuidString, name: String, argumentsJson: String) {
        self.id = id
        self.name = name
        self.argumentsJson = argumentsJson
    }

    public var parsedArguments: [String: Any] {
        guard let data = argumentsJson.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}

/// Representa o resultado da execução determinística de uma ferramenta
public struct AIToolResult: @unchecked Sendable {
    public let toolCallId: String
    public let toolName: String
    public let result: [String: Any]
    public let error: String?

    public init(toolCallId: String, toolName: String, result: [String: Any], error: String? = nil) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.result = result
        self.error = error
    }

    public var resultJson: String {
        if let err = error {
            return "{\"error\": \"\(err.replacingOccurrences(of: "\"", with: "\\\""))\"}"
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}

/// Registro de evento de capacidade não suportada (Fallback Feedback Loop)
public struct UnsupportedCapabilityEvent: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let requestedCapability: String
    public let reason: String
    public let requiredData: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        requestedCapability: String,
        reason: String,
        requiredData: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.requestedCapability = requestedCapability
        self.reason = reason
        self.requiredData = requiredData
        self.timestamp = timestamp
    }
}
