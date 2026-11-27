import SwiftUI
import AppKit

// MARK: - FinSense 2.0 Bento Design System & Tokens

public enum FinSenseTheme {
    public static let cardCornerRadius: CGFloat = 15
    public static let compactCornerRadius: CGFloat = 11
    public static let hairlineWidth: CGFloat = 0.75

    // 90/10 Controlled Semantic Palette
    public static let emerald = Color(hex: "#10B981")
    public static let coral = Color(hex: "#EF4444")
    public static let softCoral = Color(hex: "#F87171")
    public static let amber = Color(hex: "#F59E0B")
    public static let indigo = Color(hex: "#6366F1")
    public static let cyan = Color(hex: "#38BDF8")
    public static let slateLight = Color(hex: "#94A3B8")

    public static func windowBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#0D0D0F") : Color(hex: "#EBEBEF")
    }

    public static func sidebarBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#0F0F12") : Color(hex: "#ECECF0")
    }

    public static func canvasBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#161618") : Color(hex: "#F5F5F7")
    }

    public static func elevatedSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#1E1E22") : Color.white
    }

    public static func nestedSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#18181B") : Color(hex: "#F1F1F5")
    }

    public static func cardBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }

    public static func subtleDivider(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06)
    }

    public static func glassFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045)
    }

    public static func glassHoverFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08)
    }

    public static func ambientShadow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.32) : Color.black.opacity(0.045)
    }
}

public struct BentoCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public let padding: CGFloat
    public let cornerRadius: CGFloat
    public let accent: Color?
    public let isHighlighted: Bool

    public init(
        padding: CGFloat = 18,
        cornerRadius: CGFloat = FinSenseTheme.cardCornerRadius,
        accent: Color? = nil,
        isHighlighted: Bool = false
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.accent = accent
        self.isHighlighted = isHighlighted
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let borderColor: Color = {
            if isHighlighted, let accent {
                return accent.opacity(colorScheme == .dark ? 0.38 : 0.30)
            }
            return FinSenseTheme.cardBorder(for: colorScheme)
        }()

        content
            .padding(padding)
            .background {
                ZStack {
                    shape.fill(FinSenseTheme.elevatedSurface(for: colorScheme))
                    if isHighlighted, let accent {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(colorScheme == .dark ? 0.11 : 0.06),
                                    accent.opacity(0.01)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
            }
            .overlay(
                shape.strokeBorder(borderColor, lineWidth: isHighlighted ? 1 : FinSenseTheme.hairlineWidth)
            )
            .shadow(color: FinSenseTheme.ambientShadow(for: colorScheme), radius: isHighlighted ? 14 : 8, x: 0, y: 4)
    }
}

extension View {
    public func bentoCard(
        padding: CGFloat = 18,
        cornerRadius: CGFloat = FinSenseTheme.cardCornerRadius,
        accent: Color? = nil,
        isHighlighted: Bool = false
    ) -> some View {
        modifier(
            BentoCardModifier(
                padding: padding,
                cornerRadius: cornerRadius,
                accent: accent,
                isHighlighted: isHighlighted
            )
        )
    }

    public func numericCurrencyTransition<V: Equatable>(value: V) -> some View {
        self
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.28), value: value)
    }
}

public struct BentoGlassButtonStyle: ButtonStyle {
    public var tint: Color?
    public var cornerRadius: CGFloat
    public var verticalPadding: CGFloat
    public var horizontalPadding: CGFloat

    public init(
        tint: Color? = nil,
        cornerRadius: CGFloat = 9,
        verticalPadding: CGFloat = 6,
        horizontalPadding: CGFloat = 12
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
    }

    public func makeBody(configuration: Configuration) -> some View {
        BentoGlassButtonBody(
            configuration: configuration,
            tint: tint,
            cornerRadius: cornerRadius,
            verticalPadding: verticalPadding,
            horizontalPadding: horizontalPadding
        )
    }

    private struct BentoGlassButtonBody: View {
        @Environment(\.colorScheme) private var colorScheme
        @State private var isHovered = false
        let configuration: Configuration
        let tint: Color?
        let cornerRadius: CGFloat
        let verticalPadding: CGFloat
        let horizontalPadding: CGFloat

        var body: some View {
            let baseFill: Color = {
                if let tint {
                    return tint.opacity(isHovered ? 0.18 : 0.11)
                }
                return isHovered
                    ? FinSenseTheme.glassHoverFill(for: colorScheme)
                    : FinSenseTheme.glassFill(for: colorScheme)
            }()
            let strokeColor: Color = {
                if let tint {
                    return tint.opacity(isHovered ? 0.35 : 0.22)
                }
                return FinSenseTheme.cardBorder(for: colorScheme)
            }()

            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tint ?? .primary)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(baseFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: FinSenseTheme.hairlineWidth)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.snappy(duration: 0.16), value: configuration.isPressed)
                .animation(.snappy(duration: 0.16), value: isHovered)
                .onHover { hovering in
                    isHovered = hovering
                }
        }
    }
}

