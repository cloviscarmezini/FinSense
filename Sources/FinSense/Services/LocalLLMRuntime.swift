import Foundation
import AppKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Modelos de Turno & Resposta da Runtime Neural Local

public struct LLMChatCompletionMessage: Sendable {
    public let role: String // "system", "user", "assistant", "tool"
    public let content: String
    public let toolCallId: String?
    public let toolName: String?
    public let toolCalls: [AIToolCall]?

    public init(
        role: String,
        content: String,
        toolCallId: String? = nil,
        toolName: String? = nil,
        toolCalls: [AIToolCall]? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.toolCalls = toolCalls
    }
}

public struct LLMInferenceTurnResult: Sendable {
    public let thinkingText: String
    public let contentText: String
    public let toolCalls: [AIToolCall]
    public let engineUsed: String

    public init(thinkingText: String, contentText: String, toolCalls: [AIToolCall], engineUsed: String) {
        self.thinkingText = thinkingText
        self.contentText = contentText
        self.toolCalls = toolCalls
        self.engineUsed = engineUsed
    }
}

public enum LocalLLMBackendKind: Equatable, Sendable {
    case llamaCppMetal(modelName: String, binaryPath: String, modelPath: String)
    case customOpenAIEndpoint(endpointURL: String, modelName: String)
    case appleFoundationModels
    case deterministicFallback(reason: String)

    public var displayBadge: String {
        switch self {
        case .llamaCppMetal(let modelName, _, _):
            return "\(modelName) • Metal GPU"
        case .customOpenAIEndpoint(_, let modelName):
            return "\(modelName) • Endpoint Local"
        case .appleFoundationModels:
            return "Apple Intelligence Nativo"
        case .deterministicFallback:
            return "Motor Determinístico Local"
        }
    }

    public var supportsDeepContext: Bool {
        switch self {
        case .llamaCppMetal, .customOpenAIEndpoint:
            return true
        case .appleFoundationModels, .deterministicFallback:
            return false
        }
    }
}

// MARK: - Parser de Blocos <think>...</think> em Streaming e Final

public struct ThinkTagStreamExtractor: Sendable {
    private var rawBuffer: String = ""
    private var insideThink: Bool = false
    private var emittedThinkingCount: Int = 0
    private var emittedContentCount: Int = 0

    public private(set) var accumulatedThinking: String = ""
    public private(set) var accumulatedContent: String = ""

    public init() {}

    /// Alimenta tokens provenientes de `reasoning_content` dedicado (ex: llama-server --reasoning-format deepseek)
    public mutating func appendDedicatedReasoning(_ delta: String) -> String {
        guard !delta.isEmpty else { return "" }
        accumulatedThinking += delta
        return delta
    }

    /// Alimenta texto vindo de `content` que pode conter tags `<think>...</think>`
    public mutating func feedContentDelta(_ delta: String) -> (thinkingDelta: String, contentDelta: String) {
        guard !delta.isEmpty else { return ("", "") }
        rawBuffer += delta
        processBuffer(flushAll: false)

        let tDelta = String(accumulatedThinking.dropFirst(emittedThinkingCount))
        emittedThinkingCount = accumulatedThinking.count

        let cDelta = String(accumulatedContent.dropFirst(emittedContentCount))
        emittedContentCount = accumulatedContent.count
        return (tDelta, cDelta)
    }

    public mutating func finish() -> (thinkingDelta: String, contentDelta: String) {
        processBuffer(flushAll: true)
        let tDelta = String(accumulatedThinking.dropFirst(emittedThinkingCount))
        emittedThinkingCount = accumulatedThinking.count
        let cDelta = String(accumulatedContent.dropFirst(emittedContentCount))
        emittedContentCount = accumulatedContent.count
        return (tDelta, cDelta)
    }

