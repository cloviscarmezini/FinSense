import Foundation

/// Orquestrador de conversação financeira multi-turno orientado a ferramentas (Super Agente ReAct Local).
@MainActor
public final class AIChatOrchestrator: ObservableObject {
    public static let shared = AIChatOrchestrator()

    public let registry: AIToolRegistry
    public var maxSlidingWindowMessages: Int = 18
    public var maxToolExecutionHops: Int = 8
    /// Permite forçar execução determinística pura em testes unitários isolados
    public var forceDeterministicFallbackForTesting: Bool = false
    /// Alvo pendente quando o usuário clica em "Simular Prazo" e a IA aguarda a escolha do ritmo (Agressivo / Moderado / Leve)
    public var pendingSimulationTarget: PendingSimulationTarget? = nil
    /// Último alvo simulado para permitir alternância direta de ritmo ("E no Moderado?")
    public var lastSimulatedTarget: PendingSimulationTarget? = nil

    public init(registry: AIToolRegistry? = nil) {
        self.registry = registry ?? .shared
    }

    /// Registra todas as ferramentas nativas com acesso irrestrito ao banco local para uma instância de FinancialDataStore
    public func registerStandardTools(for store: FinancialDataStore) {
        registry.register(QueryDatabaseTool(store: store))
        registry.register(GetFinancialOverviewTool(store: store))
        registry.register(GetContractDetailsTool(store: store))
        registry.register(SimulateAmortizationTool(store: store))
        registry.register(GetLoanProjectionAndPlanTool(store: store))
        registry.register(GetMonthlyCashFlowTool(store: store))
        registry.register(GetProjectedCashFlowRangeTool(store: store))
        registry.register(AnalyzeDiscretionarySpendingTool(store: store))
        registry.register(GetBudgetCapsStatusTool(store: store))
        registry.register(QueryTransactionsTool(store: store))
        registry.register(AggregateTransactionsTool(store: store))
        registry.register(GetInvestmentsSummaryTool(store: store))
        registry.register(AnalyzeDebtPayoffStrategyTool(store: store))
        registry.register(InternetLookupTool(store: store))
        registry.register(UnsupportedCapabilityTool(registry: registry))
    }

    // MARK: - Ciclo de Execução Multi-Turno

    public struct TurnOutput: Sendable {
        public let responseMarkdown: String
        public let thinkingContent: String?
        public let executedSteps: [String]
        public let followUps: [String]
        public let shouldClose: Bool
        public let engineUsed: String
    }

