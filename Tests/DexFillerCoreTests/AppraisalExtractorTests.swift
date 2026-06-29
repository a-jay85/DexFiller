import CoreGraphics
import ImageIO
import XCTest
@testable import DexFillerCore

/// Phase 0 regression: runs the IV-bar extractor against the hand-verified
/// baseline screenshots and asserts it reproduces the labels in
/// `fixtures/baseline_labels.csv`.
///
/// The fixtures (personal screenshots) are gitignored, so this test skips
/// cleanly when they are absent — it only runs on a machine that has the
/// baseline checked out locally.
final class AppraisalExtractorTests: XCTestCase {

    /// Repo-root/fixtures, resolved relative to this source file.
    private var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DexFillerCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("fixtures")
    }

    private struct Label {
        let file: String
        let atk: Int
        let def: Int
        let hp: Int
    }

    func testReproducesBaselineLabels() async throws {
        let csvURL = fixturesDir.appendingPathComponent("baseline_labels.csv")
        let imagesDir = fixturesDir.appendingPathComponent("baseline")
        guard FileManager.default.fileExists(atPath: csvURL.path),
              FileManager.default.fileExists(atPath: imagesDir.path) else {
            throw XCTSkip("Baseline fixtures not present; skipping Phase 0 regression.")
        }

        let labels = try parseLabels(csvURL)
        XCTAssertFalse(labels.isEmpty, "Expected labeled rows in baseline CSV")

        let extractor = AppraisalExtractor()
        var checked = 0
        var mismatches: [String] = []

        for label in labels {
            let imageURL = imagesDir.appendingPathComponent(label.file)
            guard let cgImage = loadCGImage(imageURL) else {
                mismatches.append("\(label.file): could not load image")
                continue
            }
            let result = try await extractor.extract(from: FrameImage(cgImage))
            let atk = result.attackIV?.value
            let def = result.defenseIV?.value
            let hp = result.staminaIV?.value
            checked += 1
            if atk != label.atk || def != label.def || hp != label.hp {
                mismatches.append(
                    "\(label.file): got (\(str(atk)),\(str(def)),\(str(hp))) " +
                    "expected (\(label.atk),\(label.def),\(label.hp))"
                )
            }
        }

        let report = mismatches.prefix(20).joined(separator: "\n")
        XCTAssertTrue(
            mismatches.isEmpty,
            "\(mismatches.count)/\(checked) baseline screenshots mismatched:\n\(report)"
        )
    }

    /// Coverage regression for the OCR text fields the appraisal screen carries
    /// on its own (species + CP). The labeled rows are exactly the true appraisal
    /// screens, so every one should yield a species; CP is allowed a small miss
    /// rate because the arc/sprite can cross the digits — those cases must read
    /// `nil` (→ flagged for manual entry) rather than a wrong value.
    func testExtractsSpeciesAndCPFromAppraisal() async throws {
        let csvURL = fixturesDir.appendingPathComponent("baseline_labels.csv")
        let imagesDir = fixturesDir.appendingPathComponent("baseline")
        guard FileManager.default.fileExists(atPath: csvURL.path),
              FileManager.default.fileExists(atPath: imagesDir.path) else {
            throw XCTSkip("Baseline fixtures not present; skipping appraisal OCR regression.")
        }

        let labels = try parseLabels(csvURL)
        XCTAssertFalse(labels.isEmpty)

        let extractor = AppraisalExtractor()
        var checked = 0, speciesRead = 0, cpRead = 0
        for label in labels {
            guard let cgImage = loadCGImage(imagesDir.appendingPathComponent(label.file)) else { continue }
            let result = try await extractor.extract(from: FrameImage(cgImage))
            checked += 1
            if result.species != nil { speciesRead += 1 }
            if result.cp != nil { cpRead += 1 }
        }

        XCTAssertGreaterThan(checked, 0)
        let speciesRate = Double(speciesRead) / Double(checked)
        let cpRate = Double(cpRead) / Double(checked)
        XCTAssertGreaterThanOrEqual(speciesRate, 0.98, "species read on \(speciesRead)/\(checked)")
        XCTAssertGreaterThanOrEqual(cpRate, 0.95, "CP read on \(cpRead)/\(checked)")
    }

    // MARK: - Helpers

    /// Parse labeled rows, skipping NO_PANEL / unlabeled rows.
    private func parseLabels(_ url: URL) throws -> [Label] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var rows = text.split(whereSeparator: \.isNewline).map(String.init)
        guard !rows.isEmpty else { return [] }
        rows.removeFirst() // header
        var labels: [Label] = []
        for row in rows {
            let cols = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 4,
                  let atk = Int(cols[1]), let def = Int(cols[2]), let hp = Int(cols[3]) else {
                continue // NO_PANEL rows have empty IV cells — skip
            }
            labels.append(Label(file: cols[0], atk: atk, def: def, hp: hp))
        }
        return labels
    }

    private func loadCGImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func str(_ value: Int?) -> String { value.map(String.init) ?? "nil" }
}
