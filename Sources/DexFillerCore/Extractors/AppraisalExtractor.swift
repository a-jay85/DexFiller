import CoreGraphics
import Foundation

/// Extracts IV values from Pokemon GO appraisal screen frames.
///
/// Reads the three horizontal stat bars (Attack, Defense, HP/Stamina) directly
/// from pixels. Each bar is split into three segments worth 5 IV points each
/// (15 max). The fill of each segment is measured independently and rounded to
/// the nearest 0–5, which sidesteps the non-linearity introduced by the gaps
/// between segments. A fully-maxed (15) bar renders salmon-red rather than
/// orange, which is used as a clean anchor for that value.
///
/// Geometry constants below are calibrated against 1170×2532 screenshots
/// (iPhone 13/14/15 non-Pro) and validated to read all values 0–15 across a
/// 281-screenshot baseline with zero ambiguous reads. They are expressed as
/// fractions of the image dimensions so they scale proportionally, but only the
/// 1170×2532 instantiation has been empirically validated (Phase 0 gate).
public final class AppraisalExtractor: Sendable {

    public init() {}

    // MARK: - Calibration (fractions of image width / height @ 1170×2532)

    /// Horizontal extent of the bar track, as fractions of image width.
    private static let barLeftFrac = 139.0 / 1170.0
    private static let barRightFrac = 543.0 / 1170.0

    /// Per-segment x-ranges (start, end) as fractions of image width.
    /// Three segments of 5 IV each, with small gaps between them.
    private static let segmentFracs: [(lo: Double, hi: Double)] = [
        (139.0 / 1170.0, 269.0 / 1170.0),
        (276.0 / 1170.0, 405.0 / 1170.0),
        (411.0 / 1170.0, 543.0 / 1170.0),
    ]

    /// Vertical window (top, bottom) to search for the bar band, as fractions
    /// of image height. The appraisal panel is anchored low-left.
    private static let rowSearchTopFrac = 1820.0 / 2532.0
    private static let rowSearchBottomFrac = 2300.0 / 2532.0

    /// A row counts as "on the bar band" when this fraction of the track width
    /// is occupied by track pixels (filled or empty-gray).
    private static let bandCoverageThreshold = 0.55

    /// Minimum band height in pixels (a bar is ~16px tall @ 2532).
    private static let minBandHeightFrac = 6.0 / 2532.0

    // MARK: - Public API

    /// Extract IV values (from the stat bars) plus CP and species/date/location
    /// (via OCR) from an appraisal screen frame. The appraisal screen is
    /// self-sufficient for everything except moves, which live on the info screen.
    public func extract(from frame: FrameImage) async throws -> AppraisalResult {
        // Text fields come from OCR over the whole frame; the bars come from pixels.
        let textBlocks = (try? await TextRecognizer.recognize(in: frame.cgImage)) ?? []
        let cp = extractCP(from: textBlocks)
        let caught = extractCaughtLine(from: textBlocks)

        guard let pixels = RGBABuffer(frame.cgImage) else {
            return AppraisalResult(
                attackIV: nil, defenseIV: nil, staminaIV: nil,
                cp: cp, species: caught?.species, catchDate: caught?.date, catchLocation: caught?.location
            )
        }

        let bands = findBarBands(pixels)
        guard bands.count == 3 else {
            // Not three clean bars — likely not an expanded appraisal panel.
            return AppraisalResult(
                attackIV: nil, defenseIV: nil, staminaIV: nil,
                cp: cp, species: caught?.species, catchDate: caught?.date, catchLocation: caught?.location
            )
        }

        // Bands are sorted top→bottom = Attack, Defense, HP(stamina).
        let attack = decodeBar(pixels, rowY: bands[0])
        let defense = decodeBar(pixels, rowY: bands[1])
        let stamina = decodeBar(pixels, rowY: bands[2])

        return AppraisalResult(
            attackIV: attack, defenseIV: defense, staminaIV: stamina,
            cp: cp, species: caught?.species, catchDate: caught?.date, catchLocation: caught?.location
        )
    }

    // MARK: - Text Extraction (CP, species, catch date/location)

    /// Plausible CP range for a Pokemon. Vision can return a confident misread on
    /// the stylized CP digits over a busy background, so we reject out-of-range
    /// values rather than trust them.
    private static let cpRange = 10...6000

    /// CP is shown top-center as "CP444"/"cp 444". Restrict to the top of the
    /// screen (Vision origin is bottom-left, so top = high Y) to avoid matching
    /// stray digits elsewhere.
    ///
    /// A clean Latin "CP" prefix is required: when the arc/sprite crosses the
    /// digits Vision injects noise ("CP9.23") that we can safely strip, but when
    /// it garbles the prefix itself (Cyrillic "Р", "฿", or no prefix) a digit is
    /// usually lost too — yielding a plausible but wrong CP. Those are left
    /// unread so the record drops below threshold and is flagged for manual
    /// entry, rather than emitting a confident-wrong value.
    private func extractCP(from blocks: [RecognizedTextBlock]) -> FieldResult<Int>? {
        for block in blocks where block.boundingBox.midY > 0.85 {
            let text = block.text.uppercased().replacingOccurrences(of: " ", with: "")
            guard text.hasPrefix("CP") else { continue }
            let digits = text.dropFirst(2).filter(\.isNumber)
            if let value = Int(digits), Self.cpRange.contains(value) {
                return FieldResult(value: value, confidence: block.confidence)
            }
        }
        return nil
    }

