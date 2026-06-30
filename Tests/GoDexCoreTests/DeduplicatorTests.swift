import Testing
@testable import GoDexCore

@Suite("Deduplicator Tests")
struct DeduplicatorTests {
    @Test("Removes exact duplicates, keeps highest confidence")
    func deduplication() {
        var r1 = PokemonRecord()
        r1.species = "Pikachu"
        r1.cp = 1000
        r1.hp = 80
        r1.weight = 6.0
        r1.confidence = 0.8

        var r2 = PokemonRecord()
        r2.species = "Pikachu"
        r2.cp = 1000
        r2.hp = 80
        r2.weight = 6.0
        r2.confidence = 0.95

        var r3 = PokemonRecord()
        r3.species = "Bulbasaur"
        r3.cp = 500
        r3.hp = 60
        r3.weight = 7.0
        r3.confidence = 0.9

        let deduplicator = Deduplicator()
        let result = deduplicator.deduplicate([r1, r2, r3])

        #expect(result.count == 2)
        // Pikachu should have the higher confidence
        let pikachu = result.first { $0.species == "Pikachu" }
        #expect(pikachu?.confidence == 0.95)
    }

    @Test("Different Pokemon are not deduplicated")
    func differentPokemon() {
        var r1 = PokemonRecord()
        r1.species = "Pikachu"
        r1.cp = 1000
        r1.hp = 80

        var r2 = PokemonRecord()
        r2.species = "Pikachu"
        r2.cp = 1001 // Different CP
        r2.hp = 80

        let deduplicator = Deduplicator()
        let result = deduplicator.deduplicate([r1, r2])

        #expect(result.count == 2)
    }

    @Test("Preserves original order")
    func preservesOrder() {
        var r1 = PokemonRecord()
        r1.species = "Pikachu"
        r1.cp = 100
        r1.hp = 10

        var r2 = PokemonRecord()
        r2.species = "Bulbasaur"
        r2.cp = 200
        r2.hp = 20

        var r3 = PokemonRecord()
        r3.species = "Charmander"
        r3.cp = 300
        r3.hp = 30

        let deduplicator = Deduplicator()
        let result = deduplicator.deduplicate([r1, r2, r3])

        #expect(result.count == 3)
        #expect(result[0].species == "Pikachu")
        #expect(result[1].species == "Bulbasaur")
        #expect(result[2].species == "Charmander")
    }
}