public struct BentoPrimaryButtonStyle: ButtonStyle {
    public var color: Color
    public var cornerRadius: CGFloat
    public var verticalPadding: CGFloat
    public var horizontalPadding: CGFloat

    public init(
        color: Color = FinSenseTheme.indigo,
        cornerRadius: CGFloat = 9,
        verticalPadding: CGFloat = 6.5,
        horizontalPadding: CGFloat = 13
    ) {
        self.color = color
        self.cornerRadius = cornerRadius
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
    }

    public func makeBody(configuration: Configuration) -> some View {
        BentoPrimaryButtonBody(
            configuration: configuration,
            color: color,
            cornerRadius: cornerRadius,
            verticalPadding: verticalPadding,
            horizontalPadding: horizontalPadding
        )
    }

    private struct BentoPrimaryButtonBody: View {
        @State private var isHovered = false
        let configuration: Configuration
        let color: Color
        let cornerRadius: CGFloat
        let verticalPadding: CGFloat
        let horizontalPadding: CGFloat

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(color.opacity(isHovered ? 0.92 : 1.0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75)
                )
                .shadow(color: color.opacity(0.24), radius: 6, x: 0, y: 2)
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.snappy(duration: 0.16), value: configuration.isPressed)
                .animation(.snappy(duration: 0.16), value: isHovered)
                .onHover { hovering in
                    isHovered = hovering
                }
        }
    }
}

public struct AppleIntelligenceStatusDot: View {
    @ObservedObject public var llmService: LocalLLMService
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    public init(llmService: LocalLLMService, store: FinancialDataStore) {
        self.llmService = llmService
        self.store = store
    }

    private var statusColor: Color {
        if llmService.isDownloading {
            return FinSenseTheme.cyan
        } else if store.hasInstalledLLMModel {
            return FinSenseTheme.emerald
        } else if LocalLLMRuntime.isAppleIntelligenceAvailable {
            return FinSenseTheme.amber
        } else {
            return .secondary
        }
    }

    private var tooltipText: String {
        if llmService.isDownloading {
            return "Preparando modelo IA local... Clique para ver detalhes"
        } else if store.hasInstalledLLMModel {
            let engine = llmService.activeEngineDescription.isEmpty ? "Apple Intelligence On-Device" : llmService.activeEngineDescription
            return "\(engine) • Clique para abrir Chat IA (⌘K)"
        } else if LocalLLMRuntime.isAppleIntelligenceAvailable {
            return "Apple Intelligence disponível • Clique para ativar ou abrir Chat IA (⌘K)"
        } else {
            return "IA Local em espera • Clique para configurar ou abrir assistente (⌘K)"
        }
    }

    public var body: some View {
        Button {
            store.openAIChat()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: statusColor.opacity(0.6), radius: 3)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovered ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isHovered ? FinSenseTheme.glassHoverFill(for: colorScheme) : FinSenseTheme.glassFill(for: colorScheme))
            )
            .overlay(
                Capsule()
                    .strokeBorder(FinSenseTheme.cardBorder(for: colorScheme), lineWidth: FinSenseTheme.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltipText)
    }
}
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import Charts

// MARK: - Native File Picker Helper (macOS NSOpenPanel)

public enum MacFilePicker {
    @MainActor
    public static func pickImageFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Selecionar Imagem ou Ícone do Mac"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .icns, .pdf]
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    public static func pickStatementFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Selecionar Extrato ou Relatório Financeiro (PDF, CSV, TXT)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf, .commaSeparatedText, .plainText, .text, .data]
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    public static func pickAttachmentFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Anexar Comprovante ou Documento"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item, .image, .pdf, .data]
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    public static func saveJSONFile(defaultFileName: String = "financial_backup_granular.json") -> URL? {
        let panel = NSSavePanel()
        panel.title = "Exportar Dados Financeiros (JSON Estruturado)"
        panel.nameFieldStringValue = defaultFileName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    public static func saveDatabaseBackupFile(defaultFileName: String = "financial_backup_completo.fcbackup") -> URL? {
        let panel = NSSavePanel()
        panel.title = "Exportar Backup Completo da Base de Dados (Exceto Modelos de IA)"
        panel.nameFieldStringValue = defaultFileName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.data, .json]
        panel.allowsOtherFileTypes = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    public static func pickJSONImportFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Importar Gastos / Transações (JSON)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    public static func pickDatabaseImportFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Selecionar Arquivo de Backup ou Importação (.fcbackup / .json)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data, .json, .item]
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - High-Quality Account Custom Icon Loader (Lanczos Retina Downsampling)

@MainActor
public final class AccountAvatarImageCache {
    public static let shared = AccountAvatarImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private let ciContext = CIContext(options: [
        .highQualityDownsample: true,
        .useSoftwareRenderer: false
    ])

    private init() {
        cache.countLimit = 128
    }

