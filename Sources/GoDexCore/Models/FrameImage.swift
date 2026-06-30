import CoreGraphics
import Foundation

/// Wrapper around CGImage that conforms to Sendable for safe passing between tasks.
/// CGImage is thread-safe for read-only access.
public struct FrameImage: @unchecked Sendable {
    public let cgImage: CGImage
    public let width: Int
    public let height: Int

    public init(_ cgImage: CGImage) {
        self.cgImage = cgImage
        self.width = cgImage.width
        self.height = cgImage.height
    }
}