    /// The appraisal screen's bottom caption reads
    /// "This <species> was caught on <date> around <location>." — and always uses
    /// the true species, even when the Pokemon has been renamed (the title shows
    /// the nickname; this line does not). It yields species, catch date, and
    /// location. Vision may split it across blocks, so we match over the joined
    /// text; the caption can also wrap and have its tail cut off the bottom of a
    /// single frame, so species is captured independently of date/location.
    private func extractCaughtLine(
        from blocks: [RecognizedTextBlock]
    ) -> (species: FieldResult<String>, date: FieldResult<String>?, location: FieldResult<String>?)? {
        // Only the lower portion of the screen carries this caption.
        let lower = blocks.filter { $0.boundingBox.midY < 0.25 }
        guard !lower.isEmpty else { return nil }

        let joined = lower.map(\.text).joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
        let captionConfidence = lower.map(\.confidence).min() ?? 0

        // Species: lenient — only needs "This <species> was caught" to be present,
        // so a caption whose date/location line is cut off still yields a species.
        guard let name = firstGroup(in: joined, pattern: #"This\s+(.+?)\s+was\s+caught"#),
              !name.isEmpty else {
            return nil
        }
        let species = FieldResult(value: name, confidence: captionConfidence)

        // Date and location are best-effort from whatever of the line is present.
        let date = firstGroup(in: joined, pattern: #"caught\s+on\s+([\d/.-]+)"#)
            .map { FieldResult(value: $0, confidence: captionConfidence) }
        let location = firstGroup(in: joined, pattern: #"(?:around|in)\s+(.+?)\.\s*$"#)
            .map { FieldResult(value: $0, confidence: captionConfidence) }

        return (species, date, location)
    }

    /// First capture group of `pattern` (case-insensitive) in `text`, trimmed.
    private func firstGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        let value = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - Bar Band Detection

    /// Locate the three stat-bar rows by scanning the search window for
    /// horizontal bands where the track (filled or empty-gray) spans the bar.
    /// Returns the center Y of each band, sorted top→bottom.
    private func findBarBands(_ p: RGBABuffer) -> [Int] {
        let xl = Int(Self.barLeftFrac * Double(p.width))
        let xr = Int(Self.barRightFrac * Double(p.width))
        let yTop = Int(Self.rowSearchTopFrac * Double(p.height))
        let yBot = min(Int(Self.rowSearchBottomFrac * Double(p.height)), p.height)
        guard xr > xl, yBot > yTop else { return [] }

        let trackWidth = xr - xl
        let coverageThreshold = Int(Self.bandCoverageThreshold * Double(trackWidth))
        let minBandHeight = max(3, Int(Self.minBandHeightFrac * Double(p.height)))

        // Mark each row as "on band" if enough track pixels span the bar x-range.
        var onBand = [Bool](repeating: false, count: yBot - yTop)
        for y in yTop..<yBot {
            var count = 0
            for x in xl..<xr where p.isTrack(x, y) { count += 1 }
            onBand[y - yTop] = count > coverageThreshold
        }

        // Collect contiguous runs tall enough to be a bar.
        var runs: [(lo: Int, hi: Int)] = []
        var start: Int? = nil
        for (i, on) in onBand.enumerated() {
            if on, start == nil { start = i }
            if !on, let s = start { runs.append((s, i - 1)); start = nil }
        }
        if let s = start { runs.append((s, onBand.count - 1)) }
        runs = runs.filter { $0.hi - $0.lo >= minBandHeight }

        // Keep the three tallest runs, then order them top→bottom.
        let tallest = runs.sorted { ($0.hi - $0.lo) > ($1.hi - $1.lo) }.prefix(3)
        return tallest
            .map { yTop + ($0.lo + $0.hi) / 2 }
            .sorted()
    }

    // MARK: - Bar Decoding

    /// Decode a single bar at the given row into a 0–15 IV value.
    private func decodeBar(_ p: RGBABuffer, rowY: Int) -> FieldResult<Int> {
        let xl = Int(Self.barLeftFrac * Double(p.width))
        let xr = Int(Self.barRightFrac * Double(p.width))

        // A maxed (15) bar renders salmon-red across the whole track.
        var redCount = 0
        for x in xl..<xr where p.isRed(x, rowY) { redCount += 1 }
        if redCount > (xr - xl) / 4 {
            return FieldResult(value: 15, confidence: 1.0)
        }

        // Otherwise measure each segment's fill fraction independently.
        var iv = 0
        var maxResidual = 0.0
        for seg in Self.segmentFracs {
            let s0 = Int(seg.lo * Double(p.width))
            let s1 = Int(seg.hi * Double(p.width))
            let frac = segmentFillFraction(p, rowY: rowY, x0: s0, x1: s1)
            let scaled = frac * 5.0
            let rounded = (scaled).rounded()
            iv += Int(rounded)
            maxResidual = max(maxResidual, abs(scaled - rounded))
        }
        iv = min(iv, 15)

        // Confidence: 1.0 when every segment sits exactly on a 1/5 boundary,
        // dropping toward 0 as a segment approaches a half-step (ambiguous).
        let confidence = max(0.0, 1.0 - 2.0 * maxResidual)
        return FieldResult(value: iv, confidence: confidence)
    }

    /// Fraction of a segment that is filled, measured by the rightmost filled
    /// pixel (fill is always left-anchored within the segment).
    private func segmentFillFraction(_ p: RGBABuffer, rowY: Int, x0: Int, x1: Int) -> Double {
        guard x1 > x0 else { return 0 }
        var lastFilled = -1
        for x in x0...x1 where p.isFilled(x, rowY) { lastFilled = x }
        if lastFilled < 0 { return 0 }
        return Double(lastFilled - x0 + 1) / Double(x1 - x0 + 1)
    }
}

// MARK: - Pixel Buffer

/// A flattened RGBA8 view of a CGImage with predictable byte layout, produced by
/// drawing the image into a fresh sRGB context. Classifies bar pixels by the
/// rules validated against the baseline screenshots.
struct RGBABuffer {
    let width: Int
    let height: Int
    private let bytes: [UInt8]
    private let bytesPerRow: Int

    init?(_ cgImage: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        let success = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }

        self.width = width
        self.height = height
        self.bytes = buffer
        self.bytesPerRow = bytesPerRow
    }

    /// RGB at a pixel. Returns (0,0,0) out of bounds.
    @inline(__always)
    private func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        guard x >= 0, x < width, y >= 0, y < height else { return (0, 0, 0) }
        let o = y * bytesPerRow + x * 4
        return (Int(bytes[o]), Int(bytes[o + 1]), Int(bytes[o + 2]))
    }

    /// A colored (filled) bar pixel: bright and saturated. Catches both orange
    /// (~244,166,76) and salmon-red (~224,126,132); excludes empty-gray track
    /// (~225,225,225) and the cream panel background (~235,230,195).
    @inline(__always)
    func isFilled(_ x: Int, _ y: Int) -> Bool {
        let (r, g, b) = rgb(x, y)
        let sat = max(r, g, b) - min(r, g, b)
        return r > 195 && sat > 55
    }

    /// A salmon-red (maxed, IV 15) pixel — a filled pixel with high blue
    /// (~132) versus orange's low blue (~76).
    @inline(__always)
    func isRed(_ x: Int, _ y: Int) -> Bool {
        let (_, _, b) = rgb(x, y)
        return isFilled(x, y) && b > 100
    }

    /// Empty-gray bar track (~225,225,225): bright and near-neutral.
    @inline(__always)
    func isGray(_ x: Int, _ y: Int) -> Bool {
        let (r, g, b) = rgb(x, y)
        return r > 205 && r < 245
            && abs(r - b) < 16 && abs(r - g) < 16 && abs(g - b) < 16
    }

    /// Either filled or empty-gray track — i.e. part of the bar, not background.
    @inline(__always)
    func isTrack(_ x: Int, _ y: Int) -> Bool {
        isFilled(x, y) || isGray(x, y)
    }
}

// MARK: - Supporting Types

public struct AppraisalResult: Sendable {
    public let attackIV: FieldResult<Int>?
    public let defenseIV: FieldResult<Int>?
    public let staminaIV: FieldResult<Int>?

