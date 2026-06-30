import GoDexCore
import Foundation

// MARK: - Output helpers

/// Progress and diagnostics go to stderr; CSV/summary to stdout — keeps piping clean.
func err(_ message: String, terminator: String = "\n") {
    FileHandle.standardError.write((message + terminator).data(using: .utf8)!)
}

func fail(_ message: String) -> Never {
    err("error: \(message)")
    exit(1)
}

// MARK: - Argument parsing

let usage = """
godex — extract Pokemon GO data from a screen-recording video

USAGE:
    godex <video> [options]

ARGUMENTS:
    <video>                 Path to the input video (.mov/.mp4).

OPTIONS:
    -o, --output <path>     CSV output path (default: <video> with .csv extension).
    --sample-rate <fps>     Frames sampled per second (default: 2.0).
    --review-threshold <r>  Confidence below which rows are flagged (default: 0.7).
    --max-gap <seconds>     Max gap between frames in one group (default: 2.0).
    -q, --quiet             Suppress per-phase progress on stderr.
    -h, --help              Show this help.
"""

var positional: [String] = []
var outputPath: String?
var sampleRate = 2.0
var reviewThreshold = 0.7
var maxGap = 2.0
var quiet = false

func parseDouble(_ raw: String?, _ flag: String) -> Double {
    guard let raw, let value = Double(raw) else { fail("\(flag) requires a number") }
    return value
}

var args = Array(CommandLine.arguments.dropFirst()).makeIterator()
while let arg = args.next() {
    switch arg {
    case "-h", "--help":
        print(usage)
        exit(0)
    case "-o", "--output":
        guard let value = args.next() else { fail("\(arg) requires a path") }
        outputPath = value
    case "--sample-rate":
        sampleRate = parseDouble(args.next(), arg)
    case "--review-threshold":
        reviewThreshold = parseDouble(args.next(), arg)
    case "--max-gap":
        maxGap = parseDouble(args.next(), arg)
    case "-q", "--quiet":
        quiet = true
    default:
        if arg.hasPrefix("-") { fail("unknown option: \(arg)") }
        positional.append(arg)
    }
}

guard positional.count == 1 else {
    err(usage)
    exit(positional.isEmpty ? 1 : 1)
}

let videoURL = URL(fileURLWithPath: positional[0])
guard FileManager.default.fileExists(atPath: videoURL.path) else {
    fail("input video not found: \(videoURL.path)")
}

let outputURL = outputPath.map { URL(fileURLWithPath: $0) }
    ?? videoURL.deletingPathExtension().appendingPathExtension("csv")

// MARK: - Run

let pipeline = ProcessingPipeline(
    sampleRate: sampleRate,
    reviewThreshold: reviewThreshold,
    maxGroupGap: maxGap
)

// @Sendable, print-only — no captured mutable state (Swift 6 strict concurrency).
let onProgress: @Sendable (ProcessingProgress) -> Void = { [quiet] progress in
    guard !quiet else { return }
    switch progress {
    case .sampling(let done, let total):
        err("\r[sampling]  \(done)/\(total) frames        ", terminator: "")
    case .grouping:
        err("\r[grouping]                                 ")
    case .extracting(let done, let total):
        err("\r[extracting] \(done)/\(total) pokemon       ", terminator: "")
    case .deduplicating:
        err("\r[deduplicating]                            ")
    case .complete:
        err("\r[complete]                                 ")
    }
}

do {
    err("Processing \(videoURL.lastPathComponent) → \(outputURL.lastPathComponent)")
    let result = try await pipeline.processAndExport(
        videoURL: videoURL,
        outputURL: outputURL,
        onProgress: onProgress
    )

    let s = result.summary
    err("")
    err("Done in \(String(format: "%.1f", result.processingTime))s")
    err("  frames analyzed:     \(result.framesAnalyzed)")
    err("  info screens:        \(result.infoScreensFound)")
    err("  appraisal screens:   \(result.appraisalScreensFound)")
    err("  duplicates removed:  \(result.duplicatesRemoved)")
    err("  records written:     \(s.totalRecords)")
    err("    with IVs:          \(s.recordsWithIVs)")
    err("    with moves:        \(s.recordsWithMoves)")
    err("    flagged for review:\(s.flaggedForReview)")
    err("  avg confidence:      \(String(format: "%.0f%%", s.averageConfidence * 100))")
    err("CSV → \(outputURL.path)")
} catch {
    fail(error.localizedDescription)
}