    public func crispImage(forFilePath path: String, pointSize: CGFloat) -> NSImage? {
        guard !path.isEmpty else { return nil }
        let backingScale = max(2.0, NSScreen.main?.backingScaleFactor ?? 2.0)
        // Oversample 3x when scale is 2x or use exact 3x/scale so curves & text downscale cleanly
        let effectiveScale = max(backingScale, 3.0)
        let targetPx = max(16.0, ceil(pointSize * effectiveScale))
        let modTimestamp = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(path)|\(Int(ceil(pointSize)))|\(Int(effectiveScale * 10))|\(Int(modTimestamp))" as NSString

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard let original = NSImage(contentsOfFile: path),
              let srcCG = original.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSImage(contentsOfFile: path)
        }

        let srcW = CGFloat(srcCG.width)
        let srcH = CGFloat(srcCG.height)
        guard srcW > 0, srcH > 0 else { return original }

        let fillScale = max(targetPx / srcW, targetPx / srcH)
        var resultImage: NSImage? = nil

        if fillScale < 0.95 {
            let ciInput = CIImage(cgImage: srcCG)
            let filter = CIFilter.lanczosScaleTransform()
            filter.inputImage = ciInput
            filter.scale = Float(fillScale)
            filter.aspectRatio = 1.0

            if let output = filter.outputImage {
                let scaledExtent = output.extent
                let cropOriginX = scaledExtent.origin.x + max(0, (scaledExtent.width - targetPx) / 2.0)
                let cropOriginY = scaledExtent.origin.y + max(0, (scaledExtent.height - targetPx) / 2.0)
                let cropRect = CGRect(
                    x: cropOriginX,
                    y: cropOriginY,
                    width: min(targetPx, scaledExtent.width),
                    height: min(targetPx, scaledExtent.height)
                )
                if let outCG = ciContext.createCGImage(output, from: cropRect) {
                    resultImage = NSImage(cgImage: outCG, size: NSSize(width: pointSize, height: pointSize))
                }
            }
        }

        if resultImage == nil {
            let pxInt = Int(targetPx)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let ctx = CGContext(
                data: nil,
                width: pxInt,
                height: pxInt,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                ctx.interpolationQuality = .high
                ctx.setShouldAntialias(true)
                ctx.setAllowsAntialiasing(true)
                let drawW = srcW * fillScale
                let drawH = srcH * fillScale
                let drawRect = CGRect(
                    x: (targetPx - drawW) / 2.0,
                    y: (targetPx - drawH) / 2.0,
                    width: drawW,
                    height: drawH
                )
                ctx.draw(srcCG, in: drawRect)
                if let outCG = ctx.makeImage() {
                    resultImage = NSImage(cgImage: outCG, size: NSSize(width: pointSize, height: pointSize))
                }
            }
        }

        let finalImage = resultImage ?? original
        cache.setObject(finalImage, forKey: cacheKey)
        return finalImage
    }
}

// MARK: - Bank / Custom Icon Avatar View

public struct AccountAvatarView: View {
    public let customImagePath: String?
    public let bankPresetId: String?
    public let fallbackSymbol: String
    public let colorHex: String
    public var size: CGFloat = 38

    public init(
        customImagePath: String? = nil,
        bankPresetId: String? = nil,
        fallbackSymbol: String = "building.columns.fill",
        colorHex: String = "#EC7000",
        size: CGFloat = 38
    ) {
        self.customImagePath = customImagePath
        self.bankPresetId = bankPresetId
        self.fallbackSymbol = fallbackSymbol
        self.colorHex = colorHex
        self.size = size
    }

    public init(account: BankAccount, size: CGFloat = 38) {
        self.customImagePath = account.customImagePath
        self.bankPresetId = account.bankPresetId
        self.fallbackSymbol = account.iconSymbol
        self.colorHex = account.colorHex
        self.size = size
    }

    public var body: some View {
        if let path = customImagePath,
           !path.isEmpty,
           let nsImage = AccountAvatarImageCache.shared.crispImage(forFilePath: path, pointSize: size) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
                )
        } else if let preset = BrazilianBanksCatalog.preset(for: bankPresetId) {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: preset.primaryHex), Color(hex: preset.secondaryHex)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(preset.monogram)
                    .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(3)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .shadow(color: Color(hex: preset.primaryHex).opacity(0.25), radius: 3, x: 0, y: 2)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(Color(hex: colorHex).gradient)
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Category Icon View

public struct CategoryBadgeView: View {
    public let symbol: String
    public let colorHex: String
    public var size: CGFloat = 34

    public init(symbol: String, colorHex: String, size: CGFloat = 34) {
        self.symbol = symbol
        self.colorHex = colorHex
        self.size = size
    }

    public init(category: CategoryItem?, size: CGFloat = 34) {
        self.symbol = category?.iconSymbol ?? "tag.fill"
        self.colorHex = category?.colorHex ?? "#64748B"
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color(hex: colorHex).opacity(0.16))
            Image(systemName: validSymbolName(symbol))
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(Color(hex: colorHex))
        }
        .frame(width: size, height: size)
    }

    private static let symbolCacheLock = NSLock()
    private static var validatedSymbolsCache: [String: String] = [:]

    private func validSymbolName(_ name: String) -> String {
        Self.symbolCacheLock.lock()
        if let cached = Self.validatedSymbolsCache[name] {
            Self.symbolCacheLock.unlock()
            return cached
        }
        Self.symbolCacheLock.unlock()

        let resolved = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "tag.fill"
        Self.symbolCacheLock.lock()
        Self.validatedSymbolsCache[name] = resolved
        Self.symbolCacheLock.unlock()
        return resolved
    }
}

