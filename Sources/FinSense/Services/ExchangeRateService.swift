import Foundation
import Combine

/// Serviço offline-first de cotações cambiais com persistência local em disco, atualização pública somente leitura
/// (AwesomeAPI / Frankfurter) e suporte a taxas manuais de fallback.
@MainActor
public final class ExchangeRateService: ObservableObject {
    public static let shared = ExchangeRateService()

    @Published public private(set) var ratesToBRL: [String: Double] = [:]
    @Published public private(set) var lastUpdatedAt: Date? = nil
    @Published public private(set) var isRefreshing: Bool = false
    @Published public var manualOverrideRatesToBRL: [String: Double] = [:] {
        didSet { persistCache() }
    }

    private let cacheFileURL: URL

    public init(customDirectory: URL? = nil) {
        let baseDir: URL = {
            if let customDirectory { return customDirectory }
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            return appSupport.appendingPathComponent("FinSense", isDirectory: true)
        }()
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        self.cacheFileURL = baseDir.appendingPathComponent("fx_rates_cache.json")
        loadCache()
    }

    private struct CachePayload: Codable {
        var ratesToBRL: [String: Double]
        var manualOverrideRatesToBRL: [String: Double]
        var lastUpdatedAt: Date?
    }

    private func loadCache() {
        var initial: [String: Double] = ["BRL": 1.0]
        for cur in SupportedCurrency.allCases where cur != .BRL {
            initial[cur.rawValue] = cur.defaultFallbackRateToBRL
        }
        if let data = try? Data(contentsOf: cacheFileURL),
           let decoded = try? JSONDecoder().decode(CachePayload.self, from: data) {
            for (k, v) in decoded.ratesToBRL where v > 0 {
                initial[k.uppercased()] = v
            }
            self.manualOverrideRatesToBRL = decoded.manualOverrideRatesToBRL
            self.lastUpdatedAt = decoded.lastUpdatedAt
        }
        self.ratesToBRL = initial
    }

    private func persistCache() {
        let payload = CachePayload(
            ratesToBRL: ratesToBRL,
            manualOverrideRatesToBRL: manualOverrideRatesToBRL,
            lastUpdatedAt: lastUpdatedAt
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }

    /// Retorna a cotação para converter 1 unidade de `currencyCode` em BRL.
    /// Prioriza override manual (caso configurado), depois última cotação em cache, depois fallback seguro.
    public func rateToBRL(for currencyCode: String) -> Double {
        let code = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if code.isEmpty || code == "BRL" { return 1.0 }
        if let manual = manualOverrideRatesToBRL[code], manual > 0 {
            return manual
        }
        if let cached = ratesToBRL[code], cached > 0 {
            return cached
        }
        return SupportedCurrency(rawValue: code)?.defaultFallbackRateToBRL ?? 1.0
    }

    public func convertToBRL(_ amount: Double, currencyCode: String) -> Double {
        amount * rateToBRL(for: currencyCode)
    }

    public func setManualOverride(rate: Double?, for currencyCode: String) {
        let code = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code != "BRL", !code.isEmpty else { return }
        if let rate, rate > 0 {
            manualOverrideRatesToBRL[code] = rate
        } else {
            manualOverrideRatesToBRL.removeValue(forKey: code)
        }
        objectWillChange.send()
    }

    /// Atualiza cotações em background usando API pública de câmbio (AwesomeAPI + fallback Frankfurter).
    public func refreshRates(currencies: [SupportedCurrency] = SupportedCurrency.allCases.filter { $0 != .BRL }) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let codes = currencies.filter { $0 != .BRL }.map(\.rawValue)
        let fetched = await InternetLookupService.fetchExchangeRates(requestedCodes: codes)
        var updated = ratesToBRL
        updated["BRL"] = 1.0
        for item in fetched where item.bid > 0 {
            updated[item.code.uppercased()] = item.bid
        }

        // Complementa moedas não retornadas via Frankfurter (ex.: JPY, CHF, CAD, AUD se necessário)
        let missing = codes.filter { code in !fetched.contains(where: { $0.code.uppercased() == code.uppercased() }) }
        if !missing.isEmpty,
           let url = URL(string: "https://api.frankfurter.app/latest?from=BRL&to=\(missing.joined(separator: ","))") {
            var req = URLRequest(url: url)
            req.timeoutInterval = 6.0
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ratesDict = json["rates"] as? [String: Double] {
                for (code, brlToForeign) in ratesDict where brlToForeign > 0 {
                    updated[code.uppercased()] = 1.0 / brlToForeign
                }
            }
        }

        self.ratesToBRL = updated
        self.lastUpdatedAt = Date()
        persistCache()
    }
}