    private mutating func processBuffer(flushAll: Bool) {
        while !rawBuffer.isEmpty {
            if insideThink {
                if let closeRange = rawBuffer.range(of: "</think>") {
                    let chunk = String(rawBuffer[..<closeRange.lowerBound])
                    accumulatedThinking += chunk
                    rawBuffer.removeSubrange(..<closeRange.upperBound)
                    insideThink = false
                } else if flushAll {
                    accumulatedThinking += rawBuffer
                    rawBuffer = ""
                } else {
                    // Segura os últimos 8 caracteres caso `</think>` esteja partido entre chunks
                    let safeCount = max(0, rawBuffer.count - 8)
                    if safeCount > 0 {
                        let idx = rawBuffer.index(rawBuffer.startIndex, offsetBy: safeCount)
                        accumulatedThinking += String(rawBuffer[..<idx])
                        rawBuffer.removeSubrange(..<idx)
                    }
                    break
                }
            } else {
                if let openRange = rawBuffer.range(of: "<think>") {
                    let before = String(rawBuffer[..<openRange.lowerBound])
                    accumulatedContent += before
                    rawBuffer.removeSubrange(..<openRange.upperBound)
                    insideThink = true
                } else if flushAll {
                    accumulatedContent += rawBuffer
                    rawBuffer = ""
                } else {
                    // Segura os últimos 7 caracteres caso `<think>` esteja partido entre chunks
                    let safeCount = max(0, rawBuffer.count - 7)
                    if safeCount > 0 {
                        let idx = rawBuffer.index(rawBuffer.startIndex, offsetBy: safeCount)
                        accumulatedContent += String(rawBuffer[..<idx])
                        rawBuffer.removeSubrange(..<idx)
                    }
                    break
                }
            }
        }
    }

    /// Utilitário síncrono para extrair bloco `<think>...</think>` de uma string completa
    public static func splitThinkingAndContent(from raw: String) -> (thinking: String, content: String) {
        var extractor = ThinkTagStreamExtractor()
        _ = extractor.feedContentDelta(raw)
        _ = extractor.finish()
        return (
            extractor.accumulatedThinking.trimmingCharacters(in: .whitespacesAndNewlines),
            extractor.accumulatedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

// MARK: - Gerenciador do Subprocesso llama-server (Apple Silicon Metal GPU)

@MainActor
public final class LlamaServerProcessManager {
    public static let shared = LlamaServerProcessManager()

    private var serverProcess: Process?
    private var activeModelPath: String?
    private var activeContextSize: Int = 0
    private var activePort: Int = 0
    private var terminateObserver: NSObjectProtocol?

    private init() {
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopServer()
            }
        }
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
    }

    /// Procura o binário `llama-server` instalado no Mac (Homebrew Apple Silicon, Intel, Bundle ou App Support)
    public static func locateLlamaServerBinary() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []

        if let execURL = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(execURL.appendingPathComponent("llama-server").path)
        }
        if let resURL = Bundle.main.resourceURL {
            candidates.append(resURL.appendingPathComponent("bin/llama-server").path)
            candidates.append(resURL.appendingPathComponent("llama-server").path)
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server"
        ])
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(appSupport.appendingPathComponent("FinSense/bin/llama-server").path)
        }

        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    public func stopServer() {
        if let proc = serverProcess, proc.isRunning {
            proc.terminate()
        }
        serverProcess = nil
        activeModelPath = nil
        activePort = 0
    }

    public func ensureRunning(
        binaryPath: String,
        modelPath: String,
        contextSize: Int,
        onStatus: ((String) -> Void)? = nil
    ) async throws -> URL {
        // Reaproveita o servidor se já estiver ativo com o mesmo modelo e contexto
        if let proc = serverProcess,
           proc.isRunning,
           activeModelPath == modelPath,
           activeContextSize == contextSize,
           activePort > 0,
           let url = URL(string: "http://127.0.0.1:\(activePort)"),
           await isHealthy(baseURL: url) {
            return url
        }

        stopServer()

        let port = findAvailablePort(startingAt: 18421)
        let effectiveCtx = max(8192, min(contextSize, 32768))

        onStatus?("Inicializando motor Metal GPU (`llama-server`) com contexto de \(effectiveCtx) tokens...")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            "-m", modelPath,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "-c", "\(effectiveCtx)",
            "-ngl", "99",
            "-fa", "on",
            "--jinja",
            "--reasoning", "auto",
            "--reasoning-format", "deepseek",
            "--no-webui"
        ]
        // Redireciona stdout/stderr para /dev/null para evitar bloqueio de buffer de pipe
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        try proc.run()
        self.serverProcess = proc
        self.activeModelPath = modelPath
        self.activeContextSize = effectiveCtx
        self.activePort = port

        guard let baseURL = URL(string: "http://127.0.0.1:\(port)") else {
            throw NSError(domain: "LlamaServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Porta local inválida"])
        }

        // Aguarda modelo carregar na memória unificada Metal (até 45s para modelos 8B+)
        for attempt in 0..<180 {
            if Task.isCancelled {
                stopServer()
                throw CancellationError()
            }
            if !proc.isRunning {
                stopServer()
                throw NSError(
                    domain: "LlamaServer",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "O servidor llama-server encerrou inesperadamente ao carregar o modelo."]
                )
            }
            if await isHealthy(baseURL: baseURL) {
                return baseURL
            }
            if attempt == 4 {
                onStatus?("Carregando pesos neurais na GPU Apple Silicon (Metal)...")
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        stopServer()
        throw NSError(
            domain: "LlamaServer",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "Tempo limite excedido ao carregar o modelo GGUF no llama-server."]
        )
    }

    private func isHealthy(baseURL: URL) async -> Bool {
        let healthURL = baseURL.appendingPathComponent("health")
        var req = URLRequest(url: healthURL)
        req.timeoutInterval = 1.0
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    return status == "ok"
                }
                return true
            }
        } catch {
            return false
        }
        return false
    }

    private func findAvailablePort(startingAt start: Int) -> Int {
        for candidate in start..<(start + 40) {
            let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else { continue }
            defer { Darwin.close(sock) }
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(candidate).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bindResult == 0 {
                return candidate
            }
        }
        return start
    }
}

