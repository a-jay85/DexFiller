import Foundation

/// Orchestrates the full video processing pipeline:
/// Frame Sampler → Screen Classifier → Frame Grouper → Data Extractor → Pokemon Linker → Deduplicator → CSV Writer
public final class ProcessingPipeline: Sendable {
    private let frameSampler: FrameSampler
    private let screenClassifier: ScreenClassifier
    private let frameGrouper: FrameGrouper
    private let infoExtractor: InfoScreenExtractor
    private let appraisalExtractor: AppraisalExtractor
    private let pokemonLinker: PokemonLinker
    private let deduplicator: Deduplicator
    private let csvWriter: CSVWriter

    public init(
        sampleRate: Double = 2.0,
        reviewThreshold: Double = 0.7,
        maxGroupGap: Double = 2.0
    ) {
        self.frameSampler = FrameSampler(sampleRate: sampleRate)
        self.screenClassifier = ScreenClassifier()
        self.frameGrouper = FrameGrouper(maxGapSeconds: maxGroupGap)
        self.infoExtractor = InfoScreenExtractor()
        self.appraisalExtractor = AppraisalExtractor()
        self.pokemonLinker = PokemonLinker()
        self.deduplicator = Deduplicator()
        self.csvWriter = CSVWriter(reviewThreshold: reviewThreshold)
    }

    /// Process a video file and return extracted Pokemon records.
    /// - Parameter onProgress: optional callback invoked on the calling task as work proceeds.
    public func process(
        videoURL: URL,
        onProgress: (@Sendable (ProcessingProgress) -> Void)? = nil
    ) async throws -> ProcessingResult {
        let startTime = Date()
        func reportProgress(_ progress: ProcessingProgress) { onProgress?(progress) }

        // Phase 1: Estimate total frames
        let estimatedTotal = try await frameSampler.estimatedFrameCount(for: videoURL)
        reportProgress(.sampling(framesProcessed: 0, estimatedTotal: estimatedTotal))

        // Phase 2: Sample and classify frames
        var classifiedFrames: [ClassifiedFrame] = []
        var framesProcessed = 0

        for try await (image, timestamp) in frameSampler.sampleFrames(from: videoURL) {
            let classified = try await screenClassifier.classifyFrame(image: image, timestamp: timestamp)
            classifiedFrames.append(classified)

            framesProcessed += 1
            if framesProcessed % 10 == 0 {
                reportProgress(.sampling(framesProcessed: framesProcessed, estimatedTotal: estimatedTotal))
            }
        }

        reportProgress(.sampling(framesProcessed: framesProcessed, estimatedTotal: framesProcessed))

        // Phase 3: Group frames
        reportProgress(.grouping)
        let groups = frameGrouper.group(classifiedFrames)

        let infoGroupCount = groups.filter { $0.screenType == .infoScreen }.count
        let appraisalGroupCount = groups.filter { $0.screenType == .appraisalOverlay }.count

        // Phase 4: Extract and link data
        reportProgress(.extracting(pokemonProcessed: 0, estimatedTotal: max(infoGroupCount, appraisalGroupCount)))
        let records = try await pokemonLinker.link(
            groups: groups,
            infoExtractor: infoExtractor,
            appraisalExtractor: appraisalExtractor
        )

        // Phase 5: Deduplicate
        reportProgress(.deduplicating)
        let deduplicated = deduplicator.deduplicate(records)

        let elapsed = Date().timeIntervalSince(startTime)
        let summary = csvWriter.summary(deduplicated)
        let flagged = csvWriter.flaggedForReview(deduplicated)

        reportProgress(.complete)

        return ProcessingResult(
            records: deduplicated,
            flaggedRecords: flagged,
            summary: summary,
            framesAnalyzed: framesProcessed,
            infoScreensFound: infoGroupCount,
            appraisalScreensFound: appraisalGroupCount,
            duplicatesRemoved: records.count - deduplicated.count,
            processingTime: elapsed
        )
    }

    /// Process a video and export directly to CSV.
    public func processAndExport(
        videoURL: URL,
        outputURL: URL,
        onProgress: (@Sendable (ProcessingProgress) -> Void)? = nil
    ) async throws -> ProcessingResult {
        let result = try await process(videoURL: videoURL, onProgress: onProgress)
        try csvWriter.write(result.records, to: outputURL)
        return result
    }

    /// Export existing records to CSV.
    public func exportCSV(_ records: [PokemonRecord], to url: URL) throws {
        try csvWriter.write(records, to: url)
    }

    /// Format records as CSV string (for preview).
    public func formatCSV(_ records: [PokemonRecord]) -> String {
        return csvWriter.formatCSV(records)
    }
}

// MARK: - Supporting Types

public enum ProcessingProgress: Sendable {
    case sampling(framesProcessed: Int, estimatedTotal: Int)
    case grouping
    case extracting(pokemonProcessed: Int, estimatedTotal: Int)
    case deduplicating
    case complete

    public var phase: String {
        switch self {
        case .sampling: return "Sampling frames"
        case .grouping: return "Grouping frames"
        case .extracting: return "Extracting data"
        case .deduplicating: return "Deduplicating"
        case .complete: return "Complete"
        }
    }

    public var fractionComplete: Double {
        switch self {
        case .sampling(let done, let total):
            guard total > 0 else { return 0 }
            return Double(done) / Double(total) * 0.6 // Sampling is ~60% of work
        case .grouping:
            return 0.65
        case .extracting(let done, let total):
            guard total > 0 else { return 0.7 }
            return 0.65 + Double(done) / Double(total) * 0.25
        case .deduplicating:
            return 0.95
        case .complete:
            return 1.0
        }
    }
}

public struct ProcessingResult: Sendable {
    public let records: [PokemonRecord]
    public let flaggedRecords: [PokemonRecord]
    public let summary: ProcessingSummary
    public let framesAnalyzed: Int
    public let infoScreensFound: Int
    public let appraisalScreensFound: Int
    public let duplicatesRemoved: Int
    public let processingTime: TimeInterval
}
