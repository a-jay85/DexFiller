import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

/// Samples frames from a video file at a configurable rate using AVAssetReader.
/// Streams frames one at a time — never loads the full video into memory.
public final class FrameSampler: Sendable {
    /// Frames per second to sample (default 2.0 = one frame every 0.5s)
    public let sampleRate: Double

    public init(sampleRate: Double = 2.0) {
        self.sampleRate = sampleRate
    }

    /// Sample frames from a video file, yielding (CGImage, timestamp) pairs.
    /// Uses AVAssetReader for streaming — memory-efficient for multi-hour videos.
    public func sampleFrames(from url: URL) -> AsyncThrowingStream<(FrameImage, Double), Error> {
        let sampleInterval = 1.0 / sampleRate

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let asset = AVURLAsset(url: url)
                    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                        continuation.finish(throwing: FrameSamplerError.noVideoTrack)
                        return
                    }

                    let outputSettings: [String: Any] = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]

                    let reader = try AVAssetReader(asset: asset)
                    let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
                    trackOutput.alwaysCopiesSampleData = false
                    reader.add(trackOutput)

                    guard reader.startReading() else {
                        continuation.finish(throwing: FrameSamplerError.readerFailed(reader.error?.localizedDescription ?? "Unknown error"))
                        return
                    }

                    var nextSampleTime: Double = 0
                    var frameCount = 0

                    while reader.status == .reading {
                        // Check for cancellation
                        if Task.isCancelled {
                            reader.cancelReading()
                            continuation.finish()
                            return
                        }

                        guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else {
                            break
                        }

                        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        let timeSeconds = CMTimeGetSeconds(presentationTime)

                        // Skip frames until we reach the next sample point
                        guard timeSeconds >= nextSampleTime else {
                            continue
                        }

                        // Extract CGImage from sample buffer
                        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                            CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
                            defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

                            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                            let context = CIContext()
                            let rect = CGRect(
                                x: 0, y: 0,
                                width: CVPixelBufferGetWidth(imageBuffer),
                                height: CVPixelBufferGetHeight(imageBuffer)
                            )

                            if let cgImage = context.createCGImage(ciImage, from: rect) {
                                let frameImage = FrameImage(cgImage)
                                continuation.yield((frameImage, timeSeconds))
                                frameCount += 1
                            }
                        }

                        nextSampleTime = timeSeconds + sampleInterval
                    }

                    if reader.status == .failed {
                        continuation.finish(throwing: FrameSamplerError.readerFailed(reader.error?.localizedDescription ?? "Unknown error"))
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Get the total duration of a video file in seconds.
    public func videoDuration(for url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    /// Estimate total frames that will be sampled.
    public func estimatedFrameCount(for url: URL) async throws -> Int {
        let duration = try await videoDuration(for: url)
        return Int(duration * sampleRate)
    }
}

public enum FrameSamplerError: Error, LocalizedError {
    case noVideoTrack
    case readerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found in file"
        case .readerFailed(let reason):
            return "Video reader failed: \(reason)"
        }
    }
}
