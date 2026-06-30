import Testing
@testable import GoDexCore

@Suite("StardustLevelTable Tests")
struct StardustLevelTableTests {
    @Test("Known stardust costs map to correct levels")
    func knownCosts() {
        #expect(StardustLevelTable.level(forStardustCost: 200) == 1)
        #expect(StardustLevelTable.level(forStardustCost: 400) == 3)
        #expect(StardustLevelTable.level(forStardustCost: 1000) == 9)
        #expect(StardustLevelTable.level(forStardustCost: 5000) == 29)
        #expect(StardustLevelTable.level(forStardustCost: 10000) == 39)
        #expect(StardustLevelTable.level(forStardustCost: 16000) == 51)
    }

    @Test("Invalid stardust cost returns nil")
    func invalidCost() {
        #expect(StardustLevelTable.level(forStardustCost: 0) == nil)
        #expect(StardustLevelTable.level(forStardustCost: 123) == nil)
        #expect(StardustLevelTable.level(forStardustCost: 999) == nil)
        #expect(StardustLevelTable.level(forStardustCost: 20000) == nil)
    }

    @Test("All costs are sorted ascending")
    func costsAreSorted() {
        let costs = StardustLevelTable.allCosts
        #expect(costs == costs.sorted())
        #expect(costs.first == 200)
        #expect(costs.last == 16000)
    }
}