// MARK: - Month Navigator Bar

public struct MonthNavigatorBar: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.colorScheme) private var colorScheme

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Button {
                    withAnimation(.snappy(duration: 0.24)) {
                        store.changeMonth(by: -1)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Mês anterior")

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(BRLFormatters.monthYear(store.selectedMonth))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.24), value: store.selectedMonth)
                        .frame(minWidth: 132)
                }
                .padding(.horizontal, 6)

                Button {
                    withAnimation(.snappy(duration: 0.24)) {
                        store.changeMonth(by: 1)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Próximo mês")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(FinSenseTheme.elevatedSurface(for: colorScheme))
            )
            .overlay(
                Capsule()
                    .strokeBorder(FinSenseTheme.cardBorder(for: colorScheme), lineWidth: FinSenseTheme.hairlineWidth)
            )

            Button {
                withAnimation(.snappy(duration: 0.24)) {
                    store.selectedMonth = Date()
                    store.ensureRecurringTransactionsMaterialized(upTo: store.endOfMonth(for: Date()))
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 11))
                    Text("Hoje")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(BentoGlassButtonStyle(cornerRadius: 14, verticalPadding: 5, horizontalPadding: 10))
            .help("Ir para o mês atual")
        }
    }
}

// MARK: - Dashboard Period Navigator Bar (Visão Mensal vs Visão Anual)

public struct DashboardPeriodNavigatorBar: View {
    @ObservedObject public var store: FinancialDataStore
    @Environment(\.colorScheme) private var colorScheme

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 10) {
            Picker("", selection: $store.dashboardPeriodMode) {
                ForEach(DashboardPeriodMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 196)
            .onChange(of: store.dashboardPeriodMode) { _, newMode in
                if newMode == .annual {
                    store.ensureRecurringTransactionsMaterialized(upTo: store.endOfYear(for: store.selectedMonth))
                } else {
                    store.ensureRecurringTransactionsMaterialized(upTo: store.endOfMonth(for: store.selectedMonth))
                }
            }

            if store.dashboardPeriodMode == .monthly {
                MonthNavigatorBar(store: store)
            } else {
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Button {
                            withAnimation(.snappy(duration: 0.24)) {
                                store.changeYear(by: -1)
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11.5, weight: .semibold))
                                .frame(width: 26, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Ano anterior")

                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("Ano \(BRLFormatters.yearString(store.selectedMonth))")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .contentTransition(.numericText())
                                .animation(.snappy(duration: 0.24), value: store.selectedMonth)
                                .frame(minWidth: 96)
                        }
                        .padding(.horizontal, 6)

                        Button {
                            withAnimation(.snappy(duration: 0.24)) {
                                store.changeYear(by: 1)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11.5, weight: .semibold))
                                .frame(width: 26, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Próximo ano")
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(FinSenseTheme.elevatedSurface(for: colorScheme))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(FinSenseTheme.cardBorder(for: colorScheme), lineWidth: FinSenseTheme.hairlineWidth)
                    )

                    Button {
                        withAnimation(.snappy(duration: 0.24)) {
                            store.selectedMonth = Date()
                            store.ensureRecurringTransactionsMaterialized(upTo: store.endOfYear(for: Date()))
                        }
                    } label: {
                        Text("Ano Atual")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(BentoGlassButtonStyle(cornerRadius: 14, verticalPadding: 5, horizontalPadding: 10))
                }
            }
        }
    }
}

// MARK: - Modern KPI Summary Card

public struct MetricCardView: View {
    public static let standardCardHeight: CGFloat = 120
    @Environment(\.colorScheme) private var colorScheme

    public let title: String
    public let value: String
    public var valueColor: Color? = nil
    public let subtitle: String
    public var customSubtitle: Text? = nil
    public let icon: String
    public let tint: Color
    public var footnote: String?
    public var footnoteColor: Color
    public var action: (() -> Void)?
    public var actionLabel: String?
    public var actionIcon: String?
    public var subtitleHelp: String?
    public var intraMonthAnalysis: IntraMonthCashFlowAnalysis?
    public var cardHeight: CGFloat = MetricCardView.standardCardHeight
    public var isHero: Bool = false

    public init(
        title: String,
        value: String,
        valueColor: Color? = nil,
        subtitle: String = "",
        customSubtitle: Text? = nil,
        icon: String,
        tint: Color,
        footnote: String? = nil,
        footnoteColor: Color = .secondary,
        action: (() -> Void)? = nil,
        actionLabel: String? = nil,
        actionIcon: String? = nil,
        subtitleHelp: String? = nil,
        intraMonthAnalysis: IntraMonthCashFlowAnalysis? = nil,
        cardHeight: CGFloat = MetricCardView.standardCardHeight,
        isHero: Bool = false
    ) {
        self.title = title
        self.value = value
        self.valueColor = valueColor
        self.subtitle = subtitle
        self.customSubtitle = customSubtitle
        self.icon = icon
        self.tint = tint
        self.footnote = footnote
        self.footnoteColor = footnoteColor
        self.action = action
        self.actionLabel = actionLabel
        self.actionIcon = actionIcon
        self.subtitleHelp = subtitleHelp
        self.intraMonthAnalysis = intraMonthAnalysis
        self.cardHeight = cardHeight
        self.isHero = isHero
    }

