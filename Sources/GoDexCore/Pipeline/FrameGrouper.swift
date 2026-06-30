import Accelerate
import CoreGraphics
import Foundation

/// Groups consecutive frames of the same screen type and selects the sharpest frame per group.
public final class FrameGrouper: Sendable {
    /// Maximum time gap (seconds) between frames in the same group.
    /// If two frames of the same type are more than this apart, they're separate groups.
    public let maxGapSeconds: Double

    public init(maxGapSeconds: Double = 2.0) {
        self.maxGapSeconds = maxGapSeconds
    }

    /// Group classified frames into FrameGroups, selecting the sharpest frame per group.
    public func group(_ frames: [ClassifiedFrame]) -> [FrameGroup] {
        guard !frames.isEmpty else { return [] }

        var groups: [FrameGroup] = []
        var currentGroupFrames: [ClassifiedFrame] = [frames[0]]
        var currentType = frames[0].screenType

        for i in 1..<frames.count {
            let frame = frames[i]
            let prevFrame = frames[i - 1]
            let timeDelta = frame.timestamp - prevFrame.timestamp
            let sameType = isSameType(frame.screenType, currentType)

            if sameType && timeDelta <= maxGapSeconds {
                currentGroupFrames.append(frame)
            } else {
                // Finalize current group
                if let group = finalizeGroup(currentGroupFrames, type: currentType) {
                    groups.append(group)
                }
                currentGroupFrames = [frame]
                currentType = frame.screenType
            }
        }

        // Finalize last group
        if let group = finalizeGroup(currentGroupFrames, type: currentType) {
            groups.append(group)
        }

        return groups
    }

    // MARK: - Private

    private func isSameType(_ a: ScreenType, _ b: ScreenType) -> Bool {
        switch (a, b) {
        case (.infoScreen, .infoScreen): return true
        case (.appraisalOverlay, .appraisalOverlay): return true
        case (.other, .other): return true
        default: return false
        }
    }

    private func finalizeGroup(_ frames: [ClassifiedFrame], type: ScreenType) -> FrameGroup? {
        guard !frames.isEmpty else { return nil }
        // Skip groups of "other" type — they're transitions
        guard type != .other else { return nil }

        let bestFrame = frames.max(by: { sharpness($0.image) < sharpness($1.image) }) ?? frames[0]

        return FrameGroup(screenType: type, frames: frames, bestFrame: bestFrame)
    }

    /// Estimate image sharpness using Laplacian variance.
    /// Higher values = sharper image.
    private func sharpness(_ image: FrameImage) -> Double {
        let cgImage = image.cgImage
        let width = cgImage.width
        let height = cgImage.height

        // Convert to grayscale pixel buffer
        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return 0
        }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        // Sample a center region to save computation (no need to process full frame)
        let sampleSize = min(200, min(width, height))
        let startX = (width - sampleSize) / 2
        let startY = (height - sampleSize) / 2

        // Convert sampled region to grayscale floats
        var grayscale = [Float](repeating: 0, count: sampleSize * sampleSize)
        for y in 0..<sampleSize {
            for x in 0..<sampleSize {
                let offset = (startY + y) * bytesPerRow + (startX + x) * bytesPerPixel
                // Luminance from RGB (approximate)
                let r = Float(ptr[offset])
                let g = Float(ptr[offset + 1])
                let b = Float(ptr[offset + 2])
                grayscale[y * sampleSize + x] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }

        // Apply 3x3 Laplacian kernel and compute variance
        // Kernel: [0, 1, 0; 1, -4, 1; 0, 1, 0]
        var laplacianValues = [Float](repeating: 0, count: (sampleSize - 2) * (sampleSize - 2))
        var sum: Float = 0
        var count = 0

        for y in 1..<(sampleSize - 1) {
            for x in 1..<(sampleSize - 1) {
                let center = grayscale[y * sampleSize + x]
                let top = grayscale[(y - 1) * sampleSize + x]
                let bottom = grayscale[(y + 1) * sampleSize + x]
                let left = grayscale[y * sampleSize + (x - 1)]
                let right = grayscale[y * sampleSize + (x + 1)]

                let lap = top + bottom + left + right - 4 * center
                laplacianValues[count] = lap
                sum += lap
                count += 1
            }
        }

        guard count > 0 else { return 0 }

        let mean = sum / Float(count)
        var variance: Float = 0
        for i in 0..<count {
            let diff = laplacianValues[i] - mean
            variance += diff * diff
        }
        variance /= Float(count)

        return Double(variance)
    }
}