    /// CP read from the top of the screen (nil if obscured/unreadable).
    public let cp: FieldResult<Int>?
    /// Display name from the "This … was caught on …" caption. Equals the species
    /// for un-renamed Pokemon; holds the nickname if the Pokemon was renamed.
    public let species: FieldResult<String>?
    public let catchDate: FieldResult<String>?
    public let catchLocation: FieldResult<String>?

    public init(
        attackIV: FieldResult<Int>?,
        defenseIV: FieldResult<Int>?,
        staminaIV: FieldResult<Int>?,
        cp: FieldResult<Int>? = nil,
        species: FieldResult<String>? = nil,
        catchDate: FieldResult<String>? = nil,
        catchLocation: FieldResult<String>? = nil
    ) {
        self.attackIV = attackIV
        self.defenseIV = defenseIV
        self.staminaIV = staminaIV
        self.cp = cp
        self.species = species
        self.catchDate = catchDate
        self.catchLocation = catchLocation
    }

    /// Confidence of the IV bar read only — the validated Phase 0 signal. Kept
    /// separate from CP/species so OCR confidence never perturbs the IV path.
    public var overallConfidence: Double {
        let confidences = [attackIV?.confidence, defenseIV?.confidence, staminaIV?.confidence].compactMap { $0 }
        return confidences.min() ?? 0
    }
}
