import Foundation

/// Maps stardust power-up cost to Pokemon level.
/// Source: well-documented community data (e.g., Silph Road, PokeGenie).
/// Each stardust cost corresponds to a range of half-levels.
public enum StardustLevelTable {
    /// Returns the Pokemon level for a given stardust power-up cost.
    /// Pokemon GO uses half-levels (1, 1.5, 2, 2.5, ..., 50, 50.5, 51).
    /// The stardust cost corresponds to the base level of that cost tier.
    /// Returns nil if the cost doesn't match any known tier.
    public static func level(forStardustCost stardust: Int) -> Double? {
        return stardustToLevel[stardust]
    }

    /// Returns all possible stardust costs (sorted ascending).
    public static var allCosts: [Int] {
        return stardustToLevel.keys.sorted()
    }

    // Stardust cost → base level of that tier
    // Each cost covers 2 half-levels (e.g., 200 → levels 1 and 1.5)
    // We return the lower level; caller can refine with CP curve if needed.
    private static let stardustToLevel: [Int: Double] = [
        200: 1,
        400: 3,
        600: 5,
        800: 7,
        1000: 9,
        1300: 11,
        1600: 13,
        1900: 15,
        2200: 17,
        2500: 19,
        3000: 21,
        3500: 23,
        4000: 25,
        4500: 27,
        5000: 29,
        6000: 31,
        7000: 33,
        8000: 35,
        9000: 37,
        10000: 39,
        11000: 41,
        12000: 43,
        13000: 45,
        14000: 47,
        15000: 49,
        16000: 51,
    ]
}