// MARK: - Cliente Unificado de Inferência Local (Streaming + Tool Calling + Thinking)

@MainActor
public final class LocalLLMRuntime {
    public static let shared = LocalLLMRuntime()

    /// Modo exclusivo Apple Intelligence (Apple Silicon M1/macOS Nativo).
    /// Mantém integrações antigas (llama.cpp / Hugging Face / HTTP) preservadas em código, porém desativadas e ocultas.
    public static let isAppleIntelligenceExclusiveMode: Bool = true

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private final class AppleSessionBox {
        let session: LanguageModelSession
        init(_ session: LanguageModelSession) { self.session = session }
    }
    private var cachedAppleSessionBox: AnyObject?
    private var cachedAppleSessionThinkingFlag: Bool?
    private var cachedAppleSessionDataRevision: UInt64?
    private var cachedAppleSessionStoreId: ObjectIdentifier?
    private var activeAppleStepHandler: ((String) -> Void)?
    private var activeAppleThinkingHandler: ((String) -> Void)?
    private var collectedAppleSteps: [String] = []
    private var collectedAppleThinkingLines: [String] = []
    #endif

    private init() {}

    /// Determina qual backend real deve ser usado com base na configuração atual e hardware do Mac
    public func resolveActiveBackend(for store: FinancialDataStore) -> LocalLLMBackendKind {
        if Self.isAppleIntelligenceExclusiveMode {
            if Self.isAppleIntelligenceAvailable {
                return .appleFoundationModels
            }
            return .deterministicFallback(reason: "Apple Intelligence indisponível nas Preferências do Sistema deste Mac.")
        }

        // Legado preservado (desabilitado no modo exclusivo Apple Intelligence):
        if let selected = store.llmConfig.selectedModel,
           selected.hasValidGGUFBinary,
           let binaryPath = LlamaServerProcessManager.locateLlamaServerBinary() {
            return .llamaCppMetal(
                modelName: selected.displayName,
                binaryPath: binaryPath,
                modelPath: selected.localPath
            )
        }

        let customEndpoint = store.llmConfig.localEndpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customEndpoint.isEmpty {
            let modelName = store.llmConfig.selectedModel?.displayName ?? "LLM Local HTTP"
            return .customOpenAIEndpoint(endpointURL: customEndpoint, modelName: modelName)
        }

        if Self.isAppleIntelligenceAvailable {
            return .appleFoundationModels
        }

        return .deterministicFallback(reason: "Nenhum modelo GGUF completo ou motor Apple Intelligence disponível no momento.")
    }