    /// Versão completa com suporte a Thinking Mode e Streaming em tempo real
    public func processTurnWithThinking(
        userPrompt: String,
        store: FinancialDataStore,
        modelLabel: String,
        isThinkingEnabled: Bool,
        onStepUpdate: ((String) -> Void)? = nil,
        onThinkingUpdate: ((String) -> Void)? = nil,
        onContentUpdate: ((String) -> Void)? = nil
    ) async -> TurnOutput {
        registerStandardTools(for: store)

        var executedSteps: [String] = []
        func logStep(_ text: String) {
            executedSteps.append(text)
            onStepUpdate?(text)
        }

        let cleanPrompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        logStep("💬 Orquestrador: Analisando solicitação '\(cleanPrompt.prefix(50))\(cleanPrompt.count > 50 ? "..." : "")'")

        // 1. Verifica encerramento educado imediato
        if isPoliteClosingIntent(cleanPrompt) {
            let goodbye = """
            Por nada! Fico à disposição sempre que precisar analisar seus números, simular amortizações ou planejar seu fluxo de caixa. Conversa encerrada com sucesso.
            """
            return TurnOutput(
                responseMarkdown: goodbye,
                thinkingContent: nil,
                executedSteps: executedSteps,
                followUps: [],
                shouldClose: true,
                engineUsed: modelLabel
            )
        }

        // 1B. Interceptação da Simulação Interativa em 2 Etapas (Simular Prazo: Dívidas vs Contratos)
        let promptMeta = InteractivePayoffPlanner.extractMetadata(from: cleanPrompt, store: store)
        let normCleanPrompt = promptMeta.cleanPrompt
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()

        let saveTargetContextBreadcrumb: (PendingSimulationTarget, String) -> Void = { target, stage in
            let kindStr: String
            let idStr: String
            let nameStr: String
            switch target {
            case .debt(let id, let name):
                kindStr = "debt"
                idStr = id.uuidString
                nameStr = name
            case .contract(let id, let name, _):
                kindStr = "contract"
                idStr = id.uuidString
                nameStr = name
            }
            let obj: [String: Any] = [
                "kind": kindStr,
                "id": idStr,
                "name": nameStr,
                "stage": stage
            ]
            if let data = try? JSONSerialization.data(withJSONObject: obj),
               let jsonStr = String(data: data, encoding: .utf8) {
                store.chatHistory.append(
                    ChatMessage(
                        role: .tool,
                        content: jsonStr,
                        timestamp: Date(),
                        modelUsed: modelLabel,
                        toolName: "interactive_simulation_context",
                        toolCallId: UUID().uuidString
                    )
                )
            }
        }

        if let explicitTarget = promptMeta.target {
            pendingSimulationTarget = explicitTarget
            lastSimulatedTarget = nil
            LocalLLMRuntime.shared.invalidateAppleSession()
        }

        // Caso chat livre peça "simular/simule prazo" sem ritmo nem valor mensal explícito, identifica o alvo exato citado
        let hasSimulIntent = normCleanPrompt.contains("simul") &&
            (normCleanPrompt.contains("prazo") || normCleanPrompt.contains("quitar") || normCleanPrompt.contains("divid") || normCleanPrompt.contains("emprest") || normCleanPrompt.contains("financiament"))
        let specifiesMonthlyAmount = normCleanPrompt.contains("/mes") || normCleanPrompt.contains("por mes") || normCleanPrompt.contains("mensal de r$")
        if pendingSimulationTarget == nil &&
           hasSimulIntent &&
           PayoffIntensity.parse(from: promptMeta.cleanPrompt) == nil &&
           !normCleanPrompt.contains("monte um plano de acao") &&
           !specifiesMonthlyAmount {
            if let matchedDebt = store.activeDebts.first(where: {
                let dNorm = $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
                let noStopwords = dNorm.split(separator: " ").filter { $0.count >= 4 }.map(String.init)
                return (!dNorm.isEmpty && normCleanPrompt.contains(dNorm)) || (!noStopwords.isEmpty && noStopwords.allSatisfy { normCleanPrompt.contains($0) })
            }) ?? (normCleanPrompt.contains("divid") && store.activeDebts.count == 1 ? store.activeDebts.first : nil) {
                pendingSimulationTarget = .debt(id: matchedDebt.id, name: matchedDebt.name)
                LocalLLMRuntime.shared.invalidateAppleSession()
            } else if normCleanPrompt.contains("financiament") || normCleanPrompt.contains("emprest") || normCleanPrompt.contains("contrat"),
                      let matchedContract = matchBestContract(in: normCleanPrompt, store: store) {
                pendingSimulationTarget = .contract(id: matchedContract.id, name: matchedContract.name, kind: matchedContract.kind)
                LocalLLMRuntime.shared.invalidateAppleSession()
            }
        }

        // 2. Determina se há backend neural configurado no store (ou se estamos em teste/fallback determinístico)
        let hasConfiguredAI = store.hasInstalledLLMModel || !store.llmConfig.localEndpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let backend = LocalLLMRuntime.shared.resolveActiveBackend(for: store)

        let serializeJson: ([String: Any]) -> String = { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
                  let str = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return str.count > 3600 ? String(str.prefix(3600)) + "...}" : str
        }

        // ETAPA 1: Perguntar Agressivo / Moderado / Leve antes de calcular datas e valores
        let shouldAskIntensityFirst: Bool = {
            if promptMeta.askIntensityFirst && pendingSimulationTarget != nil && PayoffIntensity.parse(from: promptMeta.cleanPrompt) == nil {
                return true
            }
            if pendingSimulationTarget != nil &&
               hasSimulIntent &&
               PayoffIntensity.parse(from: promptMeta.cleanPrompt) == nil &&
               !normCleanPrompt.contains("monte um plano de acao") {
                return true
            }
            return false
        }()

        if shouldAskIntensityFirst, let clarTarget = pendingSimulationTarget {
            logStep("🗄️ Consultando banco local FinSense: alvo, contas, reservas e Saldo Previsto de \(BRLFormatters.shortDate(store.endOfMonth(for: store.selectedMonth)))...")
            logStep("🎯 Perguntando o ritmo desejado (Agressivo, Moderado ou Leve) antes de calcular datas e valores...")
            saveTargetContextBreadcrumb(clarTarget, "awaiting_intensity")
            let clarPayload = InteractivePayoffPlanner.buildClarificationPayload(target: clarTarget, store: store)
            let fallbackMd = InteractivePayoffPlanner.buildClarificationFallbackMarkdown(target: clarTarget, store: store)
            let clarFollowUps = ["Plano Agressivo", "Plano Moderado", "Plano Leve"]

            if !forceDeterministicFallbackForTesting, hasConfiguredAI, case .appleFoundationModels = backend {
                let isDebtTarget = clarTarget.isDebt
                let forbiddenRule = isDebtTarget
                    ? "PROIBIDO chamar de empréstimo/financiamento/amortização: trata-se exclusivamente de uma DÍVIDA EM ABERTO (guardar dinheiro pouco a pouco)."
                    : "Trata-se de contrato parcelado (empréstimo/financiamento com plano de amortização)."
                let directive = """
                ANTES DE PROPOR QUALQUER VALOR MENSAL OU DATA DE QUITAÇÃO:
                - \(forbiddenRule)
                - Confirme qual é o alvo exato e informe apenas o valor/saldo atual no banco local e o Saldo Previsto na data de fechamento (\(clarPayload["dataReferenciaFechamentoMes"] ?? "")).
                - NÃO escreva estimativas em R$/mês (NÃO diga R$ 0,00/mês nem invente parcelas/percentuais); os valores exatos serão calculados apenas após a escolha nos meses em que houver saldo positivo no fechamento.
                - Pergunte claramente se o usuário prefere o ritmo **Agressivo**, **Moderado** ou **Leve**.
                """
                if let appleOut = try? await LocalLLMRuntime.shared.runNativeAppleIntelligenceAgentTurn(
                    userPrompt: promptMeta.cleanPrompt,
                    store: store,
                    isThinkingEnabled: isThinkingEnabled,
                    preGroundedContext: (steps: executedSteps, compactJson: serializeJson(clarPayload), directive: directive),
                    onStepUpdate: onStepUpdate,
                    onThinkingUpdate: onThinkingUpdate,
                    onContentUpdate: nil
                ) {
                    let md = appleOut.responseMarkdown
                    let mentionsAllChoices = md.localizedCaseInsensitiveContains("agressiv") &&
                        md.localizedCaseInsensitiveContains("moderad") &&
                        md.localizedCaseInsensitiveContains("leve")
                    let expectedSaldoStr = (clarPayload["saldoPrevistoNaDataReferencia"] as? String) ?? ""
                    let saldoPreserved = expectedSaldoStr.isEmpty || md.contains(expectedSaldoStr)
                    let containsPrematureMonthlyValues = md.contains("0,00/m") || md.contains("0.00/m") || md.contains("/mês")
                    let confusedDebtWithLoan = isDebtTarget && (md.localizedCaseInsensitiveContains("empréstim") || md.localizedCaseInsensitiveContains("emprestim") || md.localizedCaseInsensitiveContains("amortiza"))
                    let useAppleDraft = mentionsAllChoices && saldoPreserved && !containsPrematureMonthlyValues && !confusedDebtWithLoan
                    return TurnOutput(
                        responseMarkdown: useAppleDraft ? md : fallbackMd,
                        thinkingContent: appleOut.thinkingContent,
                        executedSteps: executedSteps + appleOut.executedSteps,
                        followUps: clarFollowUps,
                        shouldClose: false,
                        engineUsed: backend.displayBadge
                    )
                }
            }

            return TurnOutput(
                responseMarkdown: fallbackMd,
                thinkingContent: isThinkingEnabled ? "Consultei o banco local FinSense e identifiquei o alvo; aguardando escolha do ritmo (Agressivo, Moderado ou Leve) para calcular datas e valores reais mês a mês." : nil,
                executedSteps: executedSteps,
                followUps: clarFollowUps,
                shouldClose: false,
                engineUsed: !forceDeterministicFallbackForTesting && hasConfiguredAI ? backend.displayBadge : modelLabel
            )
        }

        // ETAPA 2: Usuário escolheu Agressivo / Moderado / Leve -> recupera contexto durável e calcula mês a mês
        let recoveredTarget = pendingSimulationTarget
            ?? InteractivePayoffPlanner.recoverTargetFromHistory(store.chatHistory, store: store)
            ?? lastSimulatedTarget
        if let simTarget = recoveredTarget,
           let chosenIntensity = PayoffIntensity.parse(from: promptMeta.cleanPrompt) {
            logStep("📆 Consultando meses futuros no banco local e calculando plano \(chosenIntensity.displayTitle) mês a mês com fechamento do mês + impacto futuro...")
            let simResult = InteractivePayoffPlanner.simulateDetailedPlan(
                target: simTarget,
                intensity: chosenIntensity,
                store: store
            )
            pendingSimulationTarget = nil
            lastSimulatedTarget = simTarget
            saveTargetContextBreadcrumb(simTarget, "completed")

            let alternativeFollowUps: [String] = PayoffIntensity.allCases
                .filter { $0 != chosenIntensity }
                .map { "Simular no ritmo \($0.displayTitle)" } + ["Obrigado, pode encerrar"]

            let jsonString = serializeJson(simResult.payload)
            let toolRecord = ChatMessage(
                role: .tool,
                content: jsonString,
                timestamp: Date(),
                modelUsed: modelLabel,
                toolName: simTarget.isDebt ? "interactive_debt_savings_plan" : "interactive_contract_amortization_plan",
                toolCallId: UUID().uuidString
            )
            store.chatHistory.append(toolRecord)

            if !forceDeterministicFallbackForTesting, hasConfiguredAI, case .appleFoundationModels = backend {
                let terminologyGuard = simTarget.isDebt
                    ? "TRATA-SE DE UMA DÍVIDA EM ABERTO (NÃO É EMPRÉSTIMO NEM FINANCIAMENTO). É PROIBIDO usar as palavras empréstimo, financiamento ou amortização; fale apenas em guardar dinheiro pouco a pouco nos meses positivos."
                    : "Trata-se de contrato de crédito com parcelas mensais e amortização."
                let directive = """
                \(terminologyGuard)
                Escreva APENAS uma introdução executiva curta (2 frases objetivas em português) apresentando o plano \(chosenIntensity.displayTitle), SEM desenhar tabela nem inventar valores (o cronograma completo com todas as datas e valores verificados já será exibido logo abaixo).
                COPIE EXATAMENTE a data de quitação do JSON sem alterá-la.
                """
                if let appleOut = try? await LocalLLMRuntime.shared.runNativeAppleIntelligenceAgentTurn(
                    userPrompt: promptMeta.cleanPrompt,
                    store: store,
                    isThinkingEnabled: isThinkingEnabled,
                    preGroundedContext: (steps: executedSteps, compactJson: jsonString, directive: directive),
                    onStepUpdate: onStepUpdate,
                    onThinkingUpdate: onThinkingUpdate,
                    onContentUpdate: nil
                ) {
                    let intro = appleOut.responseMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
                    let payoffDate = (simResult.payload["dataQuitacaoPrevista"] as? String)
                        ?? (simResult.payload["dataQuitacaoPossivel"] as? String)
                        ?? ""
                    let origMaturity = (simResult.payload["dataOriginalTermino"] as? String) ?? ""
                    let wrongDebtTerms = simTarget.isDebt && (
                        intro.localizedCaseInsensitiveContains("empréstim") ||
                        intro.localizedCaseInsensitiveContains("emprestim") ||
                        intro.localizedCaseInsensitiveContains("amortiza") ||
                        intro.localizedCaseInsensitiveContains("financiam")
                    )
                    let introValid = !intro.isEmpty &&
                        !intro.contains("|") &&
                        !intro.contains("---") &&
                        !wrongDebtTerms &&
                        (origMaturity.isEmpty || origMaturity == payoffDate || !intro.contains(origMaturity))
                    let finalMd = introValid
                        ? "\(intro)\n\n---\n\n\(simResult.markdown)"
                        : simResult.markdown
                    return TurnOutput(
                        responseMarkdown: finalMd,
                        thinkingContent: appleOut.thinkingContent,
                        executedSteps: executedSteps + appleOut.executedSteps,
                        followUps: Array(alternativeFollowUps.prefix(3)),
                        shouldClose: false,
                        engineUsed: backend.displayBadge
                    )
                }
            }

            return TurnOutput(
                responseMarkdown: simResult.markdown,
                thinkingContent: isThinkingEnabled ? "Cronograma \(chosenIntensity.displayTitle) calculado mês a mês considerando exclusivamente os meses positivos e o impacto no Saldo Previsto futuro." : nil,
                executedSteps: executedSteps,
                followUps: Array(alternativeFollowUps.prefix(3)),
                shouldClose: false,
                engineUsed: !forceDeterministicFallbackForTesting && hasConfiguredAI ? backend.displayBadge : modelLabel
            )
        } else if pendingSimulationTarget != nil {
            let asksAboutSimulation = normCleanPrompt.contains("ritmo") || normCleanPrompt.contains("diferenca") || normCleanPrompt.contains("qual melhor")
            if !asksAboutSimulation {
                pendingSimulationTarget = nil
            }
        }

        if !forceDeterministicFallbackForTesting,
           hasConfiguredAI,
           case .deterministicFallback = backend {
            // Nenhum modelo nem Apple Intelligence disponível mesmo após tentativa
            logStep("⚠️ Nenhuma runtime neural local ativa; utilizando motor determinístico.")
        }

        if !forceDeterministicFallbackForTesting, hasConfiguredAI {
            if case .appleFoundationModels = backend {
                do {
                    logStep("🍎 Executando nativamente via Apple Intelligence (Apple Silicon M1)...")
                    let appleOut = try await LocalLLMRuntime.shared.runNativeAppleIntelligenceAgentTurn(
                        userPrompt: cleanPrompt,
                        store: store,
                        isThinkingEnabled: isThinkingEnabled,
                        onStepUpdate: onStepUpdate,
                        onThinkingUpdate: onThinkingUpdate,
                        onContentUpdate: onContentUpdate
                    )
                    let finalSteps = executedSteps + appleOut.executedSteps
                    let followUps = generateSmartFollowUps(
                        prompt: cleanPrompt,
                        usedTools: appleOut.executedSteps,
                        store: store
                    )
                    return TurnOutput(
                        responseMarkdown: appleOut.responseMarkdown,
                        thinkingContent: appleOut.thinkingContent,
                        executedSteps: finalSteps,
                        followUps: followUps,
                        shouldClose: false,
                        engineUsed: backend.displayBadge
                    )
                } catch is CancellationError {
                    return TurnOutput(
                        responseMarkdown: "_Geração interrompida pelo usuário._",
                        thinkingContent: nil,
                        executedSteps: executedSteps,
                        followUps: ["Continuar análise", "Fazer outra pergunta"],
                        shouldClose: false,
                        engineUsed: backend.displayBadge
                    )
                } catch {
                    logStep("⚠️ Falha pontual no Apple Intelligence (\(error.localizedDescription)); acionando contingência determinística.")
                }
            } else if case .deterministicFallback = backend {
                // cai para determinístico abaixo
            } else {
                do {
                    return try await runNeuralReActLoop(
                        userPrompt: cleanPrompt,
                        store: store,
                        backend: backend,
                        isThinkingEnabled: isThinkingEnabled,
                        initialSteps: executedSteps,
                        logStep: logStep,
                        onStepUpdate: onStepUpdate,
                        onThinkingUpdate: onThinkingUpdate,
                        onContentUpdate: onContentUpdate
                    )
                } catch is CancellationError {
                    return TurnOutput(
                        responseMarkdown: "_Geração interrompida pelo usuário._",
                        thinkingContent: nil,
                        executedSteps: executedSteps,
                        followUps: ["Continuar análise", "Fazer outra pergunta"],
                        shouldClose: false,
                        engineUsed: backend.displayBadge
                    )
                } catch {
                    logStep("⚠️ Falha na inferência neural (\(error.localizedDescription)); acionando contingência determinística.")
                }
            }
        }

        // 3. Fallback determinístico (também usado em testes unitários sem modelo instalado)
        let det = await runDeterministicFallback(
            userPrompt: cleanPrompt,
            store: store,
            modelLabel: modelLabel,
            initialSteps: executedSteps,
            logStep: logStep,
            onStepUpdate: onStepUpdate
        )
        return TurnOutput(
            responseMarkdown: det.responseMarkdown,
            thinkingContent: isThinkingEnabled ? "Modo determinístico local acionado (sem runtime neural carregada)." : nil,
            executedSteps: det.executedSteps,
            followUps: det.followUps,
            shouldClose: det.shouldClose,
            engineUsed: modelLabel
        )
    }

