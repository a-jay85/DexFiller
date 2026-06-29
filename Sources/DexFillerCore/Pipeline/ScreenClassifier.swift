import CoreGraphics
import Foundation
import Vision

/// Classifies Pokemon GO frames as info screens, appraisal overlays, or other.
/// Uses Vision framework OCR to detect characteristic text patterns.
public final class ScreenClassifier: Sendable {

    public init() {}

    /// Classify a single frame by analyzing its text content.
    public func classify(_ frame: FrameImage) async throws -> (ScreenType, Double) {
        let recognizedText = try await recognizeText(in: frame.cgImage)

        // Check for appraisal screen indicators first (more specific)
        let appraisalResult = checkAppraisalScreen(recognizedText)
        if appraisalResult.confidence > 0.7 {
            return (.appraisalOverlay, appraisalResult.confidence)
        }

        // Check for info screen indicators
        let infoResult = checkInfoScreen(recognizedText)
        if infoResult.confidence > 0.6 {
            return (.infoScreen, infoResult.confidence)
        }

        return (.other, 1.0 - max(appraisalResult.confidence, infoResult.confidence))
    }

    /// Classify a frame and wrap it in a ClassifiedFrame.
    public func classifyFrame(image: FrameImage, timestamp: Double) async throws -> ClassifiedFrame {
        let (screenType, confidence) = try await classify(image)
        return ClassifiedFrame(
            image: image,
            timestamp: timestamp,
            screenType: screenType,
            classificationConfidence: confidence
        )
    }

    // MARK: - Private

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

    private func checkAppraisalScreen(_ textBlocks: [RecognizedTextBlock]) -> (isAppraisal: Bool, confidence: Double) {
        let allText = textBlocks.map { $0.text.uppercased() }.joined(separator: " ")
        var score: Double = 0

        // Appraisal screen has stat labels
        let appraisalKeywords = ["ATTACK", "DEFENSE", "HP"]
        for keyword in appraisalKeywords {
            if allText.contains(keyword) {
                score += 0.25
            }
        }

        // The appraisal screen shows star ratings or bar indicators
        // and often has text like "Overall" or team leader dialogue
        if allText.contains("OVERALL") {
            score += 0.15
        }

        // Appraisal screens also show CP at the top
        if allText.contains("CP") {
            score += 0.1
        }

        return (score > 0.5, min(score, 1.0))
    }

    private func checkInfoScreen(_ textBlocks: [RecognizedTextBlock]) -> (isInfo: Bool, confidence: Double) {
        let allText = textBlocks.map { $0.text.uppercased() }.joined(separator: " ")
        var score: Double = 0

        // Info screen always shows CP prominently
        if allText.contains("CP") {
            score += 0.2
        }

        // HP indicator
        if allText.contains("HP") {
            score += 0.15
        }

        // Type label(s) — Pokemon types
        let types = ["NORMAL", "FIRE", "WATER", "GRASS", "ELECTRIC", "ICE", "FIGHTING",
                     "POISON", "GROUND", "FLYING", "PSYCHIC", "BUG", "ROCK", "GHOST",
                     "DRAGON", "DARK", "STEEL", "FAIRY"]
        for type in types {
            if allText.contains(type) {
                score += 0.15
                break
            }
        }

        // Weight/Height indicators
        if allText.contains("WEIGHT") || allText.contains("KG") {
            score += 0.1
        }
        if allText.contains("HEIGHT") || allText.contains("M") {
            score += 0.1
        }

        // Stardust / Power Up
        if allText.contains("POWER UP") || allText.contains("STARDUST") {
            score += 0.15
        }

        // Move names are typically present
        if allText.contains("EVOLVE") || allText.contains("POWER") {
            score += 0.1
        }

        return (score > 0.4, min(score, 1.0))
    }
}

public struct RecognizedTextBlock: Sendable {
    public let text: String
    public let confidence: Double
    /// Normalized bounding box (0–1 range, origin at bottom-left per Vision convention)
    public let boundingBox: CGRect

    public init(text: String, confidence: Double, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}
