import CoreGraphics
import Foundation
import Vision

/// Extracts IV values from Pokemon GO appraisal screen frames.
/// Analyzes the three horizontal bars (Attack, Defense, Stamina) to determine 0–15 values.
public final class AppraisalExtractor: Sendable {

    public init() {}

    /// Extract IV values from an appraisal screen frame.
    public func extract(from frame: FrameImage) async throws -> AppraisalResult {
        let textBlocks = try await recognizeText(in: frame.cgImage)

        // Find the appraisal bar regions by locating the stat labels
        let barRegions = findBarRegions(textBlocks: textBlocks, imageSize: (frame.width, frame.height))

        var attackIV: FieldResult<Int>?
        var defenseIV: FieldResult<Int>?
        var staminaIV: FieldResult<Int>?

        for region in barRegions {
            let ivValue = analyzeBar(
                in: frame.cgImage,
                barRegion: region.barRect,
                imageSize: (frame.width, frame.height)
            )

            switch region.stat {
            case .attack:
                attackIV = ivValue
            case .defense:
                defenseIV = ivValue
            case .stamina:
                staminaIV = ivValue
            }
        }

        return AppraisalResult(
            attackIV: attackIV,
            defenseIV: defenseIV,
            staminaIV: staminaIV
        )
    }

    // MARK: - Bar Region Detection

    private func findBarRegions(textBlocks: [RecognizedTextBlock], imageSize: (Int, Int)) -> [StatBarRegion] {
        var regions: [StatBarRegion] = []

        for block in textBlocks {
            let text = block.text.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let stat: StatType?

            if text == "ATTACK" || text.contains("ATTACK") {
                stat = .attack
            } else if text == "DEFENSE" || text.contains("DEFENSE") {
                stat = .defense
            } else if text == "HP" && block.boundingBox.midY < 0.6 {
                // HP label in the appraisal context (not the top HP bar)
                stat = .stamina
            } else {
                continue
            }

            guard let statType = stat else { continue }

            // The bar is typically to the right of or below the label
            // In Pokemon GO's appraisal, bars appear directly below each label
            // The bar extends from roughly the left edge of the label to the right side of the screen
            let barRect = CGRect(
                x: block.boundingBox.minX,
                y: block.boundingBox.minY - 0.04, // Bar is just below the label (Vision coords: lower Y = lower on screen)
                width: 0.6, // Bars span roughly 60% of screen width
                height: 0.025 // Bars are thin horizontal elements
            )

            regions.append(StatBarRegion(stat: statType, labelBox: block.boundingBox, barRect: barRect))
        }

        return regions
    }

    // MARK: - Bar Analysis

    /// Analyze a horizontal bar to determine its fill level (0–15).
    /// The bar consists of filled segments against a background.
    private func analyzeBar(in cgImage: CGImage, barRegion: CGRect, imageSize: (Int, Int)) -> FieldResult<Int>? {
        // Convert normalized coordinates to pixel coordinates
        let pixelRect = CGRect(
            x: barRegion.origin.x * CGFloat(imageSize.0),
            y: (1.0 - barRegion.origin.y - barRegion.height) * CGFloat(imageSize.1), // Flip Y for CGImage
            width: barRegion.width * CGFloat(imageSize.0),
            height: barRegion.height * CGFloat(imageSize.1)
        )

        // Clamp to image bounds
        let clampedRect = pixelRect.intersection(CGRect(x: 0, y: 0, width: imageSize.0, height: imageSize.1))
        guard !clampedRect.isEmpty,
              clampedRect.width > 10,
              clampedRect.height > 2 else {
            return nil
        }

        // Crop the bar region
        guard let cropped = cgImage.cropping(to: clampedRect),
              let data = cropped.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return nil
        }

        let width = cropped.width
        let height = cropped.height
        let bytesPerPixel = cropped.bitsPerPixel / 8
        let bytesPerRow = cropped.bytesPerRow

        // Sample the middle row of the bar
        let midY = height / 2

        // Collect the red/saturation channel along the bar's width
        // Filled portions of IV bars in Pokemon GO are colored (orange/red),
        // while unfilled portions are gray/dark
        var brightness: [Double] = []
        for x in 0..<width {
            let offset = midY * bytesPerRow + x * bytesPerPixel
            let r = Double(ptr[offset])
            let g = Double(ptr[offset + 1])
            let b = Double(ptr[offset + 2])
            // Use saturation as indicator: filled bars are more saturated
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            brightness.append(saturation)
        }

        guard !brightness.isEmpty else { return nil }

        // Find the transition point where the bar goes from filled to unfilled
        // Use a threshold-based approach
        let threshold = 0.15 // Saturation threshold between filled and unfilled

        var filledPixels = 0
        for value in brightness {
            if value > threshold {
                filledPixels += 1
            }
        }

        let fillRatio = Double(filledPixels) / Double(width)

        // Map fill ratio to 0–15
        // Each IV point = 1/15th of the bar
        let ivValue = Int(round(fillRatio * 15.0))
        let clampedIV = max(0, min(15, ivValue))

        // Confidence based on how cleanly the ratio maps to a discrete value
        let exactRatio = Double(clampedIV) / 15.0
        let deviation = abs(fillRatio - exactRatio)
        let confidence = max(0, 1.0 - deviation * 15.0) // Lower confidence if between discrete values

        return FieldResult(value: clampedIV, confidence: confidence)
    }

    // MARK: - Text Recognition

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

public struct AppraisalResult: Sendable {
    public let attackIV: FieldResult<Int>?
    public let defenseIV: FieldResult<Int>?
    public let staminaIV: FieldResult<Int>?

    public var overallConfidence: Double {
        let confidences = [attackIV?.confidence, defenseIV?.confidence, staminaIV?.confidence].compactMap { $0 }
        return confidences.min() ?? 0
    }
}

enum StatType {
    case attack
    case defense
    case stamina
}

struct StatBarRegion {
    let stat: StatType
    let labelBox: CGRect
    let barRect: CGRect
}
