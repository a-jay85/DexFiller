import CoreGraphics
import Foundation
import Vision

/// Extracts Pokemon data from info screen frames using Vision OCR.
public final class InfoScreenExtractor: Sendable {

    public init() {}

    /// Extract all available data from a Pokemon info screen frame.
    public func extract(from frame: FrameImage) async throws -> ExtractionResult {
        let textBlocks = try await recognizeText(in: frame.cgImage)
        var record = PokemonRecord()
        var confidences: [Double] = []

        // Extract CP
        if let cpResult = extractCP(from: textBlocks) {
            record.cp = cpResult.value
            confidences.append(cpResult.confidence)
        }

        // Extract species name
        if let speciesResult = extractSpecies(from: textBlocks, imageHeight: frame.height) {
            record.species = speciesResult.value
            confidences.append(speciesResult.confidence)
        }

        // Extract HP
        if let hpResult = extractHP(from: textBlocks) {
            record.hp = hpResult.value
            confidences.append(hpResult.confidence)
        }

        // Extract weight
        if let weightResult = extractWeight(from: textBlocks) {
            record.weight = weightResult.value
            confidences.append(weightResult.confidence)
        }

        // Extract height
        if let heightResult = extractHeight(from: textBlocks) {
            record.height = heightResult.value
            confidences.append(heightResult.confidence)
        }

        // Extract stardust cost → level
        if let stardustResult = extractStardustCost(from: textBlocks) {
            record.stardustCost = stardustResult.value
            record.level = StardustLevelTable.level(forStardustCost: stardustResult.value)
            confidences.append(stardustResult.confidence)
        }

        // Extract moves
        let moves = extractMoves(from: textBlocks)
        if let fastMove = moves.fastMove {
            record.fastMove = fastMove.value
            confidences.append(fastMove.confidence)
        }
        if let charged1 = moves.chargedMove1 {
            record.chargedMove1 = charged1.value
            confidences.append(charged1.confidence)
        }
        if let charged2 = moves.chargedMove2 {
            record.chargedMove2 = charged2.value
            confidences.append(charged2.confidence)
        }

        // Extract catch date and location
        if let dateResult = extractCatchDate(from: textBlocks) {
            record.catchDate = dateResult.value
            confidences.append(dateResult.confidence)
        }
        if let locationResult = extractCatchLocation(from: textBlocks) {
            record.catchLocation = locationResult.value
            confidences.append(locationResult.confidence)
        }

        // Overall confidence = minimum of all field confidences
        record.confidence = confidences.min() ?? 0

        return ExtractionResult(record: record, textBlocks: textBlocks)
    }

    // MARK: - Field Extraction

    /// CP is displayed prominently at the top of the info screen, in format "CP1234" or "CP 1234"
    private func extractCP(from blocks: [RecognizedTextBlock]) -> FieldResult<Int>? {
        for block in blocks {
            let text = block.text.uppercased().replacingOccurrences(of: " ", with: "")
            // Match "CP" followed by digits
            if let range = text.range(of: #"CP(\d+)"#, options: .regularExpression) {
                let match = String(text[range])
                let digits = match.dropFirst(2) // Remove "CP"
                if let value = Int(digits) {
                    return FieldResult(value: value, confidence: block.confidence)
                }
            }
        }
        return nil
    }

    /// Species name is typically near the top of the screen, below CP.
    /// It's the largest text block in the upper portion of the screen.
    private func extractSpecies(from blocks: [RecognizedTextBlock], imageHeight: Int) -> FieldResult<String>? {
        // Filter blocks in the upper 40% of the screen
        // Vision uses bottom-left origin, so upper portion = higher Y values
        let upperBlocks = blocks.filter { $0.boundingBox.midY > 0.55 }

        // Look for species name — it's NOT "CP..." and NOT a number
        for block in upperBlocks {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            if text.uppercased().hasPrefix("CP") { continue }
            if text.allSatisfy({ $0.isNumber || $0 == "," }) { continue }

            // Species names are typically single words or two-word names
            let words = text.split(separator: " ")
            if words.count <= 3 && text.count >= 2 {
                return FieldResult(value: text, confidence: block.confidence)
            }
        }
        return nil
    }

