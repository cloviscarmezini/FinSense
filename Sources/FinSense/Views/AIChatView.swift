import SwiftUI

public struct AIChatSheetView: View {
    @ObservedObject public var store: FinancialDataStore
    @ObservedObject public var llmService: LocalLLMService
    @Environment(\.dismiss) private var dismiss

    @State private var inputPrompt: String = ""
    @State private var showClearHistoryConfirmation: Bool = false
    @State private var expandedAgentSteps: Set<UUID> = []
    @State private var expandedThinkingIds: Set<UUID> = []
    @State private var isLiveThinkingExpanded: Bool = true
    @State private var pulseAnimation: Bool = false

    private let suggestedPrompts: [String] = [
        "Qual é o panorama completo das minhas contas, investimentos, dívidas e contratos?",
        "Se eu continuar gastando no ritmo deste mês, ao final do mês terei quanto?",
        "Analise meu plano de amortização atual e me diga quanto estou economizando de juros",
        "Onde posso cortar gastos variáveis para sobrar mais dinheiro todo mês?",
        "Analise meus próximos 12 meses e diga se há risco de caixa negativo",
        "Quais são minhas maiores categorias de despesa nos últimos meses?"
    ]

    public init(store: FinancialDataStore, llmService: LocalLLMService) {
        self.store = store
        self.llmService = llmService
    }

    private var activeBackend: LocalLLMBackendKind {
        LocalLLMRuntime.shared.resolveActiveBackend(for: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top bar
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#6366F1"), Color(hex: "#8B5CF6")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 38)
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Super Agente Financeiro Local")
                            .font(.title3.bold())
                        Text("Acesso irrestrito ao banco local • 100% das regras do FinSense • Conversação contínua")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Toggle explícito da opção "Pensando"
                Button {
                    store.llmConfig.isThinkingModeEnabled.toggle()
                    store.save()
                    LocalLLMRuntime.shared.invalidateAppleSession()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: store.llmConfig.isThinkingModeEnabled ? "brain.filled.head.profile" : "bolt.fill")
                            .font(.caption)
                        Text(store.llmConfig.isThinkingModeEnabled ? "Pensando: ON" : "Modo Rápido")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(
                            store.llmConfig.isThinkingModeEnabled
                                ? Color(hex: "#6366F1").opacity(0.18)
                                : Color.secondary.opacity(0.14)
                        )
                    )
                    .overlay(
                        Capsule().stroke(
                            store.llmConfig.isThinkingModeEnabled
                                ? Color(hex: "#6366F1").opacity(0.55)
                                : Color.clear,
                            lineWidth: 1
                        )
                    )
                    .foregroundStyle(store.llmConfig.isThinkingModeEnabled ? Color(hex: "#6366F1") : .secondary)
                }
                .buttonStyle(.plain)
                .help(
                    store.llmConfig.isThinkingModeEnabled
                        ? "Modo Pensando ativado: extrai 100% do raciocínio da IA, realiza múltiplas consultas ao banco e valida cada cálculo antes de responder (pode levar mais segundos)."
                        : "Modo Rápido: respostas mais curtas e diretas com menor latência."
                )

