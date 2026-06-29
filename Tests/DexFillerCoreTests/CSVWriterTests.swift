import Foundation
import Testing
@testable import DexFillerCore

@Suite("CSVWriter Tests")
struct CSVWriterTests {
    @Test("Format CSV with header and rows")
    func formatCSV() {
        let writer = CSVWriter()

        var r1 = PokemonRecord()
        r1.species = "Pikachu"
        r1.cp = 1234
        r1.confidence = 0.95

        var r2 = PokemonRecord()
        r2.species = "Bulbasaur"
        r2.cp = 500
        r2.confidence = 0.60

        let csv = writer.formatCSV([r1, r2])
        let lines = csv.split(separator: "\n")

        #expect(lines.count == 3) // header + 2 rows
        #expect(lines[0].hasPrefix("species,"))
        #expect(lines[1].contains("Pikachu"))
        #expect(lines[2].contains("Bulbasaur"))
    }

    @Test("Flagged for review identifies low confidence records")
    func flaggedForReview() {
        let writer = CSVWriter(reviewThreshold: 0.7)

        var high = PokemonRecord()
        high.confidence = 0.95

        var low = PokemonRecord()
        low.confidence = 0.5

        let flagged = writer.flaggedForReview([high, low])
        #expect(flagged.count == 1)
        #expect(flagged[0].confidence == 0.5)
    }

    @Test("Summary statistics are correct")
    func summary() {
        let writer = CSVWriter()

        var r1 = PokemonRecord()
        r1.attackIV = 15
        r1.defenseIV = 14
        r1.staminaIV = 13
        r1.fastMove = "Thunder Shock"
        r1.confidence = 0.9

        var r2 = PokemonRecord()
        r2.fastMove = "Vine Whip"
        r2.confidence = 0.8

        let stats = writer.summary([r1, r2])
        #expect(stats.totalRecords == 2)
        #expect(stats.recordsWithIVs == 1)
        #expect(stats.recordsWithMoves == 2)
        #expect(abs(stats.averageConfidence - 0.85) < 0.001)
    }

    @Test("Write CSV to file")
    func writeToFile() throws {
        let writer = CSVWriter()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_export.csv")

        var record = PokemonRecord()
        record.species = "Charmander"
        record.cp = 789
        record.confidence = 0.88

        try writer.write([record], to: tempURL)

        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(contents.contains("species,"))
        #expect(contents.contains("Charmander"))

        try? FileManager.default.removeItem(at: tempURL)
    }
}