    /// Compatibilidade retroativa com assinatura anterior (mantém testes unitários 100% compatíveis)
    public func processTurn(
        userPrompt: String,
        store: FinancialDataStore,
        modelLabel: String,
        onStepUpdate: ((String) -> Void)? = nil
    ) async -> (responseMarkdown: String, executedSteps: [String], followUps: [String], shouldClose: Bool) {
        let out = await processTurnWithThinking(
            userPrompt: userPrompt,
            store: store,
            modelLabel: modelLabel,
            isThinkingEnabled: store.llmConfig.isThinkingModeEnabled,
            onStepUpdate: onStepUpdate
        )
        return (out.responseMarkdown, out.executedSteps, out.followUps, out.shouldClose)
    }

    // MARK: - Loop Agêntico ReAct Neural Real (Multi-Hop + Tools Ilimitadas + Thinking)

    private func runNeuralReActLoop(
        userPrompt: String,
        store: FinancialDataStore,
        backend: LocalLLMBackendKind,
        isThinkingEnabled: Bool,
        initialSteps: [String],
        logStep: (String) -> Void,
        onStepUpdate: ((String) -> Void)?,
        onThinkingUpdate: ((String) -> Void)?,
        onContentUpdate: ((String) -> Void)?
    ) async throws -> TurnOutput {
        var collectedSteps = initialSteps
        func record(_ text: String) {
            collectedSteps.append(text)
            logStep(text)
        }
        let compactMode = !backend.supportsDeepContext
        let toolsDoc = compactMode ? registry.generateCompactToolsDocumentation() : registry.generateToolsDocumentation()
        let masterSystemPrompt = FinSenseBusinessKnowledge.buildMasterSystemPrompt(
            store: store,
            toolsDocumentation: toolsDoc,
            isThinkingEnabled: isThinkingEnabled,
            compactMode: compactMode
        )

        ensureSystemPrompt(masterSystemPrompt, store: store)
        applySlidingWindow(store: store)
        record("🧠 Motor ativo: \(backend.displayBadge) • Pensamento: \(isThinkingEnabled ? "Ativado" : "Direto")")

        // Aviso informativo transparente se o modelo selecionado tiver arquivo GGUF incompleto
        if let sel = store.llmConfig.selectedModel,
           !sel.isBuiltInAppleIntelligence,
           !sel.hasValidGGUFBinary,
           case .appleFoundationModels = backend {
            record("ℹ️ Arquivo local de '\(sel.displayName)' é apenas manifesto. Usando Apple Intelligence Nativo como motor neural.")
        }

        // Constrói histórico base de mensagens para o turno
        var loopMessages: [LLMChatCompletionMessage] = [
            LLMChatCompletionMessage(role: "system", content: masterSystemPrompt)
        ]

        let nonSystem = store.chatHistory.filter { $0.role != .system }
        // Evita duplicar a última mensagem se já estiver em store.chatHistory
        let historySlice = Array(nonSystem.suffix(compactMode ? 8 : 16))
        for msg in historySlice {
            loopMessages.append(
                LLMChatCompletionMessage(
                    role: msg.role.rawValue,
                    content: msg.content,
                    toolCallId: msg.toolCallId,
                    toolName: msg.toolName,
                    toolCalls: msg.toolCalls
                )
            )
        }
        // Garante que a pergunta atual esteja no final (caso `processTurnWithThinking` seja chamado sem apendar antes)
        if historySlice.last?.role != .user || historySlice.last?.content != userPrompt {
            loopMessages.append(LLMChatCompletionMessage(role: "user", content: userPrompt))
        }

        var accumulatedThinkingParts: [String] = []
        var liveThinkingAccumulator = ""
        var executedCallSignatures: Set<String> = []
        var usedToolsNames: [String] = []
        var finalMarkdown = ""

        for hop in 0..<maxToolExecutionHops {
            if Task.isCancelled { throw CancellationError() }

            let isLastPossibleHop = (hop == maxToolExecutionHops - 1)
            let toolsForHop: [any AIToolProtocol] = isLastPossibleHop ? [] : registry.allTools
            let stepPrefix = isThinkingEnabled ? "🧠 Pensando e avaliando dados" : "⚡ Processando consulta"
            record("\(stepPrefix) (Etapa \(hop + 1))...")

            // Para evitar que chamadas JSON de ferramenta vazem no streaming visual da resposta final,
            // encaminhamos deltas de conteúdo apenas se não parecerem um bloco JSON de tool call.
            var hopRawContentBuffer = ""
            var suppressLiveContentStreaming = false

            let llmResult = try await LocalLLMRuntime.shared.generateCompletion(
                backend: backend,
                messages: loopMessages,
                tools: toolsForHop,
                isThinkingEnabled: isThinkingEnabled,
                contextSize: store.llmConfig.contextWindowSize,
                modelIdForEndpoint: store.llmConfig.selectedModelId,
                onStatus: { status in
                    onStepUpdate?(status)
                },
                onThinkingDelta: { delta in
                    liveThinkingAccumulator += delta
                    onThinkingUpdate?(liveThinkingAccumulator)
                },
                onContentDelta: { delta in
                    hopRawContentBuffer += delta
                    let trimmedCheck = hopRawContentBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedCheck.hasPrefix("{") || trimmedCheck.hasPrefix("```") || trimmedCheck.contains("<tool_call>") {
                        suppressLiveContentStreaming = true
                    }
                    if !suppressLiveContentStreaming && !trimmedCheck.isEmpty {
                        onContentUpdate?(hopRawContentBuffer)
                    }
                }
            )

            if !llmResult.thinkingText.isEmpty {
                let header = hop > 0 ? "\n\n**[Etapa \(hop + 1) — Raciocínio após consultar ferramentas]**\n" : ""
                accumulatedThinkingParts.append(header + llmResult.thinkingText)
            }

            // Detecta chamadas de ferramenta (nativas OpenAI OU JSON no texto)
            var calls = llmResult.toolCalls
            if calls.isEmpty {
                calls = Self.parseAllToolCalls(from: llmResult.contentText)
            }

            if !calls.isEmpty && !isLastPossibleHop {
                loopMessages.append(
                    LLMChatCompletionMessage(
                        role: "assistant",
                        content: llmResult.contentText,
                        toolCalls: calls
                    )
                )

                var anyNewCallExecuted = false
                for call in calls {
                    let sig = "\(call.name)::\(call.argumentsJson)"
                    if executedCallSignatures.contains(sig) {
                        loopMessages.append(
                            LLMChatCompletionMessage(
                                role: "tool",
                                content: "{\"status\": \"already_executed\", \"hint\": \"Esta exata chamada já foi feita. Utilize os dados recebidos acima ou chame outra ferramenta ou responda ao usuário.\"}",
                                toolCallId: call.id,
                                toolName: call.name
                            )
                        )
                        continue
                    }

                    executedCallSignatures.insert(sig)
                    anyNewCallExecuted = true
                    usedToolsNames.append(call.name)

                    record("🔧 Consultando banco local via `\(call.name)`...")
                    let resultJson: String
                    do {
                        let outputDict = try await registry.execute(name: call.name, parameters: call.parsedArguments)
                        let result = AIToolResult(toolCallId: call.id, toolName: call.name, result: outputDict)
                        resultJson = compactToolJsonIfNeeded(result.resultJson, compactMode: compactMode)
                        store.chatHistory.append(
                            ChatMessage(
                                role: .tool,
                                content: resultJson,
                                timestamp: Date(),
                                modelUsed: backend.displayBadge,
                                toolName: call.name,
                                toolCallId: call.id
                            )
                        )
                        record("✅ `\(call.name)` concluída com dados reais.")
                    } catch {
                        resultJson = "{\"error\": \"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "\\\""))\"}"
                        record("⚠️ Erro em `\(call.name)`: \(error.localizedDescription)")
                    }

                    loopMessages.append(
                        LLMChatCompletionMessage(
                            role: "tool",
                            content: resultJson,
                            toolCallId: call.id,
                            toolName: call.name
                        )
                    )
                }

                // Se houve apenas chamada repetida, força síntese no próximo hop
                if !anyNewCallExecuted {
                    loopMessages.append(
                        LLMChatCompletionMessage(
                            role: "user",
                            content: "Com base nos dados já consultados acima, responda diretamente ao usuário de forma clara e completa."
                        )
                    )
                }
                continue
            }