    public static func despesasLancadasSubtitle(
        paidExpense: Double,
        pendingExpense: Double,
        isPast: Bool,
        isAnnual: Bool = false
    ) -> (text: String, styled: Text) {
        if isPast {
            let text = "\(BRLFormatters.currency(paidExpense)) pagas no período"
            return (text, Text(text).foregroundColor(.secondary))
        }
        let suffix = isAnnual ? " no ano" : ""
        let paidPart = "\(BRLFormatters.currency(paidExpense)) pagas • "
        let pendingPart = "\(BRLFormatters.currency(pendingExpense)) pendentes\(suffix)"
        let text = paidPart + pendingPart
        let styled = Text(paidPart).foregroundColor(.secondary)
            + Text(pendingPart).foregroundColor(FinSenseTheme.coral)
        return (text, styled)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 1. Linha de Cabeçalho (Topo)
            HStack(alignment: .center, spacing: 6) {
                Text(title)
                    .font(.system(size: isHero ? 13 : 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                if let action {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            if let actionIcon {
                                Image(systemName: actionIcon)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            if let actionLabel {
                                Text(actionLabel)
                                    .font(.system(size: 10.5, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(tint.opacity(0.12))
                        .foregroundStyle(tint)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Editar previsões e tetos deste mês")
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(colorScheme == .dark ? 0.14 : 0.10))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(minHeight: 30, alignment: .center)

            // 2. Valor Principal com transição numérica suave
            Text(value)
                .font(.system(size: isHero ? 28 : 21, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .numericCurrencyTransition(value: value)

            // 3. Subtítulo / Metadados
            VStack(alignment: .leading, spacing: 3) {
                let subtitleLines = intraMonthAnalysis == nil ? 2 : 3
                if let customSubtitle {
                    if let subtitleHelp {
                        customSubtitle
                            .font(.system(size: 11.5, weight: .regular))
                            .lineLimit(subtitleLines)
                            .minimumScaleFactor(0.78)
                            .help(subtitleHelp)
                    } else {
                        customSubtitle
                            .font(.system(size: 11.5, weight: .regular))
                            .lineLimit(subtitleLines)
                            .minimumScaleFactor(0.78)
                    }
                } else if let subtitleHelp {
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLines)
                        .minimumScaleFactor(0.78)
                        .help(subtitleHelp)
                } else if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLines)
                        .minimumScaleFactor(0.78)
                }

                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(footnoteColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                if let intra = intraMonthAnalysis, !intra.dailyPoints.isEmpty {
                    IntraMonthSparklineView(analysis: intra, height: 22)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: cardHeight, alignment: .topLeading)
        .bentoCard(
            padding: 16,
            cornerRadius: FinSenseTheme.cardCornerRadius,
            accent: tint,
            isHighlighted: isHero
        )
    }
}

// MARK: - Mini Gráfico Sparkline de Fluxo Intramês (Zona Negativa em Vermelho)

public struct IntraMonthSparklineView: View {
    public let analysis: IntraMonthCashFlowAnalysis
    public var height: CGFloat = 22

    public init(analysis: IntraMonthCashFlowAnalysis, height: CGFloat = 22) {
        self.analysis = analysis
        self.height = height
    }

    private var lineColor: Color {
        switch analysis.alertLevel {
        case .confirmedDeficit: return FinSenseTheme.coral
        case .possibleRisk: return FinSenseTheme.amber
        case .none: return FinSenseTheme.emerald
        }
    }

    public var body: some View {
        Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.secondary.opacity(0.28))
                .lineStyle(StrokeStyle(lineWidth: 0.7, dash: [2, 2]))

            ForEach(analysis.dailyPoints) { pt in
                LineMark(
                    x: .value("Dia", pt.day),
                    y: .value("Saldo", pt.closingBalance)
                )
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                if pt.closingBalance < -0.005 {
                    AreaMark(
                        x: .value("Dia", pt.day),
                        yStart: .value("Zero", 0.0),
                        yEnd: .value("Saldo", pt.closingBalance)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [FinSenseTheme.coral.opacity(0.35), FinSenseTheme.coral.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    PointMark(
                        x: .value("Dia", pt.day),
                        y: .value("Saldo", pt.closingBalance)
                    )
                    .symbolSize(12)
                    .foregroundStyle(FinSenseTheme.coral)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: height)
        .help(analysis.alertSummaryText ?? "Evolução diária de saldo no mês")
    }
}

// MARK: - Native AppKit Full-Width Clickable Input with Auto-Hiding Placeholder

public final class FullWidthClickableNSTextField: NSTextField {
    public override var intrinsicContentSize: NSSize {
        let superSize = super.intrinsicContentSize
        return NSSize(width: NSView.noIntrinsicMetric, height: max(superSize.height, 20))
    }

    public override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== currentEditor() {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }
}

public final class FullWidthClickableNSSecureTextField: NSSecureTextField {
    public override var intrinsicContentSize: NSSize {
        let superSize = super.intrinsicContentSize
        return NSSize(width: NSView.noIntrinsicMetric, height: max(superSize.height, 20))
    }

    public override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== currentEditor() {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }
}

public final class ClickableFieldWrapperNSView: NSView {
    public let placeholderLabel = NSTextField(labelWithString: "")
    public let textField = FullWidthClickableNSTextField()
    public let secureField = FullWidthClickableNSSecureTextField()
    public var isSecureMode: Bool = false {
        didSet {
            textField.isHidden = isSecureMode
            secureField.isHidden = !isSecureMode
            updatePlaceholderVisibility()
        }
    }

    public var activeField: NSTextField {
        isSecureMode ? secureField : textField
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        setContentHuggingPriority(.init(1), for: .horizontal)
        setContentCompressionResistancePriority(.init(1), for: .horizontal)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.isBordered = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.alignment = .left
        placeholderLabel.lineBreakMode = .byTruncatingTail
        placeholderLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        placeholderLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        for field in [textField, secureField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.isEditable = true
            field.isSelectable = true
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.alignment = .left
            field.lineBreakMode = .byTruncatingTail
            field.cell?.wraps = false
            field.cell?.isScrollable = true
            field.placeholderString = nil
            field.setContentHuggingPriority(.init(1), for: .horizontal)
            field.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        }

        secureField.isHidden = true

        addSubview(placeholderLabel)
        addSubview(textField)
        addSubview(secureField)

        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),

            secureField.leadingAnchor.constraint(equalTo: leadingAnchor),
            secureField.trailingAnchor.constraint(equalTo: trailingAnchor),
            secureField.topAnchor.constraint(equalTo: topAnchor),
            secureField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 22)
    }

    public func updatePlaceholderVisibility() {
        let current = activeField.stringValue
        placeholderLabel.isHidden = !current.isEmpty
    }

    public func focusActiveField() {
        guard let win = window else { return }
        if win.firstResponder !== activeField.currentEditor() {
            win.makeFirstResponder(activeField)
            if let editor = activeField.currentEditor() {
                let len = activeField.stringValue.utf16.count
                editor.selectedRange = NSRange(location: len, length: 0)
            }
        }
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }
        return activeField
    }

    public override func mouseDown(with event: NSEvent) {
        focusActiveField()
    }
}

public struct MacFullWidthTextInput: NSViewRepresentable {
    @Binding public var text: String
    public var placeholder: String
    public var font: NSFont
    public var isSecure: Bool
    public var focusTrigger: Int
    public var formatterTransform: ((String) -> String)?
    public var onFocusChange: ((Bool) -> Void)?
    public var onCommit: (() -> Void)?

    public init(
        text: Binding<String>,
        placeholder: String,
        font: NSFont = .systemFont(ofSize: 13.5),
        isSecure: Bool = false,
        focusTrigger: Int = 0,
        formatterTransform: ((String) -> String)? = nil,
        onFocusChange: ((Bool) -> Void)? = nil,
        onCommit: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.font = font
        self.isSecure = isSecure
        self.focusTrigger = focusTrigger
        self.formatterTransform = formatterTransform
        self.onFocusChange = onFocusChange
        self.onCommit = onCommit
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> ClickableFieldWrapperNSView {
        let wrapper = ClickableFieldWrapperNSView()
        wrapper.placeholderLabel.stringValue = placeholder
        wrapper.placeholderLabel.font = font
        wrapper.textField.font = font
        wrapper.secureField.font = font
        wrapper.textField.delegate = context.coordinator
        wrapper.secureField.delegate = context.coordinator
        wrapper.isSecureMode = isSecure
        wrapper.textField.stringValue = text
        wrapper.secureField.stringValue = text
        wrapper.updatePlaceholderVisibility()
        return wrapper
    }

    public func updateNSView(_ nsView: ClickableFieldWrapperNSView, context: Context) {
        context.coordinator.parent = self

        if nsView.placeholderLabel.stringValue != placeholder {
            nsView.placeholderLabel.stringValue = placeholder
        }
        if nsView.textField.font != font {
            nsView.placeholderLabel.font = font
            nsView.textField.font = font
            nsView.secureField.font = font
        }
        if nsView.isSecureMode != isSecure {
            nsView.isSecureMode = isSecure
        }

        let currentField = nsView.activeField
        if currentField.stringValue != text {
            nsView.textField.stringValue = text
            nsView.secureField.stringValue = text
            if let editor = currentField.currentEditor() {
                editor.string = text
                let endPos = text.utf16.count
                editor.selectedRange = NSRange(location: endPos, length: 0)
            }
        }
        nsView.updatePlaceholderVisibility()

        if context.coordinator.lastFocusTrigger != focusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                nsView.focusActiveField()
            }
        }
    }

    public final class Coordinator: NSObject, NSTextFieldDelegate {
        public var parent: MacFullWidthTextInput
        public var lastFocusTrigger: Int = 0

        public init(_ parent: MacFullWidthTextInput) {
            self.parent = parent
            self.lastFocusTrigger = parent.focusTrigger
        }

        public func controlTextDidBeginEditing(_ obj: Notification) {
            if let field = obj.object as? NSTextField,
               let wrapper = field.superview as? ClickableFieldWrapperNSView {
                wrapper.updatePlaceholderVisibility()
            }
            parent.onFocusChange?(true)
        }

        public func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let rawValue = field.stringValue
            let finalValue: String
            if let transform = parent.formatterTransform {
                finalValue = transform(rawValue)
                if field.stringValue != finalValue {
                    field.stringValue = finalValue
                    if let editor = field.currentEditor() {
                        editor.string = finalValue
                        let endPos = finalValue.utf16.count
                        editor.selectedRange = NSRange(location: endPos, length: 0)
                    }
                }
            } else {
                finalValue = rawValue
            }

            if let wrapper = field.superview as? ClickableFieldWrapperNSView {
                wrapper.textField.stringValue = finalValue
                wrapper.secureField.stringValue = finalValue
                wrapper.updatePlaceholderVisibility()
            }

            if parent.text != finalValue {
                parent.text = finalValue
            }
        }

        public func controlTextDidEndEditing(_ obj: Notification) {
            if let field = obj.object as? NSTextField,
               let wrapper = field.superview as? ClickableFieldWrapperNSView {
                wrapper.updatePlaceholderVisibility()
            }
            parent.onFocusChange?(false)
        }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if let onCommit = parent.onCommit {
                    onCommit()
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - Visible Bordered Text Input, BRL Currency Masked Input & Editable Integer Stepper

public struct BorderedTextField: View {
    public let label: String?
    public let placeholder: String
    @Binding public var text: String
    public var suffix: String? = nil
    public var isSecure: Bool = false
    public var onCommit: (() -> Void)? = nil

    @State private var focusTrigger: Int = 0
    @State private var isFocused: Bool = false

    public init(
        label: String? = nil,
        placeholder: String,
        text: Binding<String>,
        suffix: String? = nil,
        isSecure: Bool = false,
        onCommit: (() -> Void)? = nil
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.suffix = suffix
        self.isSecure = isSecure
        self.onCommit = onCommit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                MacFullWidthTextInput(
                    text: $text,
                    placeholder: placeholder,
                    font: .systemFont(ofSize: 13.5),
                    isSecure: isSecure,
                    focusTrigger: focusTrigger,
                    onFocusChange: { focused in
                        isFocused = focused
                    },
                    onCommit: onCommit
                )
                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)

                if let suffix, !suffix.isEmpty {
                    Text(suffix)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isFocused ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.32),
                        lineWidth: isFocused ? 1.6 : 1.2
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                focusTrigger += 1
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Input monetário com borda visível, clicável em toda a extensão, permitindo apenas números e aplicando máscara de Real (R$ 1.234,56)
public struct BRLCurrencyTextField: View {
    public let label: String
    @Binding public var text: String
    public var placeholder: String

    @State private var focusTrigger: Int = 0
    @State private var isFocused: Bool = false

    public init(
        label: String,
        text: Binding<String>,
        placeholder: String = "R$ 0,00"
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("R$")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    )
                    .foregroundStyle(Color.accentColor)

                MacFullWidthTextInput(
                    text: $text,
                    placeholder: placeholder,
                    font: .systemFont(ofSize: 14, weight: .semibold),
                    focusTrigger: focusTrigger,
                    formatterTransform: { raw in
                        BRLFormatters.formatCurrencyMaskedInput(raw)
                    },
                    onFocusChange: { focused in
                        isFocused = focused
                    }
                )
                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isFocused ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.32),
                        lineWidth: isFocused ? 1.6 : 1.2
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                focusTrigger += 1
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Campo numérico com borda visível que permite digitar manualmente números inteiros (ex: quantidade de parcelas ou meses) + Stepper
public struct EditableIntegerStepperField: View {
    public let label: String
    @Binding public var value: Int
    public let range: ClosedRange<Int>
    public var unitSuffix: String

    @State private var textValue: String = ""
    @State private var focusTrigger: Int = 0
    @State private var isFocused: Bool = false

    public init(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        unitSuffix: String = "x"
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.unitSuffix = unitSuffix
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    MacFullWidthTextInput(
                        text: $textValue,
                        placeholder: "\(range.lowerBound)",
                        font: .systemFont(ofSize: 14, weight: .bold),
                        focusTrigger: focusTrigger,
                        formatterTransform: { raw in
                            BRLFormatters.formatDigitsOnly(raw, maxDigits: 4)
                        },
                        onFocusChange: { focused in
                            isFocused = focused
                            if !focused {
                                // Ao sair do foco, normaliza o texto dentro do limite permitido
                                if let parsed = Int(textValue) {
                                    let clamped = min(max(parsed, range.lowerBound), range.upperBound)
                                    value = clamped
                                    textValue = "\(clamped)"
                                } else {
                                    textValue = "\(value)"
                                }
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
                    .onChange(of: textValue) { _, newValue in
                        if let parsed = Int(newValue) {
                            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
                            if value != clamped {
                                value = clamped
                            }
                        }
                    }

                    if !unitSuffix.isEmpty {
                        Text(unitSuffix)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isFocused ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.32),
                            lineWidth: isFocused ? 1.6 : 1.2
                        )
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    focusTrigger += 1
                }

                Stepper(
                    "",
                    value: Binding(
                        get: { value },
                        set: { newVal in
                            let clamped = min(max(newVal, range.lowerBound), range.upperBound)
                            value = clamped
                            textValue = "\(clamped)"
                        }
                    ),
                    in: range
                )
                .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            textValue = "\(value)"
        }
        .onChange(of: value) { _, newVal in
            if !isFocused {
                let str = "\(newVal)"
                if textValue != str {
                    textValue = str
                }
            }
        }
    }
}

// MARK: - Native AppKit Full-Area Multiline Text Editor with Auto-Hiding Placeholder & Border

public final class ClickableMultilineScrollView: NSScrollView {
    public let placeholderLabel = NSTextField(wrappingLabelWithString: "")

    public func updatePlaceholderVisibility(currentText: String) {
        placeholderLabel.isHidden = !currentText.isEmpty
    }

    public override func mouseDown(with event: NSEvent) {
        if let docView = documentView {
            window?.makeFirstResponder(docView)
        }
        super.mouseDown(with: event)
    }
}

public struct MacMultilineTextInput: NSViewRepresentable {
    @Binding public var text: String
    public var placeholder: String
    public var font: NSFont
    public var focusTrigger: Int
    public var onFocusChange: ((Bool) -> Void)?

    public init(
        text: Binding<String>,
        placeholder: String,
        font: NSFont = .monospacedSystemFont(ofSize: 12.5, weight: .regular),
        focusTrigger: Int = 0,
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.font = font
        self.focusTrigger = focusTrigger
        self.onFocusChange = onFocusChange
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> ClickableMultilineScrollView {
        let scrollView = ClickableMultilineScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = font
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView

        let placeholderField = scrollView.placeholderLabel
        placeholderField.translatesAutoresizingMaskIntoConstraints = false
        placeholderField.isEditable = false
        placeholderField.isSelectable = false
        placeholderField.isBordered = false
        placeholderField.drawsBackground = false
        placeholderField.textColor = .placeholderTextColor
        placeholderField.font = font
        placeholderField.stringValue = placeholder
        placeholderField.maximumNumberOfLines = 6

        scrollView.addSubview(placeholderField)
        NSLayoutConstraint.activate([
            placeholderField.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            placeholderField.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            placeholderField.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 6)
        ])

        scrollView.updatePlaceholderVisibility(currentText: text)
        return scrollView
    }

    public func updateNSView(_ nsView: ClickableMultilineScrollView, context: Context) {
        context.coordinator.parent = self
        if nsView.placeholderLabel.stringValue != placeholder {
            nsView.placeholderLabel.stringValue = placeholder
        }
        if let textView = nsView.documentView as? NSTextView {
            if textView.string != text {
                textView.string = text
            }
            if textView.font != font {
                textView.font = font
                nsView.placeholderLabel.font = font
            }
            if context.coordinator.lastFocusTrigger != focusTrigger {
                context.coordinator.lastFocusTrigger = focusTrigger
                DispatchQueue.main.async {
                    nsView.window?.makeFirstResponder(textView)
                }
            }
        }
        nsView.updatePlaceholderVisibility(currentText: text)
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        public var parent: MacMultilineTextInput
        public var lastFocusTrigger: Int = 0

        public init(_ parent: MacMultilineTextInput) {
            self.parent = parent
            self.lastFocusTrigger = parent.focusTrigger
        }

        public func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange?(true)
        }

        public func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange?(false)
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newStr = textView.string
            if let scrollView = textView.enclosingScrollView as? ClickableMultilineScrollView {
                scrollView.updatePlaceholderVisibility(currentText: newStr)
            }
            if parent.text != newStr {
                parent.text = newStr
            }
        }
    }
}

public struct BorderedMultilineTextEditor: View {
    public let label: String
    public let placeholder: String
    @Binding public var text: String
    public var minHeight: CGFloat = 120

    @State private var focusTrigger: Int = 0
    @State private var isFocused: Bool = false

    public init(
        label: String = "",
        placeholder: String,
        text: Binding<String>,
        minHeight: CGFloat = 120
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.minHeight = minHeight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            MacMultilineTextInput(
                text: $text,
                placeholder: placeholder,
                focusTrigger: focusTrigger,
                onFocusChange: { focused in
                    isFocused = focused
                }
            )
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight + 40)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isFocused ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.32),
                        lineWidth: isFocused ? 1.6 : 1.2
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                focusTrigger += 1
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
