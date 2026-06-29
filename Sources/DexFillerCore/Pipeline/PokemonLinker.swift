import Foundation

/// Links appraisal data with the adjacent info-screen data to produce complete
/// PokemonRecord objects.
///
/// A Pokemon GO recording shows each Pokemon as an info screen and an appraisal
/// overlay, but the capture can be in either order (info→appraisal when tapping
/// "Appraise", or appraisal→info when backing out). So an appraisal is paired
/// with a *temporally adjacent* info screen on either side; a second screen of
/// the same kind flushes the unpaired one rather than letting it reach across to
/// a different Pokemon.
public final class PokemonLinker: Sendable {

    /// Confidence cap applied when CP could not be read, so the record drops
    /// below the default review threshold and is surfaced for manual entry.
    private static let unverifiedCPConfidence = 0.4

    public init() {}

    /// Link frame groups into complete Pokemon records.
    /// Groups should be in chronological order.
    public func link(groups: [FrameGroup], infoExtractor: InfoScreenExtractor, appraisalExtractor: AppraisalExtractor) async throws -> [PokemonRecord] {
        var records: [PokemonRecord] = []
        var pendingInfo: PokemonRecord?
        var pendingAppraisal: (result: AppraisalResult, timestamp: Double)?

        for group in groups {
            switch group.screenType {
            case .infoScreen:
                var info = try await infoExtractor.extract(from: group.bestFrame.image).record
                info.infoFrameTimestamp = group.bestFrame.timestamp
                if let appraisal = pendingAppraisal {
                    // Appraisal immediately preceded this info — same Pokemon.
                    records.append(merge(info: info, appraisal: appraisal.result, appraisalTimestamp: appraisal.timestamp))
                    pendingAppraisal = nil
                } else {
                    if let prev = pendingInfo { records.append(partial(prev)) }
                    pendingInfo = info
                }

            case .appraisalOverlay:
                let result = try await appraisalExtractor.extract(from: group.bestFrame.image)
                let timestamp = group.bestFrame.timestamp
                if let info = pendingInfo {
                    records.append(merge(info: info, appraisal: result, appraisalTimestamp: timestamp))
                    pendingInfo = nil
                } else {
                    if let prev = pendingAppraisal {
                        records.append(merge(info: nil, appraisal: prev.result, appraisalTimestamp: prev.timestamp))
                    }
                    pendingAppraisal = (result, timestamp)
                }

            case .other:
                continue
            }
        }

        // Flush any unpaired trailing screen.
        if let info = pendingInfo { records.append(partial(info)) }
        if let appraisal = pendingAppraisal {
            records.append(merge(info: nil, appraisal: appraisal.result, appraisalTimestamp: appraisal.timestamp))
        }

        return records
    }

    /// Whether a string looks like a Pokemon name/nickname rather than misread
    /// chrome (a clock "16:36", a bare number). Requires at least one letter and
    /// rejects a leading time pattern.
    private static func isNameLike(_ text: String) -> Bool {
        guard text.contains(where: \.isLetter) else { return false }
        return text.range(of: #"^\s*\d{1,2}:\d{2}"#, options: .regularExpression) == nil
    }

    /// An info screen with no appraisal to pair with: lower confidence and no IVs.
    private func partial(_ info: PokemonRecord) -> PokemonRecord {
        var record = info
        record.confidence *= 0.7
        return record
    }

    /// Combine an appraisal read with the preceding info-screen record (if any)
    /// into one `PokemonRecord`. Pure and `internal` so the merge rules can be
    /// unit-tested without synthesizing frames.
    ///
    /// Field provenance. The appraisal screen is the *validated* source (281
    /// fixtures); the info-screen extractor uses loose positional heuristics that
    /// misfire on real video (e.g. the status-bar clock read as the species). So
    /// every field the appraisal carries wins; the info screen only fills gaps.
    /// - IVs: always from the appraisal bars.
    /// - species: from the appraisal **caption** — the true species even for
    ///   renamed Pokemon (the info "species" is really the title/nickname). Any
    ///   differing info title is preserved in `nickname`.
    /// - catch date / location: from the appraisal caption only. The info
    ///   extractor's versions are unreliable ("STARDUST" read as location), so an
    ///   empty field beats filling it with garbage.
    /// - CP: info fills only when appraisal couldn't read it (both sources read
    ///   the same top-center number reliably; info covers the obscured-CP case).
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

        // Species: caption is canonical; a displaced *name-like* info title is
        // kept as the nickname (the info "species" is often garbage like a clock).
        if let species = appraisal.species {
            if let infoTitle = record.species, infoTitle != species.value,
               record.nickname == nil, Self.isNameLike(infoTitle) {
                record.nickname = infoTitle
            }
            record.species = species.value
            confidences.append(species.confidence)
        }

        // Catch date / location: appraisal caption only (info versions unreliable).
        record.catchDate = appraisal.catchDate?.value
        record.catchLocation = appraisal.catchLocation?.value

        // CP: info is kept; appraisal only fills the obscured-CP gap.
        if record.cp == nil, let cp = appraisal.cp {
            record.cp = cp.value
            confidences.append(cp.confidence)
        }

        var confidence = confidences.min() ?? 0
        if record.cp == nil { confidence = min(confidence, Self.unverifiedCPConfidence) }
        record.confidence = confidence
        return record
    }
}
