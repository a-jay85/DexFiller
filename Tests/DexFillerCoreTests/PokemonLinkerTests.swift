import XCTest
@testable import DexFillerCore

/// Unit tests for `PokemonLinker.merge` — the pure rules that combine an
/// appraisal read with the preceding info-screen record. Exercises the
/// info+appraisal path that the fixture-based tests (appraisal-only) never hit.
final class PokemonLinkerTests: XCTestCase {
    private let linker = PokemonLinker()

    private func appraisal(
        atk: Int? = 10, def: Int? = 10, sta: Int? = 10,
        cp: Int? = 500, species: String? = "Pikachu",
        date: String? = "6/20/2026", location: String? = "San Francisco, CA",
        conf: Double = 1.0
    ) -> AppraisalResult {
        AppraisalResult(
            attackIV: atk.map { FieldResult(value: $0, confidence: conf) },
            defenseIV: def.map { FieldResult(value: $0, confidence: conf) },
            staminaIV: sta.map { FieldResult(value: $0, confidence: conf) },
            cp: cp.map { FieldResult(value: $0, confidence: conf) },
            species: species.map { FieldResult(value: $0, confidence: conf) },
            catchDate: date.map { FieldResult(value: $0, confidence: conf) },
            catchLocation: location.map { FieldResult(value: $0, confidence: conf) }
        )
    }

    func testAppraisalOnlyPopulatesAllFields() {
        let r = linker.merge(info: nil, appraisal: appraisal(), appraisalTimestamp: 1.0)
        XCTAssertEqual(r.species, "Pikachu")
        XCTAssertEqual(r.cp, 500)
        XCTAssertEqual(r.attackIV, 10)
        XCTAssertEqual(r.catchLocation, "San Francisco, CA")
        XCTAssertNil(r.nickname)
        XCTAssertGreaterThan(r.confidence, 0.9)
    }

    func testUnreadableCPFlagsForReview() {
        let r = linker.merge(info: nil, appraisal: appraisal(cp: nil), appraisalTimestamp: 1.0)
        XCTAssertNil(r.cp)
        XCTAssertLessThanOrEqual(r.confidence, 0.4, "missing CP must drop below review threshold")
    }

    func testCaptionSpeciesOverridesNicknameTitle() {
        // Info screen read the title, which is the player's nickname.
        var info = PokemonRecord()
        info.species = "Pvp UK91"   // nickname grabbed from the title
        info.cp = 671
        info.confidence = 0.95

        let r = linker.merge(info: info, appraisal: appraisal(cp: 671, species: "Scyther"), appraisalTimestamp: 2.0)
        XCTAssertEqual(r.species, "Scyther", "caption species is canonical")
        XCTAssertEqual(r.nickname, "Pvp UK91", "displaced title preserved as nickname")
        XCTAssertEqual(r.cp, 671, "info CP retained")
    }

    func testUnrenamedKeepsNicknameNil() {
        var info = PokemonRecord()
        info.species = "Pikachu"
        info.confidence = 0.95
        let r = linker.merge(info: info, appraisal: appraisal(species: "Pikachu"), appraisalTimestamp: 2.0)
        XCTAssertEqual(r.species, "Pikachu")
        XCTAssertNil(r.nickname, "no rename → no nickname")
    }

    func testAppraisalCaptionWinsDateAndLocation() {
        // Info screen's positional heuristics misread these on real video.
        var info = PokemonRecord()
        info.catchDate = "16:36"            // clock misread
        info.catchLocation = "STARDUST"     // label misread
        info.confidence = 0.9
        let r = linker.merge(
            info: info,
            appraisal: appraisal(date: "6/29/2026", location: "San Francisco, CA"),
            appraisalTimestamp: 2.0
        )
        XCTAssertEqual(r.catchDate, "6/29/2026", "appraisal caption date wins")
        XCTAssertEqual(r.catchLocation, "San Francisco, CA", "appraisal caption location wins")
    }

    func testCatchMetadataComesOnlyFromAppraisal() {
        // Info's date/location heuristics are unreliable; an empty field beats
        // filling it with garbage, so info is never used as a fallback.
        var info = PokemonRecord()
        info.catchDate = "16:36"
        info.catchLocation = "STARDUST"
        info.confidence = 0.9
        let r = linker.merge(info: info, appraisal: appraisal(date: nil, location: nil), appraisalTimestamp: 2.0)
        XCTAssertNil(r.catchDate, "info date discarded when appraisal has none")
        XCTAssertNil(r.catchLocation, "info location discarded when appraisal has none")
    }

    func testGarbageInfoTitleNotRoutedToNickname() {
        var info = PokemonRecord()
        info.species = "16:36"   // status-bar clock misread as species
        info.confidence = 0.9
        let r = linker.merge(info: info, appraisal: appraisal(species: "Squawkabilly"), appraisalTimestamp: 2.0)
        XCTAssertEqual(r.species, "Squawkabilly")
        XCTAssertNil(r.nickname, "non-name-like info title is not kept as nickname")
    }

    func testInfoCPRetainedOverAppraisal() {
        var info = PokemonRecord()
        info.cp = 1234       // authoritative from info screen
        info.confidence = 0.9
        let r = linker.merge(info: info, appraisal: appraisal(cp: 9999), appraisalTimestamp: 2.0)
        XCTAssertEqual(r.cp, 1234, "appraisal only fills CP when info left it blank")
    }
}
