import Foundation

/// Links appraisal data with the preceding info screen data
/// to produce complete PokemonRecord objects.
///
/// The expected flow in a Pokemon GO recording is:
/// Info Screen → Appraisal Overlay → Info Screen → Appraisal Overlay → ...
/// Each appraisal is linked to the most recent preceding info screen.
public final class PokemonLinker: Sendable {

    /// Confidence cap applied when CP could not be read, so the record drops
    /// below the default review threshold and is surfaced for manual entry.
    private static let unverifiedCPConfidence = 0.4

    public init() {}

    /// Link frame groups into complete Pokemon records.
    /// Groups should be in chronological order.
    public func link(groups: [FrameGroup], infoExtractor: InfoScreenExtractor, appraisalExtractor: AppraisalExtractor) async throws -> [PokemonRecord] {
        var records: [PokemonRecord] = []
        var lastInfoRecord: PokemonRecord?

        for group in groups {
            switch group.screenType {
            case .infoScreen:
                let result = try await infoExtractor.extract(from: group.bestFrame.image)
                var record = result.record
                record.infoFrameTimestamp = group.bestFrame.timestamp
                lastInfoRecord = record

            case .appraisalOverlay:
                let appraisalResult = try await appraisalExtractor.extract(from: group.bestFrame.image)
                records.append(merge(
                    info: lastInfoRecord,
                    appraisal: appraisalResult,
                    appraisalTimestamp: group.bestFrame.timestamp
                ))
                lastInfoRecord = nil // Consumed (or there was none)

            case .other:
                continue
            }
        }

        // If there's a trailing info screen without appraisal, include it as partial
        if var record = lastInfoRecord {
            record.confidence *= 0.7 // Lower confidence without appraisal
            records.append(record)
        }

        return records
    }

    /// Combine an appraisal read with the preceding info-screen record (if any)
    /// into one `PokemonRecord`. Pure and `internal` so the merge rules can be
    /// unit-tested without synthesizing frames.
    ///
    /// Field provenance:
    /// - IVs: always from the appraisal bars.
    /// - species: the appraisal **caption** is canonical — it carries the true
    ///   species even for renamed Pokemon, whereas the info screen's "species" is
    ///   really the title/nickname. So the caption overrides; any differing info
    ///   title is preserved in `nickname`.
    /// - CP / catch date / location: the info screen is authoritative; appraisal
    ///   only fills what the info screen left blank.
    /// - confidence: minimum across the info record, the IV read, and any
    ///   appraisal field relied on. When CP is entirely unreadable the record is
    ///   capped so it falls below the review threshold (manual entry needed).
    func merge(info: PokemonRecord?, appraisal: AppraisalResult, appraisalTimestamp: Double) -> PokemonRecord {
        var record = info ?? PokemonRecord()
        record.attackIV = appraisal.attackIV?.value
        record.defenseIV = appraisal.defenseIV?.value
        record.staminaIV = appraisal.staminaIV?.value
        record.appraisalFrameTimestamp = appraisalTimestamp

        var confidences: [Double] = [appraisal.overallConfidence]
        if info != nil { confidences.append(record.confidence) }

        // Species: caption is canonical; displaced info title becomes the nickname.
        if let species = appraisal.species {
            if let infoTitle = record.species, infoTitle != species.value, record.nickname == nil {
                record.nickname = infoTitle
            }
            record.species = species.value
            confidences.append(species.confidence)
        }

        // CP / date / location: fill only where the info screen left a gap.
        if record.cp == nil, let cp = appraisal.cp {
            record.cp = cp.value
            confidences.append(cp.confidence)
        }
        if record.catchDate == nil { record.catchDate = appraisal.catchDate?.value }
        if record.catchLocation == nil { record.catchLocation = appraisal.catchLocation?.value }

        var confidence = confidences.min() ?? 0
        if record.cp == nil { confidence = min(confidence, Self.unverifiedCPConfidence) }
        record.confidence = confidence
        return record
    }
}
