import Foundation

/// The type of Pokemon GO screen detected in a frame.
public enum ScreenType: Sendable {
    /// The Pokemon info/summary screen showing species, CP, HP, moves, etc.
    case infoScreen
    /// The appraisal overlay showing IV bars
    case appraisalOverlay
    /// A transition frame, menu, or unrecognized screen (skip)
    case other
}

/// A sampled frame with its classification.
public struct ClassifiedFrame: Sendable {
    public let image: FrameImage
    public let timestamp: Double
    public let screenType: ScreenType
    public let classificationConfidence: Double

    public init(image: FrameImage, timestamp: Double, screenType: ScreenType, classificationConfidence: Double) {
        self.image = image
        self.timestamp = timestamp
        self.screenType = screenType
        self.classificationConfidence = classificationConfidence
    }
}

/// A group of consecutive frames of the same screen type for the same Pokemon.
public struct FrameGroup: Sendable {
    public let screenType: ScreenType
    public let frames: [ClassifiedFrame]
    /// The sharpest frame in the group (highest Laplacian variance).
    public let bestFrame: ClassifiedFrame

    public init(screenType: ScreenType, frames: [ClassifiedFrame], bestFrame: ClassifiedFrame) {
        self.screenType = screenType
        self.frames = frames
        self.bestFrame = bestFrame
    }
}
