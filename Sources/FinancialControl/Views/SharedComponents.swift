import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
           let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
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

    private func validSymbolName(_ name: String) -> String {
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return name
        }
        return "tag.fill"
    }
}

// MARK: - Month Navigator Bar

public struct MonthNavigatorBar: View {
    @ObservedObject public var store: FinancialDataStore

    public init(store: FinancialDataStore) {
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 10) {
            Button {
                store.changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .help("Mês anterior")

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                Text(BRLFormatters.monthYear(store.selectedMonth))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(minWidth: 150)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Button {
                store.changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .help("Próximo mês")

            Menu {
                Button("Mês Atual (Hoje)") {
                    store.selectedMonth = Date()
                }
                if let nov2026 = BRLFormatters.shortDateFormatter.date(from: "05/11/2026") {
                    Button("Novembro de 2026 (Extrato)") {
                        store.selectedMonth = nov2026
                    }
                }
                if let oct2026 = BRLFormatters.shortDateFormatter.date(from: "15/10/2026") {
                    Button("Outubro de 2026 (Extrato)") {
                        store.selectedMonth = oct2026
                    }
                }
                if let sep2026 = BRLFormatters.shortDateFormatter.date(from: "15/09/2026") {
                    Button("Setembro de 2026 (Extrato)") {
                        store.selectedMonth = sep2026
                    }
                }
            } label: {
                Label("Ir para", systemImage: "calendar.badge.clock")
                    .font(.caption)
            }
            .menuStyle(.borderedButton)
            .fixedSize()
        }
    }
}

// MARK: - Modern KPI Summary Card

public struct MetricCardView: View {
    public let title: String
    public let value: String
    public let subtitle: String
    public let icon: String
    public let tint: Color

    public init(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        tint: Color
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}
