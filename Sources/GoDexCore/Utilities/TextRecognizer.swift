import CoreGraphics
import Foundation
import Vision

/// Shared Vision text recognition. Returns recognized text blocks with their
/// confidence and normalized bounding boxes (Vision convention: origin bottom-left).
enum TextRecognizer {
    static func recognize(in cgImage: CGImage) async throws -> [RecognizedTextBlock] {
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