                // Badge do motor neural ativo
                HStack(spacing: 5) {
                    Image(systemName: "cpu.fill")
                        .font(.caption2)
                    Text(activeBackend.displayBadge)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.green.opacity(0.15)))
                .foregroundStyle(.green)

                Button("Limpar") {
                    showClearHistoryConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Fechar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            // Aviso apenas se Apple Intelligence não estiver disponível nos Ajustes do macOS
            if !LocalLLMRuntime.isAppleIntelligenceAvailable {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Apple Intelligence indisponível nos Ajustes do Sistema (\(LocalLLMRuntime.appleIntelligenceStatusDescription())). Ative a Apple Intelligence no macOS para conversação neural completa.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Ajustes IA") {
                        dismiss()
                        store.navigateToLLMInstallSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
            }

            Divider()

            // Quick Prompt Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestedPrompts, id: \.self) { suggestion in
                        Button {
                            inputPrompt = suggestion
                            sendQuestion()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                Text(suggestion)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#6366F1").opacity(0.12)))
                            .foregroundStyle(Color(hex: "#6366F1"))
                        }
                        .buttonStyle(.plain)
                        .disabled(llmService.isProcessingChat)
                    }
                }
            }

            // Messages ScrollView
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(store.chatHistory) { msg in
                            if msg.role != .system && msg.role != .tool {
                                chatBubble(msg)
                                    .id(msg.id)
                            }
                        }

                        // Card ao vivo de "Pensando..." deixando claro que a IA está trabalhando ativamente
                        if llmService.isProcessingChat && !llmService.isTypingResponse {
                            liveThinkingWorkingCard
                                .id("liveThinkingCard")
                        }

                        if llmService.isTypingResponse {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "cpu.fill")
                                            .font(.caption)
                                            .foregroundStyle(Color(hex: "#6366F1"))
                                        Text(llmService.activeEngineDescription.isEmpty ? "Super Agente Local" : llmService.activeEngineDescription)
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                        Text(String(format: "• %.1fs", llmService.thinkingElapsedSeconds))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Parar") {
                                            llmService.cancelChatGeneration()
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }

                                    if !llmService.liveThinkingText.isEmpty {
                                        DisclosureGroup("Pensamento concluído (\(llmService.liveThinkingText.count) caracteres)", isExpanded: $isLiveThinkingExpanded) {
                                            Text(llmService.liveThinkingText)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.top, 4)
                                        }
                                        .font(.caption2.bold())
                                        .foregroundStyle(Color(hex: "#8B5CF6"))
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#8B5CF6").opacity(0.08)))
                                    }

                                    Text(LocalizedStringKey(llmService.liveTypingResponseText + " ▌"))
                                        .font(.system(size: 13.5))
                                        .textSelection(.enabled)
                                        .padding(14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.primary.opacity(0.05))
                                        )
                                }
                                Spacer(minLength: 40)
                            }
                            .id("liveTypingBubble")
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("chatBottomAnchor")
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: store.chatHistory.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: llmService.isProcessingChat) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: llmService.liveThinkingText) { _, _ in
                    proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
                }
                .onChange(of: llmService.liveTypingResponseText) { _, _ in
                    proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))

            // Input Bar
            HStack(spacing: 10) {
                BorderedTextField(
                    placeholder: "Converse abertamente: pergunte sobre contratos, planejamento, projeções, gastos ou dívidas...",
                    text: $inputPrompt,
                    onCommit: {
                        sendQuestion()
                    }
                )

                if llmService.isProcessingChat {
                    Button(role: .destructive) {
                        llmService.cancelChatGeneration()
                    } label: {
                        Label("Parar", systemImage: "stop.circle.fill")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        sendQuestion()
                    } label: {
                        Label("Enviar", systemImage: "paperplane.fill")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#6366F1"))
                    .disabled(inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(22)
        .frame(width: 920, height: 700)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
            llmService.activateBuiltInAppleIntelligenceIfNeeded(in: store)
            llmService.prewarmAppleIntelligence(store: store)
        }
        .onChange(of: llmService.shouldCloseChatSheet) { _, shouldClose in
            if shouldClose {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                }
            }
        }
        .alert("Confirmar Limpeza do Histórico", isPresented: $showClearHistoryConfirmation) {
            Button("Limpar Histórico", role: .destructive) {
                LocalLLMRuntime.shared.invalidateAppleSession()
                store.chatHistory = [
                    ChatMessage(
                        role: .assistant,
                        content: "Histórico limpo. Estou com acesso completo ao seu banco de dados financeiro via Apple Intelligence — pode perguntar qualquer coisa sobre suas contas, contratos, amortizações ou projeções!"
                    )
                ]
                store.save()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Deseja realmente remover todas as mensagens do histórico de conversas com a IA local?")
        }
    }

    @ViewBuilder
    private var liveThinkingWorkingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#6366F1").opacity(pulseAnimation ? 0.25 : 0.10))
                        .frame(width: 28, height: 28)
                    Image(systemName: store.llmConfig.isThinkingModeEnabled ? "brain.head.profile" : "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "#6366F1"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(store.llmConfig.isThinkingModeEnabled ? "Pensando profundamente..." : "Processando...")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color(hex: "#6366F1"))

                        Text(String(format: "%.1fs", llmService.thinkingElapsedSeconds))
                            .font(.caption.monospacedDigit().bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: "#6366F1").opacity(0.14)))
                            .foregroundStyle(Color(hex: "#6366F1"))
                    }

                    Text(
                        llmService.currentAgentStepMessage.isEmpty
                            ? "Consultando base de dados financeira local..."
                            : llmService.currentAgentStepMessage
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }

                Spacer()

                ProgressView()
                    .controlSize(.small)

                Button("Parar") {
                    llmService.cancelChatGeneration()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if !llmService.liveThinkingText.isEmpty {
                DisclosureGroup(
                    isExpanded: $isLiveThinkingExpanded
                ) {
                    ScrollView {
                        Text(llmService.liveThinkingText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 140)
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.caption2)
                        Text("Raciocínio em tempo real")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(Color(hex: "#8B5CF6"))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "#6366F1").opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(hex: "#6366F1").opacity(0.25), lineWidth: 1)
        )
    }

    private func sendQuestion() {
        let q = inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !llmService.isProcessingChat else { return }
        inputPrompt = ""
        Task {
            await llmService.sendUserQuestion(q, store: store)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func chatBubble(_ msg: ChatMessage) -> some View {
        HStack(alignment: .top) {
            if msg.role == .user {
                let displayContent: String = {
                    if msg.content.hasPrefix("[NOVA SIMULAÇÃO DO SISTEMA]") {
                        return msg.content
                            .replacingOccurrences(of: "[NOVA SIMULAÇÃO DO SISTEMA] ", with: "")
                            .replacingOccurrences(of: "[NOVA SIMULAÇÃO DO SISTEMA]", with: "")
                    }
                    return msg.content
                }()
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(displayContent)
                        .font(.body)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: "#6366F1"))
                        )
                        .foregroundStyle(.white)
                    Text(BRLFormatters.shortDate(msg.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu.fill")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#6366F1"))
                        Text(msg.modelUsed ?? "Super Agente Financeiro Local")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        if let duration = msg.thinkingDurationSeconds, duration > 0 {
                            Text(String(format: "• %.1fs", duration))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Seção colapsável do pensamento interno (Thinking Mode)
                    if let thinking = msg.thinkingContent, !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedThinkingIds.contains(msg.id) },
                                set: { isExp in
                                    if isExp {
                                        expandedThinkingIds.insert(msg.id)
                                    } else {
                                        expandedThinkingIds.remove(msg.id)
                                    }
                                }
                            )
                        ) {
                            Text(thinking)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(.top, 4)
                                .padding(.horizontal, 4)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "brain.head.profile")
                                    .font(.caption2)
                                let durStr = msg.thinkingDurationSeconds.map { String(format: " (%.1fs)", $0) } ?? ""
                                Text("Pensamento da IA\(durStr)")
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(Color(hex: "#8B5CF6"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "#8B5CF6").opacity(0.07))
                        )
                    }

                    if let steps = msg.agentSteps, !steps.isEmpty {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedAgentSteps.contains(msg.id) },
                                set: { isExp in
                                    if isExp {
                                        expandedAgentSteps.insert(msg.id)
                                    } else {
                                        expandedAgentSteps.remove(msg.id)
                                    }
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(steps, id: \.self) { step in
                                    Text(step)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 4)
                            .padding(.horizontal, 4)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "gearshape.arrow.triangle.2.circlepath")
                                    .font(.caption2)
                                Text("Etapas e Consultas ao Banco (\(steps.count))")
                                    .font(.caption2.bold())
                            }
                            .foregroundStyle(Color(hex: "#6366F1"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }

                    Text(LocalizedStringKey(msg.content))
                        .font(.system(size: 13.5))
                        .textSelection(.enabled)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )

                    if let followUps = msg.suggestedFollowUps, !followUps.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sugestões de continuação:")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(followUps, id: \.self) { suggestion in
                                        Button {
                                            inputPrompt = suggestion
                                            sendQuestion()
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.turn.down.right")
                                                    .font(.caption2)
                                                Text(suggestion)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color(hex: "#6366F1").opacity(0.12))
                                            )
                                            .foregroundStyle(Color(hex: "#6366F1"))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(llmService.isProcessingChat)
                                    }
                                }
                            }
                        }
                        .padding(.top, 2)
                    }

                    if msg.shouldCloseChat == true {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Conversa concluída. A janela pode ser fechada.")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 40)
            }
        }
    }
}
