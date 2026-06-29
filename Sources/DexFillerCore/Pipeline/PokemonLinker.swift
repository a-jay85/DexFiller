import Foundation

/// Links appraisal data with the preceding info screen data
/// to produce complete PokemonRecord objects.
///
/// The expected flow in a Pokemon GO recording is:
/// Info Screen → Appraisal Overlay → Info Screen → Appraisal Overlay → ...
/// Each appraisal is linked to the most recent preceding info screen.
public final class PokemonLinker: Sendable {

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

                if var record = lastInfoRecord {
                    // Merge appraisal data into the info record
                    record.attackIV = appraisalResult.attackIV?.value
                    record.defenseIV = appraisalResult.defenseIV?.value
                    record.staminaIV = appraisalResult.staminaIV?.value
                    record.appraisalFrameTimestamp = group.bestFrame.timestamp

                    // Update confidence to include appraisal confidence
                    let appraisalConfidence = appraisalResult.overallConfidence
                    record.confidence = min(record.confidence, appraisalConfidence)

                    records.append(record)
                    lastInfoRecord = nil // Consumed
                } else {
                    // Appraisal without preceding info screen — create partial record
                    var record = PokemonRecord()
                    record.attackIV = appraisalResult.attackIV?.value
                    record.defenseIV = appraisalResult.defenseIV?.value
                    record.staminaIV = appraisalResult.staminaIV?.value
                    record.appraisalFrameTimestamp = group.bestFrame.timestamp
                    record.confidence = appraisalResult.overallConfidence * 0.5 // Lower confidence
                    records.append(record)
                }

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
}