    public static var isAppleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    public static func appleIntelligenceStatusDescription() -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Disponível e ativo no Apple Silicon (On-Device)"
            case .unavailable(let reason):
                return "Indisponível (\(String(describing: reason)))"
            }
        }
        #endif
        return "Requer macOS 26+ com Apple Intelligence habilitado"
    }

    public func invalidateAppleSession() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            cachedAppleSessionBox = nil
            cachedAppleSessionThinkingFlag = nil
            cachedAppleSessionDataRevision = nil
        }
        #endif
    }

    /// Pré-aquece os pesos da Apple Intelligence na memória unificada M1 para reduzir latência da primeira resposta
    public func prewarmAppleIntelligence(for store: FinancialDataStore) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), Self.isAppleIntelligenceAvailable {
            let session = ensureNativeAppleSession(
                for: store,
                isThinkingEnabled: store.llmConfig.isThinkingModeEnabled,
                forceNew: false
            )
            session.prewarm()
        }
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func ensureNativeAppleSession(
        for store: FinancialDataStore,
        isThinkingEnabled: Bool,
        forceNew: Bool
    ) -> LanguageModelSession {
        let storeIdentity = ObjectIdentifier(store)
        if !forceNew,
           let box = cachedAppleSessionBox as? AppleSessionBox,
           cachedAppleSessionThinkingFlag == isThinkingEnabled,
           cachedAppleSessionDataRevision == store.dataRevision,
           cachedAppleSessionStoreId == storeIdentity {
            return box.session
        }

        let instructions = FinSenseBusinessKnowledge.buildAppleIntelligenceInstructions(
            store: store,
            isThinkingEnabled: isThinkingEnabled
        )

        let activityCallback: AppleToolActivityHandler = { [weak self] stepLabel, thoughtLine in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.collectedAppleSteps.append(stepLabel)
                self.collectedAppleThinkingLines.append("• \(thoughtLine)")
                self.activeAppleStepHandler?(stepLabel)
                self.activeAppleThinkingHandler?(self.collectedAppleThinkingLines.joined(separator: "\n"))
            }
        }

        let tools = AppleIntelligenceToolFactory.buildAllTools(
            store: store,
            onActivity: activityCallback
        )
        let newSession = LanguageModelSession(tools: tools, instructions: instructions)
        self.cachedAppleSessionBox = AppleSessionBox(newSession)
        self.cachedAppleSessionThinkingFlag = isThinkingEnabled
        self.cachedAppleSessionDataRevision = store.dataRevision
        self.cachedAppleSessionStoreId = storeIdentity
        return newSession
    }
    #endif

    /// Execução rápida, nativa e com tool-calling estruturado via FoundationModels no Apple Silicon M1
    public func runNativeAppleIntelligenceAgentTurn(
        userPrompt: String,
        store: FinancialDataStore,
        isThinkingEnabled: Bool,
        onStepUpdate: ((String) -> Void)?,
        onThinkingUpdate: ((String) -> Void)?,
        onContentUpdate: ((String) -> Void)?
    ) async throws -> (responseMarkdown: String, thinkingContent: String?, executedSteps: [String]) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            collectedAppleSteps = []
            collectedAppleThinkingLines = []
            activeAppleStepHandler = onStepUpdate
            activeAppleThinkingHandler = onThinkingUpdate

            let isExplicitReset = userPrompt.hasPrefix("[NOVA SIMULAÇÃO DO SISTEMA]")
            let isCleanHistory = store.chatHistory.filter({ $0.role == .user || $0.role == .assistant }).count <= 1
            let shouldForceNew = isExplicitReset || isCleanHistory

            let temp = min(max(store.llmConfig.appleIntelligenceTemperature, 0.05), 0.9)
            let maxTokens = isThinkingEnabled
                ? max(800, store.llmConfig.appleIntelligenceMaxResponseTokens)
                : min(750, max(450, store.llmConfig.appleIntelligenceMaxResponseTokens / 2))

            let options = GenerationOptions(
                temperature: isThinkingEnabled ? temp : min(temp, 0.2),
                maximumResponseTokens: maxTokens
            )

            func executeWithSession(_ session: LanguageModelSession, promptText: String) async throws -> String {
                let stream = session.streamResponse(to: promptText, options: options)
                var latestRendered = ""

                for try await partial in stream {
                    if Task.isCancelled { throw CancellationError() }
                    let cleaned = Self.sanitizeAssistantOutput(partial.content)
                    if !cleaned.isEmpty && cleaned != latestRendered {
                        latestRendered = cleaned
                        onContentUpdate?(cleaned)
                    }
                }
                return latestRendered
            }

            let session = ensureNativeAppleSession(
                for: store,
                isThinkingEnabled: isThinkingEnabled,
                forceNew: shouldForceNew
            )

            let effectivePrompt: String = isExplicitReset
                ? userPrompt.replacingOccurrences(of: "[NOVA SIMULAÇÃO DO SISTEMA]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                : userPrompt

            if isThinkingEnabled {
                let initialThought = "🧠 Analisando solicitação e preparando consultas ao banco FinSense..."
                collectedAppleThinkingLines.append(initialThought)
                onThinkingUpdate?(initialThought)
            }

            do {
                let rawReply = try await executeWithSession(session, promptText: effectivePrompt)
                let finalClean = Self.sanitizeAssistantOutput(rawReply)
                let thinkingFinal = collectedAppleThinkingLines.joined(separator: "\n")
                return (
                    finalClean.isEmpty ? "Consulta concluída nos dados locais do FinSense." : finalClean,
                    thinkingFinal.isEmpty ? nil : thinkingFinal,
                    collectedAppleSteps
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Retry automático com sessão limpa e resumo mínimo caso atinja limite da janela de 4K
                invalidateAppleSession()
                let freshSession = ensureNativeAppleSession(
                    for: store,
                    isThinkingEnabled: isThinkingEnabled,
                    forceNew: true
                )
                let retryReply = try await executeWithSession(freshSession, promptText: effectivePrompt)
                let finalClean = Self.sanitizeAssistantOutput(retryReply)
                let thinkingFinal = collectedAppleThinkingLines.joined(separator: "\n")
                return (
                    finalClean.isEmpty ? "Consulta concluída nos dados locais do FinSense." : finalClean,
                    thinkingFinal.isEmpty ? nil : thinkingFinal,
                    collectedAppleSteps
                )
            }
        }
        #endif
        throw NSError(domain: "LocalLLM", code: -6, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence indisponível nesta versão do macOS."])
    }

    /// Remove estritamente qualquer tag residual `<tool_call ...>`, `<think>...</think>` ou artefato de controle antes de exibir ao usuário
    public static func sanitizeAssistantOutput(_ raw: String) -> String {
        var text = ThinkTagStreamExtractor.splitThinkingAndContent(from: raw).content
        let patterns = [
            "<tool_call[\\s\\S]*?</tool_call>",
            "<tool_call[^>]*>",
            "</tool_call>",
            "<think>[\\s\\S]*?</think>",
            "<think>[\\s\\S]*$"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Executa um turno de inferência no modelo neural ativo com streaming em tempo real de Pensamento + Conteúdo + Tool Calls
    public func generateCompletion(
        backend: LocalLLMBackendKind,
        messages: [LLMChatCompletionMessage],
        tools: [any AIToolProtocol],
        isThinkingEnabled: Bool,
        contextSize: Int,
        modelIdForEndpoint: String?,
        onStatus: ((String) -> Void)? = nil,
        onThinkingDelta: ((String) -> Void)? = nil,
        onContentDelta: ((String) -> Void)? = nil
    ) async throws -> LLMInferenceTurnResult {
        switch backend {
        case .llamaCppMetal(_, let binaryPath, let modelPath):
            let baseURL = try await LlamaServerProcessManager.shared.ensureRunning(
                binaryPath: binaryPath,
                modelPath: modelPath,
                contextSize: contextSize,
                onStatus: onStatus
            )
            let chatURL = baseURL.appendingPathComponent("v1/chat/completions")
            return try await streamOpenAIChatCompletion(
                url: chatURL,
                modelName: nil,
                messages: messages,
                tools: tools,
                isThinkingEnabled: isThinkingEnabled,
                engineLabel: backend.displayBadge,
                onThinkingDelta: onThinkingDelta,
                onContentDelta: onContentDelta
            )

        case .customOpenAIEndpoint(let endpointURL, let modelName):
            let cleanBase = endpointURL.hasSuffix("/") ? String(endpointURL.dropLast()) : endpointURL
            let fullString = cleanBase.hasSuffix("/chat/completions") ? cleanBase : "\(cleanBase)/chat/completions"
            guard let chatURL = URL(string: fullString) else {
                throw NSError(domain: "LocalLLM", code: -4, userInfo: [NSLocalizedDescriptionKey: "URL do endpoint local inválida."])
            }
            return try await streamOpenAIChatCompletion(
                url: chatURL,
                modelName: modelIdForEndpoint ?? modelName,
                messages: messages,
                tools: tools,
                isThinkingEnabled: isThinkingEnabled,
                engineLabel: backend.displayBadge,
                onThinkingDelta: onThinkingDelta,
                onContentDelta: onContentDelta
            )

        case .appleFoundationModels:
            return try await runAppleFoundationModelsTurn(
                messages: messages,
                isThinkingEnabled: isThinkingEnabled,
                onThinkingDelta: onThinkingDelta,
                onContentDelta: onContentDelta
            )

        case .deterministicFallback(let reason):
            throw NSError(domain: "LocalLLM", code: -5, userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }

    // MARK: - OpenAI SSE Streaming Client (`llama-server` / Ollama / LM Studio)

    private func streamOpenAIChatCompletion(
        url: URL,
        modelName: String?,
        messages: [LLMChatCompletionMessage],
        tools: [any AIToolProtocol],
        isThinkingEnabled: Bool,
        engineLabel: String,
        onThinkingDelta: ((String) -> Void)?,
        onContentDelta: ((String) -> Void)?
    ) async throws -> LLMInferenceTurnResult {
        var jsonMessages: [[String: Any]] = []
        for m in messages {
            var obj: [String: Any] = ["role": m.role, "content": m.content]
            if let toolCallId = m.toolCallId { obj["tool_call_id"] = toolCallId }
            if let toolName = m.toolName { obj["name"] = toolName }
            if let tCalls = m.toolCalls, !tCalls.isEmpty {
                obj["tool_calls"] = tCalls.map { tc in
                    [
                        "id": tc.id,
                        "type": "function",
                        "function": [
                            "name": tc.name,
                            "arguments": tc.argumentsJson
                        ]
                    ] as [String: Any]
                }
            }
            jsonMessages.append(obj)
        }

        let openAITools: [[String: Any]] = tools.map { t in
            [
                "type": "function",
                "function": [
                    "name": t.name,
                    "description": t.description,
                    "parameters": t.parametersSchema
                ] as [String: Any]
            ]
        }

        var body: [String: Any] = [
            "messages": jsonMessages,
            "stream": true,
            "temperature": isThinkingEnabled ? 0.55 : 0.25,
            "max_tokens": isThinkingEnabled ? 4096 : 2048,
            "chat_template_kwargs": [
                "enable_thinking": isThinkingEnabled
            ]
        ]
        if let modelName, !modelName.isEmpty {
            body["model"] = modelName
        }
        if !openAITools.isEmpty {
            body["tools"] = openAITools
            body["tool_choice"] = "auto"
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 300 // Permite raciocínio longo sem timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(
                domain: "LocalLLM",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Erro HTTP \(http.statusCode) no servidor local de LLM."]
            )
        }

        var extractor = ThinkTagStreamExtractor()
        var pendingToolCallsByIndex: [Int: (id: String, name: String, args: String)] = [:]

        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.hasPrefix("data:") else { continue }
            let payloadStr = trimmedLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payloadStr == "[DONE]" { break }
            guard let data = payloadStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any] else {
                continue
            }

            // 1. Reasoning dedicado (llama-server --reasoning-format deepseek / Qwen3 / DeepSeek-R1)
            if let reasoningDelta = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String),
               !reasoningDelta.isEmpty {
                let emitted = extractor.appendDedicatedReasoning(reasoningDelta)
                if !emitted.isEmpty {
                    onThinkingDelta?(emitted)
                }
            }

            // 2. Content (pode conter também tags <think> inline ou texto final)
            if let contentDelta = delta["content"] as? String, !contentDelta.isEmpty {
                let (tDelta, cDelta) = extractor.feedContentDelta(contentDelta)
                if !tDelta.isEmpty { onThinkingDelta?(tDelta) }
                if !cDelta.isEmpty { onContentDelta?(cDelta) }
            }

            // 3. Acumulação de Tool Calls em Streaming
            if let deltaTools = delta["tool_calls"] as? [[String: Any]] {
                for dt in deltaTools {
                    let idx = (dt["index"] as? Int) ?? 0
                    var entry = pendingToolCallsByIndex[idx] ?? (id: UUID().uuidString, name: "", args: "")
                    if let callId = dt["id"] as? String, !callId.isEmpty {
                        entry.id = callId
                    }
                    if let fn = dt["function"] as? [String: Any] {
                        if let fname = fn["name"] as? String {
                            entry.name += fname
                        }
                        if let fargs = fn["arguments"] as? String {
                            entry.args += fargs
                        }
                    }
                    pendingToolCallsByIndex[idx] = entry
                }
            }
        }

        let (tailT, tailC) = extractor.finish()
        if !tailT.isEmpty { onThinkingDelta?(tailT) }
        if !tailC.isEmpty { onContentDelta?(tailC) }

        let assembledToolCalls = pendingToolCallsByIndex
            .sorted { $0.key < $1.key }
            .compactMap { (_, val) -> AIToolCall? in
                let name = val.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                let args = val.args.trimmingCharacters(in: .whitespacesAndNewlines)
                return AIToolCall(id: val.id, name: name, argumentsJson: args.isEmpty ? "{}" : args)
            }

        return LLMInferenceTurnResult(
            thinkingText: extractor.accumulatedThinking.trimmingCharacters(in: .whitespacesAndNewlines),
            contentText: extractor.accumulatedContent.trimmingCharacters(in: .whitespacesAndNewlines),
            toolCalls: assembledToolCalls,
            engineUsed: engineLabel
        )
    }

    // MARK: - Apple FoundationModels Native On-Device Adapter

    private func runAppleFoundationModelsTurn(
        messages: [LLMChatCompletionMessage],
        isThinkingEnabled: Bool,
        onThinkingDelta: ((String) -> Void)?,
        onContentDelta: ((String) -> Void)?
    ) async throws -> LLMInferenceTurnResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let systemContent = messages.first(where: { $0.role == "system" })?.content ?? ""
            let nonSystem = messages.filter { $0.role != "system" }

            func buildDialog(maxMessages: Int, maxToolChars: Int) -> String {
                nonSystem.suffix(maxMessages).map { msg -> String in
                    switch msg.role {
                    case "user":
                        return "USUÁRIO: \(msg.content)"
                    case "tool":
                        let truncated = msg.content.count > maxToolChars ? String(msg.content.prefix(maxToolChars)) + "..." : msg.content
                        return "RESULTADO DA FERRAMENTA (\(msg.toolName ?? "tool")): \(truncated)"
                    default:
                        let truncated = msg.content.count > 1200 ? String(msg.content.prefix(1200)) + "..." : msg.content
                        return "ASSISTENTE: \(truncated)"
                    }
                }.joined(separator: "\n\n")
            }

            func executeStream(instructionsLimit: Int, maxMessages: Int, maxToolChars: Int) async throws -> LLMInferenceTurnResult {
                let truncatedSystem = systemContent.count > instructionsLimit ? String(systemContent.prefix(instructionsLimit)) : systemContent
                let dialogParts = buildDialog(maxMessages: maxMessages, maxToolChars: maxToolChars)
                let session = LanguageModelSession(instructions: truncatedSystem)

                let stream = session.streamResponse(to: dialogParts)
                var previousLength = 0
                var rawFull = ""
                var extractor = ThinkTagStreamExtractor()

                for try await partial in stream {
                    if Task.isCancelled { throw CancellationError() }
                    let current = partial.content
                    if current.count > previousLength {
                        let idx = current.index(current.startIndex, offsetBy: previousLength)
                        let delta = String(current[idx...])
                        previousLength = current.count
                        rawFull = current
                        let (tDelta, cDelta) = extractor.feedContentDelta(delta)
                        if !tDelta.isEmpty { onThinkingDelta?(tDelta) }
                        if !cDelta.isEmpty { onContentDelta?(cDelta) }
                    }
                }

                let (tailT, tailC) = extractor.finish()
                if !tailT.isEmpty { onThinkingDelta?(tailT) }
                if !tailC.isEmpty { onContentDelta?(tailC) }

                let finalContent = extractor.accumulatedContent.isEmpty
                    ? rawFull
                    : extractor.accumulatedContent

                return LLMInferenceTurnResult(
                    thinkingText: extractor.accumulatedThinking.trimmingCharacters(in: .whitespacesAndNewlines),
                    contentText: finalContent.trimmingCharacters(in: .whitespacesAndNewlines),
                    toolCalls: [],
                    engineUsed: "Apple Intelligence Nativo"
                )
            }

            do {
                return try await executeStream(instructionsLimit: 7200, maxMessages: 8, maxToolChars: 1400)
            } catch {
                // Retry automático com orçamento ultra compacto caso exceda janela de 4K do modelo Apple On-Device
                if !Task.isCancelled {
                    return try await executeStream(instructionsLimit: 3200, maxMessages: 3, maxToolChars: 700)
                }
                throw error
            }
        }
        #endif
        throw NSError(domain: "LocalLLM", code: -6, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence indisponível nesta versão do macOS."])
    }
}

