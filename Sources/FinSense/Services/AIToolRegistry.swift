import Foundation

/// Registro centralizado e thread-safe para ferramentas determinísticas de IA.
@MainActor
public final class AIToolRegistry {
    public static let shared = AIToolRegistry()

    private var registeredTools: [String: any AIToolProtocol] = [:]
    private var logs: [UnsupportedCapabilityEvent] = []

    public init() {}

    /// Registra uma nova ferramenta no registro central com 1 linha de código
    public func register(_ tool: any AIToolProtocol) {
        registeredTools[tool.name] = tool
    }

    /// Remove ferramenta por nome
    public func unregister(name: String) {
        registeredTools.removeValue(forKey: name)
    }

    /// Retorna ferramenta cadastrada
    public func tool(named name: String) -> (any AIToolProtocol)? {
        registeredTools[name]
    }

    /// Retorna todas as ferramentas registradas
    public var allTools: [any AIToolProtocol] {
        Array(registeredTools.values).sorted { $0.name < $1.name }
    }

    /// Limpa todas as ferramentas
    public func removeAll() {
        registeredTools.removeAll()
    }

    /// Executa uma ferramenta determinística passando parâmetros
    public func execute(name: String, parameters: [String: Any]) async throws -> [String: Any] {
        guard let tool = tool(named: name) else {
            recordUnsupportedCapability(
                requestedCapability: name,
                reason: "A ferramenta '\(name)' não está registrada no AIToolRegistry.",
                requiredData: "Registro prévio de implementação de AIToolProtocol para '\(name)'."
            )
            return [
                "status": "unsupported",
                "tool": name,
                "error": "Ferramenta '\(name)' não encontrada no registro de capacidades nativas."
            ]
        }
        return try await tool.execute(parameters: parameters)
    }

    // MARK: - Fallback Feedback Loop & Logs de Capacidades Faltantes

    public var unsupportedCapabilityLogs: [UnsupportedCapabilityEvent] {
        logs
    }

    public func recordUnsupportedCapability(
        requestedCapability: String,
        reason: String,
        requiredData: String
    ) {
        let event = UnsupportedCapabilityEvent(
            requestedCapability: requestedCapability,
            reason: reason,
            requiredData: requiredData
        )
        logs.append(event)
        #if DEBUG
        print("⚠️ [AIToolRegistry] Capacidade não suportada registrada: '\(requestedCapability)'. Razão: \(reason)")
        #endif
    }

    public func clearUnsupportedCapabilityLogs() {
        logs.removeAll()
    }

    // MARK: - Gerador Dinâmico de Documentação para System Prompt

    public func generateToolsDocumentation() -> String {
        let tools = allTools
        guard !tools.isEmpty else {
            return "Nenhuma ferramenta determinística externa registrada no momento."
        }

        var jsonTools: [[String: Any]] = []
        for t in tools {
            jsonTools.append([
                "name": t.name,
                "description": t.description,
                "parameters": t.parametersSchema
            ])
        }

        var docsJsonString = "[]"
        if let data = try? JSONSerialization.data(withJSONObject: jsonTools, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            docsJsonString = str
        }

        return """
        FERRAMENTAS DETERMINÍSTICAS NATIVAS DISPONÍVEIS:
        \(docsJsonString)

        INSTRUÇÕES PARA CHAMADA DE FERRAMENTAS (TOOL CALLING):
        1. Para obter fatos reais do banco de dados, simular amortizações ou calcular fluxos de caixa, emita uma chamada de ferramenta estritamente no formato JSON:
        ```json
        {
          "tool": "nome_da_ferramenta",
          "parameters": {
            "parametro1": "valor"
          }
        }
        ```
        2. FALLBACK OBRIGATÓRIO: Se o usuário solicitar qualquer análise, projeção ou ação para a qual NÃO exista uma ferramenta correspondente listada acima, você NUNCA deve inventar números ou fazer contas de cabeça. Chame OBRIGATORIAMENTE a ferramenta "unsupported_capability":
        ```json
        {
          "tool": "unsupported_capability",
          "parameters": {
            "requestedCapability": "descrição da ação pedida",
            "reason": "por que não pode atender com as ferramentas atuais",
            "requiredData": "dados ou ferramentas que precisariam ser implementados"
          }
        }
        ```
        3. Após receber o retorno da ferramenta (role: tool), use as informações reais fornecidas para formular sua resposta conclusiva, clara e amigável em Markdown.
        """
    }
}