    /// HP is displayed as "HP" followed by current/max, like "123 / 123 HP" or "HP 123 / 123"
    private func extractHP(from blocks: [RecognizedTextBlock]) -> FieldResult<Int>? {
        for block in blocks {
            let text = block.text.uppercased()
            // Pattern: digits / digits HP  or  HP digits / digits
            // We want the max HP (second number)
            if text.contains("HP") {
                let cleaned = text.replacingOccurrences(of: "HP", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Look for "N / N" pattern
                let parts = cleaned.split(separator: "/").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if parts.count == 2, let maxHP = Int(parts[1].filter(\.isNumber)) {
                    return FieldResult(value: maxHP, confidence: block.confidence)
                }
                // Single number (just max HP visible)
                if let hp = Int(cleaned.filter(\.isNumber)), hp > 0 {
                    return FieldResult(value: hp, confidence: block.confidence * 0.8)
                }
            }
        }
        return nil
    }

    /// Weight is displayed as "Weight" label followed by a number in kg.
    private func extractWeight(from blocks: [RecognizedTextBlock]) -> FieldResult<Double>? {
        return extractLabeledNumber(from: blocks, label: "WEIGHT", unit: "KG")
    }

    /// Height is displayed as "Height" label followed by a number in m.
    private func extractHeight(from blocks: [RecognizedTextBlock]) -> FieldResult<Double>? {
        return extractLabeledNumber(from: blocks, label: "HEIGHT", unit: "M")
    }

    /// Stardust cost appears near the "Power Up" button.
    private func extractStardustCost(from blocks: [RecognizedTextBlock]) -> FieldResult<Int>? {
        // Look for a number near "Power Up" or stardust icon
        // Stardust costs are: 200, 400, 600, ..., 16000
        let validCosts = Set(StardustLevelTable.allCosts)

        for (i, block) in blocks.enumerated() {
            let text = block.text.uppercased()
            if text.contains("POWER UP") || text.contains("POWER-UP") {
                // Check nearby blocks for the stardust number
                let searchRange = max(0, i - 3)...min(blocks.count - 1, i + 3)
                for j in searchRange {
                    let numText = blocks[j].text.filter(\.isNumber)
                    if let cost = Int(numText), validCosts.contains(cost) {
                        return FieldResult(value: cost, confidence: blocks[j].confidence)
                    }
                }
            }
        }

        // Fallback: look for any number that matches a valid stardust cost
        for block in blocks {
            let numText = block.text.filter(\.isNumber)
            if let cost = Int(numText), validCosts.contains(cost) {
                // Lower confidence since we didn't confirm context
                return FieldResult(value: cost, confidence: block.confidence * 0.6)
            }
        }
        return nil
    }

    /// Extract fast move and charged moves.
    /// Moves appear in the middle section of the info screen.
    private func extractMoves(from blocks: [RecognizedTextBlock]) -> MoveResult {
        // Moves appear in the middle vertical region of the screen
        let midBlocks = blocks.filter { $0.boundingBox.midY > 0.25 && $0.boundingBox.midY < 0.55 }

        var moveTexts: [(String, Double)] = []
        for block in midBlocks {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Move names are typically multi-character, not just numbers
            if text.count >= 3 && !text.allSatisfy(\.isNumber) {
                // Filter out common non-move text
                let upper = text.uppercased()
                let skipWords = ["WEIGHT", "HEIGHT", "POWER UP", "EVOLVE", "CANDY", "STARDUST",
                               "KG", "NORMAL", "FIRE", "WATER", "GRASS", "ELECTRIC", "ICE",
                               "FIGHTING", "POISON", "GROUND", "FLYING", "PSYCHIC", "BUG",
                               "ROCK", "GHOST", "DRAGON", "DARK", "STEEL", "FAIRY", "HP"]
                if skipWords.contains(where: { upper == $0 }) { continue }
                moveTexts.append((text, block.confidence))
            }
        }

        var result = MoveResult()
        if moveTexts.count >= 1 {
            result.fastMove = FieldResult(value: moveTexts[0].0, confidence: moveTexts[0].1)
        }
        if moveTexts.count >= 2 {
            result.chargedMove1 = FieldResult(value: moveTexts[1].0, confidence: moveTexts[1].1)
        }
        if moveTexts.count >= 3 {
            result.chargedMove2 = FieldResult(value: moveTexts[2].0, confidence: moveTexts[2].1)
        }
        return result
    }

    /// Extract catch date — typically in format "7/20/2024" or similar.
    private func extractCatchDate(from blocks: [RecognizedTextBlock]) -> FieldResult<String>? {
        for block in blocks {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Match date patterns: M/D/YYYY, MM/DD/YYYY, YYYY-MM-DD
            let datePattern = #"\d{1,2}/\d{1,2}/\d{4}|\d{4}-\d{2}-\d{2}"#
            if let range = text.range(of: datePattern, options: .regularExpression) {
                return FieldResult(value: String(text[range]), confidence: block.confidence)
            }
        }
        return nil
    }

    /// Extract catch location — text near the catch date, typically a city/place name.
    private func extractCatchLocation(from blocks: [RecognizedTextBlock]) -> FieldResult<String>? {
        // Location is typically in the lower portion of the info screen
        let lowerBlocks = blocks.filter { $0.boundingBox.midY < 0.3 }

        for block in lowerBlocks {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip numbers-only, short text, and known labels
            if text.count < 3 { continue }
            if text.allSatisfy(\.isNumber) { continue }
            let upper = text.uppercased()
            if upper == "WEIGHT" || upper == "HEIGHT" || upper.hasPrefix("CP") { continue }
            // Location names typically contain letters and maybe commas
            if text.contains(",") || (text.first?.isLetter == true && text.count >= 4) {
                return FieldResult(value: text, confidence: block.confidence)
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func extractLabeledNumber(from blocks: [RecognizedTextBlock], label: String, unit: String) -> FieldResult<Double>? {
        for (i, block) in blocks.enumerated() {
            let text = block.text.uppercased()
            if text.contains(label) {
                // Check same block for number
                let numStr = text.replacingOccurrences(of: label, with: "")
                    .replacingOccurrences(of: unit, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = Double(numStr), value > 0 {
                    return FieldResult(value: value, confidence: block.confidence)
                }

                // Check adjacent blocks for the number
                let searchRange = max(0, i - 2)...min(blocks.count - 1, i + 2)
                for j in searchRange where j != i {
                    let numText = blocks[j].text
                        .replacingOccurrences(of: unit, with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let value = Double(numText), value > 0 {
                        return FieldResult(value: value, confidence: blocks[j].confidence)
                    }
                }
            }
        }
        return nil
    }

    private func recognizeText(in cgImage: CGImage) async throws -> [RecognizedTextBlock] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let results = (request.results ?? []).compactMap { result -> RecognizedTextBlock? in
                    guard let observation = result as? VNRecognizedTextObservation,
                          let candidate = observation.topCandidates(1).first else { return nil }
                    return RecognizedTextBlock(
                        text: candidate.string,
                        confidence: Double(candidate.confidence),
                        boundingBox: observation.boundingBox
                    )
                }
                continuation.resume(returning: results)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Supporting Types

public struct ExtractionResult: Sendable {
    public let record: PokemonRecord
    public let textBlocks: [RecognizedTextBlock]
}

public struct FieldResult<T: Sendable>: Sendable {
    public let value: T
    public let confidence: Double
}

struct MoveResult {
    var fastMove: FieldResult<String>?
    var chargedMove1: FieldResult<String>?
    var chargedMove2: FieldResult<String>?
}
