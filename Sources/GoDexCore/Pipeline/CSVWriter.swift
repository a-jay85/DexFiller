import Foundation

/// Writes PokemonRecord arrays to CSV files.
public final class CSVWriter: Sendable {
    /// Confidence threshold below which rows are flagged for review.
    public let reviewThreshold: Double

    public init(reviewThreshold: Double = 0.7) {
        self.reviewThreshold = reviewThreshold
    }

    /// Write records to a CSV file at the specified URL.
    public func write(_ records: [PokemonRecord], to url: URL) throws {
        let csv = formatCSV(records)
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Format records as a CSV string.
    public func formatCSV(_ records: [PokemonRecord]) -> String {
        var lines = [PokemonRecord.csvHeader]
        for record in records {
            lines.append(record.csvRow)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Returns records that are below the review threshold.
    public func flaggedForReview(_ records: [PokemonRecord]) -> [PokemonRecord] {
        return records.filter { $0.confidence < reviewThreshold }
    }

    /// Summary statistics for a batch of records.
    public func summary(_ records: [PokemonRecord]) -> ProcessingSummary {
        let total = records.count
        let flagged = flaggedForReview(records).count
        let avgConfidence = records.isEmpty ? 0 : records.map(\.confidence).reduce(0, +) / Double(total)
        let withIVs = records.filter { $0.attackIV != nil && $0.defenseIV != nil && $0.staminaIV != nil }.count
        let withMoves = records.filter { $0.fastMove != nil }.count

        return ProcessingSummary(
            totalRecords: total,
            flaggedForReview: flagged,
            averageConfidence: avgConfidence,
            recordsWithIVs: withIVs,
            recordsWithMoves: withMoves
        )
    }
}

public struct ProcessingSummary: Sendable {
    public let totalRecords: Int
    public let flaggedForReview: Int
    public let averageConfidence: Double
    public let recordsWithIVs: Int
    public let recordsWithMoves: Int
}