            // Sem novas tool calls: esta é a resposta conclusiva!
            finalMarkdown = stripResidualControlTags(from: llmResult.contentText)
            if !finalMarkdown.isEmpty {
                onContentUpdate?(finalMarkdown)
            }
            break
        }

        let finalThinking = accumulatedThinkingParts
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if finalMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalMarkdown = "Concluí a análise dos dados consultados, porém não recebi um texto final do modelo. Tente reformular ou perguntar novamente."
        }

        let followUps = generateSmartFollowUps(
            prompt: userPrompt,
            usedTools: usedToolsNames,
            store: store
        )

        return TurnOutput(
            responseMarkdown: finalMarkdown,
            thinkingContent: finalThinking.isEmpty ? nil : finalThinking,
            executedSteps: collectedSteps,
            followUps: followUps,
            shouldClose: false,
            engineUsed: backend.displayBadge
        )
    }

    private func compactToolJsonIfNeeded(_ json: String, compactMode: Bool) -> String {
        let limit = compactMode ? 1800 : 12000
        if json.count <= limit { return json }
        return String(json.prefix(limit)) + "...\"_truncated_for_context\":true}"
    }

    private func stripResidualControlTags(from raw: String) -> String {
        LocalLLMRuntime.sanitizeAssistantOutput(raw)
    }

    private func isPoliteClosingIntent(_ prompt: String) -> Bool {
        let norm = prompt.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let exactPhrases = [
            "obrigado, pode encerrar", "pode encerrar", "encerrar conversa",
            "obrigado, tchau", "valeu, pode fechar", "tchau", "encerrar chat"
        ]
        return exactPhrases.contains { norm == $0 || norm.hasSuffix($0) }
    }

    private func generateSmartFollowUps(
        prompt: String,
        usedTools: [String],
        store: FinancialDataStore
    ) -> [String] {
        var suggestions: [String] = []
        if usedTools.contains("simulate_amortization") || usedTools.contains("get_loan_projection_and_plan") || usedTools.contains("get_contract_details") {
            suggestions.append("Como esse valor afeta minha sobra líquida e saldo do mês?")
            suggestions.append("Onde posso cortar gastos para acelerar ainda mais a quitação?")
        } else if usedTools.contains("analyze_debt_payoff_strategy") {
            suggestions.append("Quais despesas posso reduzir este mês para quitar mais rápido?")
            suggestions.append("Tenho reserva suficiente em investimentos para negociar à vista?")
        } else if usedTools.contains("get_monthly_cash_flow") || usedTools.contains("aggregate_transactions") {
            suggestions.append("Faça uma projeção dos meus próximos 12 meses")
            suggestions.append("Como estão meus contratos e dívidas em relação a esse saldo?")
        } else {
            if let firstContract = store.contracts.first(where: { !$0.isSettled }) {
                suggestions.append("Analise a projeção e planejamento do contrato \"\(firstContract.name)\"")
            }
            suggestions.append("Qual o resumo do meu saldo e despesas neste mês?")
        }
        suggestions.append("Obrigado, pode encerrar")
        return Array(suggestions.prefix(3))
    }

    // MARK: - Fallback Determinístico (Testes & Execução Headless sem LLM)

    private func runDeterministicFallback(
        userPrompt: String,
        store: FinancialDataStore,
        modelLabel: String,
        initialSteps: [String],
        logStep: (String) -> Void,
        onStepUpdate: ((String) -> Void)?
    ) async -> (responseMarkdown: String, executedSteps: [String], followUps: [String], shouldClose: Bool) {
        var collectedSteps = initialSteps
        func record(_ text: String) {
            collectedSteps.append(text)
            logStep(text)
        }
        ensureSystemPromptWithTools(store: store)
        applySlidingWindow(store: store)
        record("🗜️ Contexto: Janela deslizante aplicada (preservando System Prompt e últimas interações)")

        guard let plannedCalls = planToolCalls(for: userPrompt, store: store, history: store.chatHistory) else {
            record("🤖 Acionando Agentes de Síntese RAG da base local...")
            let agentOutput = AgenticFinancialEngine.runAgentLoop(
                prompt: userPrompt,
                store: store,
                modelLabel: modelLabel,
                onStepUpdate: onStepUpdate
            )
            return (
                agentOutput.responseMarkdown,
                agentOutput.executedSteps,
                agentOutput.suggestedFollowUps,
                agentOutput.shouldCloseChat
            )
        }

        var toolResults: [AIToolResult] = []

        for call in plannedCalls {
            record("🔧 Invocando ferramenta nativa: `\(call.name)`...")
            do {
                let params = call.parsedArguments
                let outputDict = try await registry.execute(name: call.name, parameters: params)
                let result = AIToolResult(toolCallId: call.id, toolName: call.name, result: outputDict)
                toolResults.append(result)

                let toolMsg = ChatMessage(
                    role: .tool,
                    content: result.resultJson,
                    timestamp: Date(),
                    modelUsed: modelLabel,
                    toolName: call.name,
                    toolCallId: call.id
                )
                store.chatHistory.append(toolMsg)
                record("✅ Ferramenta `\(call.name)` concluída com sucesso.")
            } catch {
                let errResult = AIToolResult(toolCallId: call.id, toolName: call.name, result: [:], error: error.localizedDescription)
                toolResults.append(errResult)
                let toolMsg = ChatMessage(
                    role: .tool,
                    content: "{\"error\": \"\(error.localizedDescription)\"}",
                    timestamp: Date(),
                    modelUsed: modelLabel,
                    toolName: call.name,
                    toolCallId: call.id
                )
                store.chatHistory.append(toolMsg)
                record("⚠️ Erro na execução de `\(call.name)`: \(error.localizedDescription)")
            }
        }

        record("✍️ Orquestrador: Sintetizando resposta analítica final orientada aos dados determinísticos...")
        let finalSynthesis = synthesizeAssistantResponse(
            prompt: userPrompt,
            toolResults: toolResults,
            store: store,
            history: store.chatHistory
        )

        return (
            finalSynthesis.markdown,
            collectedSteps,
            finalSynthesis.followUps,
            finalSynthesis.shouldClose
        )
    }

    // MARK: - Planejamento e Roteamento Determinístico de Fallback

    private func planToolCalls(
        for prompt: String,
        store: FinancialDataStore,
        history: [ChatMessage]
    ) -> [AIToolCall]? {
        let norm = prompt.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))

        if let explicitCall = Self.parseToolCall(from: prompt) {
            return [explicitCall]
        }

        if isUnsupportedQuery(norm: norm) {
            let (requested, reason, reqData) = resolveUnsupportedCapabilityDetails(norm: norm)
            let args: [String: Any] = [
                "requestedCapability": requested,
                "reason": reason,
                "requiredData": reqData
            ]
            let argsJson = (try? String(data: JSONSerialization.data(withJSONObject: args), encoding: .utf8)) ?? "{}"
            return [AIToolCall(name: "unsupported_capability", argumentsJson: argsJson)]
        }

        if isMultiTurnBudgetOptimizationFollowUp(norm: norm, history: history) {
            let targetAmount = extractTargetAmount(from: norm) ?? extractTargetAmountFromHistory(history: history) ?? 2000.0
            var calls: [AIToolCall] = []

            let cashFlowJson = "{}"
            calls.append(AIToolCall(name: "get_monthly_cash_flow", argumentsJson: cashFlowJson))

            let discArgs: [String: Any] = ["targetExtraPayment": targetAmount]
            let discJson = (try? String(data: JSONSerialization.data(withJSONObject: discArgs), encoding: .utf8)) ?? "{}"
            calls.append(AIToolCall(name: "analyze_discretionary_spending", argumentsJson: discJson))

            return calls
        }

        // Turno de Financiamento / Empréstimo / Amortização / Quitação (apenas quando há intenção real de simulação/amortização/quitação)
        let hasAmortizationIntent = norm.contains("quitar") || norm.contains("amortizar") || norm.contains("plano de acao") ||
            ((norm.contains("simular") || norm.contains("menor prazo") || norm.contains("prazo")) && (norm.contains("financiamento") || norm.contains("emprestimo")))
        if hasAmortizationIntent {
            let resolvedContract = matchBestContract(in: norm, store: store)
            if let contract = resolvedContract {
                var calls: [AIToolCall] = []
                let detailsArgs: [String: Any] = [
                    "contractId": contract.id.uuidString,
                    "nameOrQuery": contract.name,
                    "kind": contract.kind.rawValue
                ]
                let detailsJson = (try? String(data: JSONSerialization.data(withJSONObject: detailsArgs), encoding: .utf8)) ?? "{}"
                calls.append(AIToolCall(name: "get_contract_details", argumentsJson: detailsJson))

                for val in [500.0, 1000.0, 2000.0] {
                    let simArgs: [String: Any] = [
                        "contractId": contract.id.uuidString,
                        "nameOrQuery": contract.name,
                        "extraPayment": val,
                        "mode": "reduce_term",
                        "recurringMonthly": true
                    ]
                    let simJson = (try? String(data: JSONSerialization.data(withJSONObject: simArgs), encoding: .utf8)) ?? "{}"
                    calls.append(AIToolCall(name: "simulate_amortization", argumentsJson: simJson))
                }
                return calls
            } else {
                // Fallback quando há nome explícito na base de teste ou consulta genérica
                let contractQuery = extractContractName(from: norm) ?? ""
                if !contractQuery.isEmpty {
                    var calls: [AIToolCall] = []
                    let detailsArgs: [String: Any] = ["nameOrQuery": contractQuery, "kind": "any"]
                    let detailsJson = (try? String(data: JSONSerialization.data(withJSONObject: detailsArgs), encoding: .utf8)) ?? "{}"
                    calls.append(AIToolCall(name: "get_contract_details", argumentsJson: detailsJson))

                    for val in [500.0, 1000.0, 2000.0] {
                        let simArgs: [String: Any] = [
                            "nameOrQuery": contractQuery,
                            "extraPayment": val,
                            "mode": "reduce_term",
                            "recurringMonthly": true
                        ]
                        let simJson = (try? String(data: JSONSerialization.data(withJSONObject: simArgs), encoding: .utf8)) ?? "{}"
                        calls.append(AIToolCall(name: "simulate_amortization", argumentsJson: simJson))
                    }
                    return calls
                }
            }
        }

        if norm.contains("projecao") || norm.contains("quando entrarei em debito") || norm.contains("futuro") {
            let projArgs: [String: Any] = ["numberOfMonths": 12]
            let projJson = (try? String(data: JSONSerialization.data(withJSONObject: projArgs), encoding: .utf8)) ?? "{}"
            return [AIToolCall(name: "get_projected_cash_flow_range", argumentsJson: projJson)]
        }

        if norm.contains("ritmo") || norm.contains("final do mes") || norm.contains("terei quanto") || norm.contains("saldo disponivel") {
            return [AIToolCall(name: "get_monthly_cash_flow", argumentsJson: "{}")]
        }

        if norm.contains("teto") || norm.contains("cota") || norm.contains("envelope") || norm.contains("lanches") || norm.contains("gasolina") {
            return [AIToolCall(name: "get_budget_caps_status", argumentsJson: "{}")]
        }

        if (norm.contains("ultimas") && norm.contains("transacoes")) || norm.contains("gastos recentes") {
            let txArgs: [String: Any] = ["limit": 10]
            let txJson = (try? String(data: JSONSerialization.data(withJSONObject: txArgs), encoding: .utf8)) ?? "{}"
            return [AIToolCall(name: "query_transactions", argumentsJson: txJson)]
        }

        if InternetLookupService.isCurrencyQuery(norm) ||
           InternetLookupService.isMacroRateQuery(norm) ||
           norm.contains("recomend") ||
           norm.contains("aplicar") ||
           norm.contains("onde investir") ||
           norm.contains("internet") {
            let topic: String = InternetLookupService.isCurrencyQuery(norm)
                ? "currency"
                : (norm.contains("selic") || norm.contains("cdi") || norm.contains("ipca") ? "economic_rates" : "investment_info")
            let webArgs: [String: Any] = ["query": prompt, "topic": topic]
            let webJson = (try? String(data: JSONSerialization.data(withJSONObject: webArgs), encoding: .utf8)) ?? "{}"
            return [AIToolCall(name: "internet_lookup", argumentsJson: webJson)]
        }

        return nil
    }

    private func matchBestContract(in normPrompt: String, store: FinancialDataStore) -> CreditContract? {
        let active = store.contracts.filter { !$0.isSettled }
        guard !active.isEmpty else { return nil }

        // 1. Correspondência direta pelo nome completo normalizado do contrato
        if let exact = active.first(where: {
            let cNorm = $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            return !cNorm.isEmpty && normPrompt.contains(cNorm)
        }) {
            return exact
        }

        // 2. Pontuação por tokens
        var best: CreditContract?
        var bestScore = 0
        for c in active {
            let cNorm = "\(c.name) \(c.subtypeDisplayName) \(c.contractNumber ?? "")"
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            let tokens = cNorm.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 }
            let score = tokens.filter { normPrompt.contains($0) }.count
            if score > bestScore {
                bestScore = score
                best = c
            }
        }
        if bestScore > 0 { return best }

        // 3. Se só há 1 contrato do tipo citado, retorna ele
        if normPrompt.contains("emprestimo") {
            let loans = active.filter { $0.kind == .loan }
            if loans.count == 1 { return loans.first }
        }
        if normPrompt.contains("financiamento") {
            let fins = active.filter { $0.kind == .financing }
            if fins.count == 1 { return fins.first }
        }
        if active.count == 1 { return active.first }
        return nil
    }

    // MARK: - Detecção de Consultas Não Suportadas (Fallback Loop)

    private func isUnsupportedQuery(norm: String) -> Bool {
        let unsupportedTokens = [
            "compre acoes", "comprar acoes", "bolsa de valores", "petrobras", "vale3", "petr4",
            "fazer emprestimo pelo aplicativo", "contratar emprestimo agora", "pegar emprestimo no itau",
            "comprar bitcoin", "comprar cripto", "vender bitcoin", "home broker", "transferir pix para",
            "enviar ted", "pagar boleto agora pelo banco", "fazer debito automatico no santander"
        ]
        return unsupportedTokens.contains { norm.contains($0) }
    }

    private func resolveUnsupportedCapabilityDetails(norm: String) -> (requested: String, reason: String, requiredData: String) {
        if norm.contains("acoes") || norm.contains("bolsa") || norm.contains("petrobras") || norm.contains("home broker") {
            return (
                requested: "Execução de ordens de compra/venda de ações na B3",
                reason: "O FinSense é uma aplicação de inteligência financeira pessoal e planejamento de fluxo de caixa, não operando como corretora de valores mobiliários (broker) autorizada.",
                requiredData: "Integração via API com corretora credenciada pela CVM/B3 e autorização de custódia."
            )
        } else if norm.contains("emprestimo") && (norm.contains("fazer") || norm.contains("contratar") || norm.contains("pegar")) {
            return (
                requested: "Contratação direta de novo empréstimo bancário",
                reason: "A aplicação gerencia e analisa contratos existentes e simula amortizações, mas não realiza originação de crédito bancário junto a instituições financeiras.",
                requiredData: "API de Open Finance com escopo de contratação de crédito e esteira de aprovação bancária."
            )
        } else if norm.contains("bitcoin") || norm.contains("cripto") {
            return (
                requested: "Negociação de criptoativos em exchange",
                reason: "O FinSense não possui conexão de custódia e execução com exchanges de criptomoedas.",
                requiredData: "Integração via chave de API com exchanges (ex: Binance, Mercado Bitcoin) com permissão de trade."
            )
        } else {
            return (
                requested: "Transação bancária externa direta (PIX / TED / Pagamento)",
                reason: "O FinSense não realiza movimentação bancária ativa externa por motivos de segurança e privacidade dos seus dados locais.",
                requiredData: "Iniciação de pagamentos via Open Finance Brasil (ITP)."
            )
        }
    }

    private func isMultiTurnBudgetOptimizationFollowUp(norm: String, history: [ChatMessage]) -> Bool {
        let triggers = ["como consigo", "onde cortar", "como arranjar", "no plano", "plano 3", "2 mil", "como pagar esse valor", "como economizar"]
        let hasTrigger = triggers.contains { norm.contains($0) }
        guard hasTrigger else { return false }

        let recentHistoryText = history.suffix(6).map(\.content).joined(separator: " ").lowercased()
        return recentHistoryText.contains("plano de ação") ||
               recentHistoryText.contains("cenário") ||
               recentHistoryText.contains("amortização") ||
               recentHistoryText.contains("financiamento")
    }

    private func extractTargetAmount(from text: String) -> Double? {
        let norm = text.lowercased()
        if norm.contains("2 mil") || norm.contains("2.000") || norm.contains("2000") { return 2000.0 }
        if norm.contains("1 mil") || norm.contains("1.000") || norm.contains("1000") { return 1000.0 }
        if norm.contains("500") { return 500.0 }
        if norm.contains("3 mil") || norm.contains("3.000") || norm.contains("3000") { return 3000.0 }
        return nil
    }

    private func extractTargetAmountFromHistory(history: [ChatMessage]) -> Double? {
        for msg in history.reversed() {
            if let amount = extractTargetAmount(from: msg.content) {
                return amount
            }
        }
        return nil
    }

    private func extractContractName(from text: String) -> String? {
        let norm = text.lowercased()
        if norm.contains("caixa") { return "caixa" }
        if norm.contains("santander") { return "santander" }
        if norm.contains("itau") { return "itau" }
        if norm.contains("bradesco") { return "bradesco" }
        if norm.contains("imovel") || norm.contains("habitacao") { return "habitacao" }
        return nil
    }

    // MARK: - Síntese Final Determinística

    private func synthesizeAssistantResponse(
        prompt: String,
        toolResults: [AIToolResult],
        store: FinancialDataStore,
        history: [ChatMessage]
    ) -> (markdown: String, followUps: [String], shouldClose: Bool) {
        if let fallbackResult = toolResults.first(where: { $0.toolName == "unsupported_capability" }) {
            let req = (fallbackResult.result["requestedCapability"] as? String) ?? "Ação solicitada"
            let reason = (fallbackResult.result["reason"] as? String) ?? "Capacidade não suportada no momento."
            let reqData = (fallbackResult.result["requiredData"] as? String) ?? "Ferramenta não disponível."

            let md = """
            ### ⚠️ Funcionalidade Não Suportada Nativamente

            Você solicitou: **\(req)**.

            **Motivo da Restrição:**
            \(reason)

            **O que seria necessário para atender:**
            • \(reqData)

            > **Feedback Registrado:** Esse evento foi computado internamente no registro de capacidades para direcionar o desenvolvimento das próximas ferramentas determinísticas da aplicação.

            Posso te ajudar a simular o impacto financeiro dessa operação no seu fluxo de caixa ou planejar uma reserva equivalente?
            """
            return (
                md,
                [
                    "Qual é a minha sobra líquida real neste mês?",
                    "Como está meu fluxo de caixa projetado?",
                    "Obrigado, pode encerrar"
                ],
                false
            )
        }

        if let contractTool = toolResults.first(where: { $0.toolName == "get_contract_details" }),
           toolResults.contains(where: { $0.toolName == "simulate_amortization" }) {
            let contractsList = (contractTool.result["contracts"] as? [[String: Any]]) ?? []
            let cName = (contractsList.first?["name"] as? String) ?? "Contrato de Crédito"
            let cBalance = (contractsList.first?["outstandingBalance"] as? Double) ?? 0.0
            let cRemaining = (contractsList.first?["remainingInstallments"] as? Int) ?? 0
            let cInstallment = (contractsList.first?["installmentAmount"] as? Double) ?? 0.0
            let cKind = (contractsList.first?["kind"] as? String) ?? "financing"

            let allSims = toolResults.filter { $0.toolName == "simulate_amortization" }
            let sim500 = allSims.first(where: { (($0.result["grossPayment"] as? Double) ?? 0) == 500.0 })?.result
            let sim1000 = allSims.first(where: { (($0.result["grossPayment"] as? Double) ?? 0) == 1000.0 })?.result
            let sim2000 = allSims.first(where: { (($0.result["grossPayment"] as? Double) ?? 0) == 2000.0 })?.result

            func descSim(_ s: [String: Any]?, val: Double) -> String {
                guard let s else { return "• Amortização de \(BRLFormatters.currency(val)): Simulação processada." }
                var elim = (s["eliminatedInstallmentsCount"] as? Int) ?? 0
                var saved = (s["estimatedTotalInterestSaved"] as? Double) ?? 0.0
                var newRem = (s["newRemainingInstallments"] as? Int) ?? 0
                var savedTime = (s["savedTimeString"] as? String) ?? "\(elim) meses"

                if let rec = s["recurringMonthlyProjection"] as? [String: Any],
                   let monthsSaved = rec["monthsSavedWithPlan"] as? Int,
                   monthsSaved > 0 || elim == 0 {
                    elim = monthsSaved
                    newRem = (rec["projectedMonthsWithPlan"] as? Int) ?? newRem
                    saved = (rec["totalInterestSaved"] as? Double) ?? saved
                    savedTime = (rec["savedTimeWithPlan"] as? String) ?? "\(elim) meses"
                }

                return "• **Cenário (+ \(BRLFormatters.currency(val))/mês):** Elimina **\(elim) parcelas** (\(savedTime) poupados), reduzindo o prazo restante para **\(newRem) meses** e economizando **\(BRLFormatters.currency(saved))** em juros futuros."
            }

            let kpiSummary = store.buildUnifiedFinancialKPISummary(referenceDate: store.selectedMonth, isAnnual: false)
            let saldoPrevistoAtual = kpiSummary.isPast ? kpiSummary.projectedAccountBalance : kpiSummary.balanceIfAllBudgetsConsumed

            let systemLabel = cKind == "loan" ? "Empréstimo" : "Tabela Price"
            let md = """
            ### Plano de Ação para Quitação no Menor Prazo: \(cName)

            Analisando os dados reais do seu contrato com **Saldo Devedor Atual de \(BRLFormatters.currency(cBalance))** (\(cRemaining) parcelas restantes de \(BRLFormatters.currency(cInstallment))):

            #### 🎯 Simulação de Prazo e Economia de Juros (\(systemLabel)):
            \(descSim(sim500, val: 500.0))
            \(descSim(sim1000, val: 1000.0))
            \(descSim(sim2000, val: 2000.0))

            #### 📊 Viabilidade no Seu Caixa (Saldo Previsto):
            • **Saldo Previsto ao Fim do Mês:** \(BRLFormatters.currency(saldoPrevistoAtual)) • **Sobra Após Planejamento:** \(BRLFormatters.currency(kpiSummary.surplusAfterPlanning))

            #### ⚡ Efeito Bola de Neve:
            Ao amortizar com redução de prazo, 100% do aporte extra abate o saldo devedor puro, desintegrando os juros compostos que seriam cobrados pelos próximos meses e anos.

            No cenário de maior aceleração (+R$ 2.000,00/mês), você reduz drasticamente o prazo e os encargos bancários.
            """

            return (
                md,
                [
                    "No plano onde amortizo 2 mil por mês, como consigo esse valor?",
                    "Qual a minha sobra líquida no mês atual?",
                    "Obrigado, pode encerrar"
                ],
                false
            )
        }

        if let discTool = toolResults.first(where: { $0.toolName == "analyze_discretionary_spending" }) {
            let discRes = discTool.result
            let targetAnalysis = (discRes["targetPaymentAnalysis"] as? [String: Any]) ?? [:]
            let targetAmount = (targetAnalysis["targetAmount"] as? Double) ?? 2000.0
            let curSurplus = (targetAnalysis["currentOperationalSurplus"] as? Double) ?? 0.0
            let neededCut = (targetAnalysis["neededFromBudgetOptimization"] as? Double) ?? targetAmount

            let discExpense = (discRes["discretionaryExpensesTotal"] as? Double) ?? 0.0
            let discShare = (discRes["discretionarySharePercent"] as? Double) ?? 0.0

            let topCats = (discRes["topDiscretionaryCategories"] as? [[String: Any]]) ?? []
            let catLines = topCats.prefix(4).map { c -> String in
                let name = (c["category"] as? String) ?? "Consumo"
                let amt = (c["amount"] as? Double) ?? 0.0
                let cut25 = (c["cutScenario25Percent"] as? Double) ?? 0.0
                return "• **\(name)**: Gasto atual de **\(BRLFormatters.currency(amt))** → Corte de 25% libera **+\(BRLFormatters.currency(cut25))**"
            }.joined(separator: "\n")

            let aggCuts = (discRes["aggregateCutScenarios"] as? [String: Any]) ?? [:]
            let cut25Total = (aggCuts["cut25Percent"] as? Double) ?? 0.0

            let md = """
            ### Como Liberar \(BRLFormatters.currency(targetAmount)) por Mês para Amortização:

            Cruzei a meta de **\(BRLFormatters.currency(targetAmount))/mês** com o seu fluxo de caixa e histórico de consumo:

            1. **Sobra Operacional Atual:**
               • Você possui atualmente uma sobra operacional de **\(BRLFormatters.currency(curSurplus))** entre receitas e despesas.
               • Para atingir os **\(BRLFormatters.currency(targetAmount))**, você precisa remanejar **\(BRLFormatters.currency(neededCut))** de despesas variáveis.

            2. **Oportunidades em Gastos Discricionários (Consumo Flexível):**
               • Seus gastos discricionários somam **\(BRLFormatters.currency(discExpense))** (\(String(format: "%.1f%%", discShare)) do total de despesas).
               \(catLines.isEmpty ? "• Redução programada de compras não essenciais." : catLines)

            3. **Plano de Corte Recomendado:**
               • Aplicando um ajuste moderado de 25% nas categorias acima, você libera **\(BRLFormatters.currency(cut25Total))** imediatamente.
               • Somando esse ajuste à sua sobra de caixa (\(BRLFormatters.currency(curSurplus))), você atinge com folga a meta de **\(BRLFormatters.currency(targetAmount))** mensais para quitar o contrato anos antes do previsto!
            """

            return (
                md,
                [
                    "Reserve R$ 500 para gasolina este mês",
                    "Qual a projeção do meu saldo acumulado até o final do ano?",
                    "Obrigado, pode encerrar"
                ],
                false
            )
        }

        if let projTool = toolResults.first(where: { $0.toolName == "get_projected_cash_flow_range" }) {
            let res = projTool.result
            let hasRisk = (res["hasRunwayRisk"] as? Bool) ?? false
            let firstDeficit = res["firstDeficitMonth"] as? String
            let lowestBal = (res["lowestProjectedBalance"] as? Double) ?? 0.0
            let count = (res["monthsProjectedCount"] as? Int) ?? 12

            var md = "### Projeção de Fluxo de Caixa para os Próximos \(count) Meses\n\n"
            if hasRisk, let month = firstDeficit {
                md += "⚠️ **Alerta de Risco Financeiro:** Seu saldo acumulado entra em terreno negativo em **\(month)** (menor saldo previsto: **\(BRLFormatters.currency(lowestBal))**).\n\n"
            } else {
                md += "✅ **Fluxo de Caixa Saudável:** Não foi detectado risco de quebra de caixa no horizonte analisado. Seu menor saldo projetado será de **\(BRLFormatters.currency(lowestBal))**.\n\n"
            }

            if let timeline = res["timeline"] as? [[String: Any]] {
                let sampleLines = timeline.prefix(6).map { m in
                    let mName = (m["month"] as? String) ?? ""
                    let inc = (m["projectedIncome"] as? Double) ?? 0.0
                    let exp = (m["projectedExpense"] as? Double) ?? 0.0
                    let end = (m["accumulatedBalanceEnd"] as? Double) ?? 0.0
                    return "• **\(mName)**: Entradas: \(BRLFormatters.currency(inc)) | Saídas: \(BRLFormatters.currency(exp)) | Saldo Final: `\(BRLFormatters.currency(end))`"
                }.joined(separator: "\n")
                md += "#### Panorama dos Próximos Meses:\n" + sampleLines
            }

            return (
                md,
                [
                    "Como estão meus tetos e provisões deste mês?",
                    "Monte um plano de ação para quitar meu financiamento",
                    "Obrigado, pode encerrar"
                ],
                false
            )
        }

        if let cashTool = toolResults.first(where: { $0.toolName == "get_monthly_cash_flow" }) {
            let res = cashTool.result
            let mRef = (res["monthReference"] as? String) ?? ""
            let opNet = (res["operationalBalance"] as? Double) ?? 0.0
            let checking = (res["liquidCheckingBalanceNow"] as? Double) ?? 0.0
            let saldoPrevisto = (res["saldoPrevistoFimDoMes"] as? Double) ?? checking
            let saldoSemOrc = (res["saldoPrevistoSemConsumirOrcamentos"] as? Double) ?? saldoPrevisto
            let sobraPlan = (res["sobraAposPlanejamento"] as? Double) ?? opNet
            let inc = ((res["income"] as? [String: Any])?["total"] as? Double) ?? 0.0
            let exp = ((res["expense"] as? [String: Any])?["total"] as? Double) ?? 0.0
            let rate = (res["savingsRatePercent"] as? Double) ?? 0.0

            let md = """
            ### Balanço e Fluxo de Caixa — \(mRef)

            • **Receitas Totais:** \(BRLFormatters.currency(inc))
            • **Despesas Lançadas:** \(BRLFormatters.currency(exp))
            • **Sobra Líquida Operacional:** **\(BRLFormatters.currency(opNet))** (\(String(format: "%.1f%%", rate)) de taxa de poupança)
            • **Sobra Após Planejamento (com Tetos/Cotas):** **\(BRLFormatters.currency(sobraPlan))**
            • **Saldo Disponível em Contas Hoje:** **\(BRLFormatters.currency(checking))**
            • **Saldo Previsto no Fim do Mês:** **\(BRLFormatters.currency(saldoPrevisto))** *(se não usar os orçamentos restantes: \(BRLFormatters.currency(saldoSemOrc)))*

            \(opNet >= 0 ? "Você está operando com superávit. Esse valor pode ser direcionado para reserva de emergência ou amortização de passivos." : "Atenção: Você está operando com déficit no mês. Recomendo analisar cortes de despesas discricionárias.")
            """

            return (
                md,
                [
                    "Onde posso cortar gastos neste mês?",
                    "Qual a projeção para os próximos meses?",
                    "Obrigado, pode encerrar"
                ],
                false
            )
        }

        if let webTool = toolResults.first(where: { $0.toolName == "internet_lookup" }) {
            let res = webTool.result
            let status = (res["status"] as? String) ?? ""
            if status == "disabled" {
                let msg = (res["message"] as? String) ?? "Consultas na internet estão desativadas nas Configurações da IA."
                return (
                    "### 🌐 Acesso à Internet Desativado\n\n\(msg)",
                    ["Qual é o meu patrimônio consolidado hoje?", "Como está meu saldo previsto?", "Obrigado, pode encerrar"],
                    false
                )
            }
            if status == "unreachable_or_no_results" {
                let msg = (res["message"] as? String) ?? "Não foi possível consultar fontes públicas externas no momento."
                return (
                    "### 🌐 Consulta Pública Externa\n\n\(msg)",
                    ["Qual é o meu saldo disponível nas contas?", "Obrigado, pode encerrar"],
                    false
                )
            }

            var lines: [String] = ["### 🌐 Consulta Pública na Internet (Somente Leitura — Sem Envio de Dados)\n"]
            if let fxList = res["exchangeRates"] as? [[String: Any]], !fxList.isEmpty {
                lines.append("#### 💱 Cotações Atuais:")
                for item in fxList {
                    let name = (item["name"] as? String) ?? (item["pair"] as? String) ?? "Moeda"
                    let bid = (item["bidFormatted"] as? String) ?? "-"
                    let src = (item["source"] as? String) ?? "Fonte Pública"
                    let dt = (item["updatedAt"] as? String) ?? ""
                    lines.append("• **\(name):** **\(bid)** _(Fonte: \(src)\(dt.isEmpty ? "" : " • \(dt)"))_")
                }
                lines.append("")
            }

            if let conv = res["localPatrimonyConversionOnlyLocalMath"] as? [String: Any] {
                let code = (conv["currencyCode"] as? String) ?? "USD"
                let patBRL = (conv["patrimonyBRL"] as? String) ?? "R$ 0,00"
                let chkBRL = (conv["checkingBRL"] as? String) ?? "R$ 0,00"
                let invBRL = (conv["consolidatedInvestmentsBRL"] as? String) ?? "R$ 0,00"
                let patConv = (conv["patrimonyConverted"] as? String) ?? "-"
                lines.append("#### 💼 Conversão do Seu Patrimônio (Cálculo 100% Local):")
                lines.append("• **Patrimônio Consolidado Local:** **\(patBRL)** _(Contas: \(chkBRL) + Investimentos: \(invBRL))_")
                lines.append("• **Equivalente em \(code) Hoje:** **\(patConv)**")
                lines.append("")
            }

            if let macro = res["brazilianMacroIndicators"] as? [String: Any] {
                lines.append("#### 🏛️ Taxas e Índices Oficiais (Banco Central):")
                if let selic = macro["selicMetaAnualPercent"] as? Double {
                    lines.append("• **Taxa Selic Meta:** **\(String(format: "%.2f", selic))% ao ano**")
                }
                if let cdi = macro["cdiAnualizadoPercent"] as? Double {
                    lines.append("• **CDI Anualizado:** **\(String(format: "%.2f", cdi))% ao ano**")
                }
                if let ipca = macro["ipcaAcumulado12MesesPercent"] as? Double {
                    lines.append("• **IPCA Acumulado (12 meses):** **\(String(format: "%.2f", ipca))%**")
                }
                lines.append("")
            }

            if let refs = res["publicWebReferences"] as? [[String: Any]], !refs.isEmpty {
                lines.append("#### 📚 Referências Públicas:")
                for ref in refs.prefix(3) {
                    let title = (ref["title"] as? String) ?? "Referência"
                    let summary = (ref["summary"] as? String) ?? ""
                    let src = (ref["source"] as? String) ?? ""
                    lines.append("• **\(title)** _(\(src))_: \(summary)")
                }
                lines.append("")
            }

            lines.append("> 🔒 _Privacidade garantida: apenas o termo público foi consultado em modo leitura; seus saldos e transações permaneceram exclusivamente neste Mac._")
            return (
                lines.joined(separator: "\n"),
                ["Qual a taxa Selic e o CDI hoje?", "Como está minha sobra líquida este mês?", "Obrigado, pode encerrar"],
                false
            )
        }

        return (
            "Consulta financeira processada com base nos dados determinísticos locais do seu FinSense.",
            ["Qual o saldo disponível nas minhas contas?", "Como estão meus contratos?", "Obrigado, pode encerrar"],
            false
        )
    }

    // MARK: - Gestão de Janela Deslizante (Sliding Window Context Optimization)

    public func applySlidingWindow(store: FinancialDataStore) {
        guard store.chatHistory.count > maxSlidingWindowMessages else { return }

        let systemMessage = store.chatHistory.first(where: { $0.role == .system })
        let nonSystemMessages = store.chatHistory.filter { $0.role != .system }

        var kept = Array(nonSystemMessages.suffix(maxSlidingWindowMessages))

        let limit = max(0, kept.count - 2)
        for i in 0..<limit {
            if kept[i].role == .tool && kept[i].content.count > 300 {
                kept[i].content = "{\"status\": \"summarized_historical_context\", \"summary\": \"Dados determinísticos consultados e incorporados na resposta do assistente.\"}"
            }
        }

        var newHistory: [ChatMessage] = []
        if let systemMessage {
            newHistory.append(systemMessage)
        }
        newHistory.append(contentsOf: kept)
        store.chatHistory = newHistory
    }

    private func ensureSystemPrompt(_ content: String, store: FinancialDataStore) {
        if store.chatHistory.isEmpty {
            store.chatHistory.append(ChatMessage(role: .system, content: content))
        } else if store.chatHistory.first?.role != .system {
            store.chatHistory.insert(ChatMessage(role: .system, content: content), at: 0)
        } else {
            store.chatHistory[0] = ChatMessage(role: .system, content: content)
        }
    }

    private func ensureSystemPromptWithTools(store: FinancialDataStore) {
        let toolsDoc = registry.generateToolsDocumentation()
        let fullSystemPrompt = """
        \(LocalLLMService.systemPrompt)

        ================================================================================
        \(toolsDoc)
        ================================================================================
        """
        ensureSystemPrompt(fullSystemPrompt, store: store)
    }

    // MARK: - Parsing Resiliente de Chamadas de Ferramenta

    public static func parseToolCall(from rawText: String) -> AIToolCall? {
        parseAllToolCalls(from: rawText).first
    }

    public static func parseAllToolCalls(from rawText: String) -> [AIToolCall] {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        var found: [AIToolCall] = []

        // 1. Tags <tool_call> ... </tool_call> (padrão Qwen / Hermes / DeepSeek)
        var searchStart = trimmed.startIndex
        while let openTag = trimmed.range(of: "<tool_call>", range: searchStart..<trimmed.endIndex),
              let closeTag = trimmed.range(of: "</tool_call>", range: openTag.upperBound..<trimmed.endIndex) {
            let inner = String(trimmed[openTag.upperBound..<closeTag.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let call = parseJsonToolCall(inner) {
                found.append(call)
            }
            searchStart = closeTag.upperBound
        }
        if !found.isEmpty { return found }

        // 2. Bloco ```json ... ```
        var blockStart = trimmed.startIndex
        while let jsonRange = trimmed.range(of: "```json", range: blockStart..<trimmed.endIndex),
              let endRange = trimmed.range(of: "```", range: jsonRange.upperBound..<trimmed.endIndex) {
            let jsonString = String(trimmed[jsonRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let call = parseJsonToolCall(jsonString) {
                found.append(call)
            }
            blockStart = endRange.upperBound
        }
        if !found.isEmpty { return found }

        // 3. Bloco genérico ``` ... ```
        if let codeRange = trimmed.range(of: "```"),
           let endRange = trimmed[codeRange.upperBound...].range(of: "```") {
            let codeString = String(trimmed[codeRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let call = parseJsonToolCall(codeString) {
                return [call]
            }
        }

        // 4. Objeto JSON direto no texto { "tool": "..." } ou { "name": "..." }
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace <= lastBrace {
            let jsonSubstring = String(trimmed[firstBrace...lastBrace])
            if let call = parseJsonToolCall(jsonSubstring) {
                return [call]
            }
        }

        return []
    }

    private static func parseJsonToolCall(_ jsonString: String) -> AIToolCall? {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let name = (dict["tool"] as? String) ?? (dict["name"] as? String)
        guard let toolName = name, !toolName.isEmpty else { return nil }

        let paramsDict = (dict["parameters"] as? [String: Any]) ??
                         (dict["arguments"] as? [String: Any]) ??
                         (dict["params"] as? [String: Any]) ?? [:]

        let argsJson = (try? String(data: JSONSerialization.data(withJSONObject: paramsDict), encoding: .utf8)) ?? "{}"
        let callId = (dict["id"] as? String) ?? UUID().uuidString

        return AIToolCall(id: callId, name: toolName, argumentsJson: argsJson)
    }
}