// MARK: - Downloader Real de Pesos GGUF do Hugging Face (Streaming + Progresso em Bytes)

public final class HFModelBinaryDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var onProgressHandler: ((_ bytesWritten: Int64, _ totalBytes: Int64) -> Void)?
    private var session: URLSession?
    private var activeTask: URLSessionDownloadTask?
    private let destinationURL: URL

    public init(destinationURL: URL) {
        self.destinationURL = destinationURL
        super.init()
    }

    public func download(
        from remoteURL: URL,
        token: String,
        onProgress: @escaping (_ bytesWritten: Int64, _ totalBytes: Int64) -> Void
    ) async throws -> URL {
        self.onProgressHandler = onProgress
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 4 // até 4 horas para modelos de vários GB
        let sess = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = sess

        var req = URLRequest(url: remoteURL)
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                let task = sess.downloadTask(with: req)
                self.activeTask = task
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    public func cancel() {
        activeTask?.cancel()
        session?.invalidateAndCancel()
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgressHandler?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let httpResp = downloadTask.response as? HTTPURLResponse, httpResp.statusCode >= 400 {
            let err = NSError(
                domain: "HFDownloader",
                code: httpResp.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Erro HTTP \(httpResp.statusCode) ao baixar arquivo do Hugging Face."]
            )
            continuation?.resume(throwing: err)
            continuation = nil
            session.finishTasksAndInvalidate()
            return
        }

        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: location, to: destinationURL)
            continuation?.resume(returning: destinationURL)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            session.finishTasksAndInvalidate()
        }
    }
}
