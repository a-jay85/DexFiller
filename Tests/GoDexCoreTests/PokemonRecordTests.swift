import Testing
@testable import GoDexCore

@Suite("PokemonRecord Tests")
struct PokemonRecordTests {
    @Test("CSV header has correct columns")
    func csvHeader() {
        let header = PokemonRecord.csvHeader
        let columns = header.split(separator: ",")
        #expect(columns.count == 21)
        #expect(columns[0] == "species")
        #expect(columns[20] == "confidence")
    }

    @Test("CSV row formats all fields correctly")
    func csvRowComplete() {
        var record = PokemonRecord()
        record.species = "Pikachu"
        record.nickname = "Sparky"
        record.cp = 1234
        record.hp = 89
        record.level = 25.0
        record.attackIV = 15
        record.defenseIV = 12
        record.staminaIV = 14
        record.fastMove = "Thunder Shock"
        record.chargedMove1 = "Thunderbolt"
        record.chargedMove2 = "Wild Charge"
        record.catchDate = "7/20/2024"
        record.catchLocation = "New York, NY"
        record.weight = 6.04
        record.height = 0.41
        record.shiny = true
        record.lucky = false
        record.shadow = false
        record.purified = false
        record.confidence = 0.95

        let row = record.csvRow
        let fields = parseCSVRow(row)

        #expect(fields[0] == "Pikachu")
        #expect(fields[1] == "Sparky")
        #expect(fields[2] == "1234")
        #expect(fields[3] == "89")
        #expect(fields[4] == "25.0")
        #expect(fields[5] == "15")
        #expect(fields[6] == "12")
        #expect(fields[7] == "14")
        // IV% = (15 + 12 + 14) / 45 * 100 = 91.1%
        #expect(fields[8] == "91.1")
        #expect(fields[9] == "Thunder Shock")
        #expect(fields[10] == "Thunderbolt")
        #expect(fields[11] == "Wild Charge")
        #expect(fields[12] == "7/20/2024")
        // Location with comma should be quoted
        #expect(fields[13] == "New York, NY")
        #expect(fields[16] == "true") // shiny
        #expect(fields[17] == "false") // lucky
    }

    @Test("CSV row handles missing fields")
    func csvRowPartial() {
        var record = PokemonRecord()
        record.species = "Bulbasaur"
        record.cp = 500

        let row = record.csvRow
        #expect(row.contains("Bulbasaur"))
        #expect(row.contains("500"))
    }

    @Test("IV percentage calculation")
    func ivPercentage() {
        var record = PokemonRecord()
        record.attackIV = 15
        record.defenseIV = 15
        record.staminaIV = 15
        #expect(record.ivPercentage == 1.0)

        var zeroRecord = PokemonRecord()
        zeroRecord.attackIV = 0
        zeroRecord.defenseIV = 0
        zeroRecord.staminaIV = 0
        #expect(zeroRecord.ivPercentage == 0.0)

        let noIVRecord = PokemonRecord()
        #expect(noIVRecord.ivPercentage == nil)
    }

    @Test("CSV escapes commas in fields")
    func csvEscaping() {
        var record = PokemonRecord()
        record.catchLocation = "San Francisco, CA"
        let row = record.csvRow
        #expect(row.contains("\"San Francisco, CA\""))
    }

    /// Simple CSV row parser for testing (handles quoted fields)
    private func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var chars = row.makeIterator()

        while let char = chars.next() {
            if char == "\"" {
                if inQuotes {
                    // Check for escaped quote
                    inQuotes = false
                } else {
                    inQuotes = true
                }
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
}
