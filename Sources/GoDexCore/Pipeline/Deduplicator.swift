import Foundation

/// Removes duplicate Pokemon records that result from multiple frames
/// showing the same Pokemon.
///
/// Deduplication matches on species + CP + HP + weight, since all four
/// are visible on the appraisal screen, the initial info screen position,
/// and most scroll positions of the info screen.
public final class Deduplicator: Sendable {

    public init() {}

    /// Remove duplicate records, keeping the one with highest confidence.
    public func deduplicate(_ records: [PokemonRecord]) -> [PokemonRecord] {
        var seen: [String: PokemonRecord] = [:]

        for record in records {
            let key = deduplicationKey(for: record)

            if let existing = seen[key] {
                // Keep the record with higher confidence
                if record.confidence > existing.confidence {
                    seen[key] = record
                }
            } else {
                seen[key] = record
            }
        }

        // Preserve original order (first occurrence order)
        var result: [PokemonRecord] = []
        var addedKeys: Set<String> = []

        for record in records {
            let key = deduplicationKey(for: record)
            if !addedKeys.contains(key) {
                if let best = seen[key] {
                    result.append(best)
                }
                addedKeys.insert(key)
            }
        }

        return result
    }

    private func deduplicationKey(for record: PokemonRecord) -> String {
        let species = record.species?.lowercased() ?? "unknown"
        let cp = record.cp.map(String.init) ?? "?"
        let hp = record.hp.map(String.init) ?? "?"
        let weight = record.weight.map { String(format: "%.1f", $0) } ?? "?"

        return "\(species)|\(cp)|\(hp)|\(weight)"
    }
}
