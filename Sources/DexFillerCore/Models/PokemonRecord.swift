import Foundation

/// A single Pokemon's extracted data, ready for CSV export.
public struct PokemonRecord: Sendable, Identifiable {
    public let id: UUID

    // Core identity
    public var species: String?
    public var nickname: String?
    public var cp: Int?
    public var hp: Int?

    // Level (derived from stardust cost)
    public var level: Double?
    public var stardustCost: Int?

    // IVs (0–15 each)
    public var attackIV: Int?
    public var defenseIV: Int?
    public var staminaIV: Int?

    /// Calculated: (atk + def + sta) / 45
    public var ivPercentage: Double? {
        guard let atk = attackIV, let def = defenseIV, let sta = staminaIV else {
            return nil
        }
        return Double(atk + def + sta) / 45.0
    }

    // Moves
    public var fastMove: String?
    public var chargedMove1: String?
    public var chargedMove2: String?

    // Catch info
    public var catchDate: String?
    public var catchLocation: String?

    // Physical stats
    public var weight: Double?
    public var height: Double?

    // Visual tags
    public var shiny: Bool = false
    public var lucky: Bool = false
    public var shadow: Bool = false
    public var purified: Bool = false

    // Confidence (0.0–1.0, minimum across all fields)
    public var confidence: Double = 0.0

    // Source frame references (for review mode)
    public var infoFrameTimestamp: Double?
    public var appraisalFrameTimestamp: Double?

    public init(id: UUID = UUID()) {
        self.id = id
    }

    /// CSV header row
    public static let csvHeader = "species,nickname,cp,hp,level,attack_iv,defense_iv,stamina_iv,iv_percentage,fast_move,charged_move_1,charged_move_2,catch_date,catch_location,weight,height,shiny,lucky,shadow,purified,confidence"

    /// Format as a CSV row
    public var csvRow: String {
        let fields: [String] = [
            csvEscape(species),
            csvEscape(nickname),
            cp.map(String.init) ?? "",
            hp.map(String.init) ?? "",
            level.map { String(format: "%.1f", $0) } ?? "",
            attackIV.map(String.init) ?? "",
            defenseIV.map(String.init) ?? "",
            staminaIV.map(String.init) ?? "",
            ivPercentage.map { String(format: "%.1f", $0 * 100) } ?? "",
            csvEscape(fastMove),
            csvEscape(chargedMove1),
            csvEscape(chargedMove2),
            csvEscape(catchDate),
            csvEscape(catchLocation),
            weight.map { String(format: "%.2f", $0) } ?? "",
            height.map { String(format: "%.2f", $0) } ?? "",
            shiny ? "true" : "false",
            lucky ? "true" : "false",
            shadow ? "true" : "false",
            purified ? "true" : "false",
            String(format: "%.2f", confidence),
        ]
        return fields.joined(separator: ",")
    }

    private func csvEscape(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
