import XCTest
@testable import UnifiedAudioControl

/// Tests for `SemanticVersion`, the pure value type behind `UpdateManager`'s
/// "is the GitHub release newer than the running app?" decision. Parsing is the
/// risky half: a tag that mis-parses instead of failing produces a confidently
/// wrong update prompt (or silently withholds a real update).
final class SemanticVersionTests: XCTestCase {

    // MARK: - Parsing

    func testParsesThreeComponentVersion() {
        let version = SemanticVersion(string: "1.2.3")
        XCTAssertEqual(version?.major, 1)
        XCTAssertEqual(version?.minor, 2)
        XCTAssertEqual(version?.patch, 3)
    }

    func testParsesTwoComponentVersionWithZeroPatch() {
        let version = SemanticVersion(string: "2.5")
        XCTAssertEqual(version?.major, 2)
        XCTAssertEqual(version?.minor, 5)
        XCTAssertEqual(version?.patch, 0)
    }

    func testStripsLeadingVPrefix() {
        XCTAssertEqual(SemanticVersion(string: "v1.0.4"), SemanticVersion(string: "1.0.4"))
    }

    func testRejectsNonNumericComponentInsteadOfDroppingIt() {
        // Regression: `compactMap { Int($0) }` dropped "x" and parsed this as 1.2.0.
        XCTAssertNil(SemanticVersion(string: "1.x.2"))
        XCTAssertNil(SemanticVersion(string: "2024.beta.5"))
    }

    func testRejectsMalformedStrings() {
        XCTAssertNil(SemanticVersion(string: ""))
        XCTAssertNil(SemanticVersion(string: "1"))
        XCTAssertNil(SemanticVersion(string: "latest"))
        XCTAssertNil(SemanticVersion(string: "1.2.3.4"))
        XCTAssertNil(SemanticVersion(string: "1..3"))
    }

    // MARK: - Pre-release / build suffixes

    func testPreReleaseSuffixParsesToItsNumericCore() {
        // Regression: "1.0.0-beta" split to ["1", "0", "0-beta"]; the unparseable
        // third component was dropped, yielding 1.0.0 by accident rather than by rule.
        let beta = SemanticVersion(string: "1.0.0-beta")
        XCTAssertEqual(beta, SemanticVersion(string: "1.0.0"))
    }

    func testPreReleaseIsNotNewerThanTheMatchingStableRelease() {
        let beta = SemanticVersion(string: "v1.1.0-beta.2")!
        let stable = SemanticVersion(string: "1.1.0")!
        XCTAssertFalse(beta > stable, "a pre-release must not be offered as an upgrade over its own stable version")
    }

    func testBuildMetadataSuffixIsIgnored() {
        XCTAssertEqual(SemanticVersion(string: "1.0.4+20240131"), SemanticVersion(string: "1.0.4"))
    }

    // MARK: - Ordering

    func testOrderingAcrossEachComponent() {
        XCTAssertTrue(SemanticVersion(string: "2.0.0")! > SemanticVersion(string: "1.9.9")!)
        XCTAssertTrue(SemanticVersion(string: "1.3.0")! > SemanticVersion(string: "1.2.9")!)
        XCTAssertTrue(SemanticVersion(string: "1.2.4")! > SemanticVersion(string: "1.2.3")!)
    }

    func testEqualVersionsAreNotNewer() {
        let a = SemanticVersion(string: "1.0.4")!
        let b = SemanticVersion(string: "v1.0.4")!
        XCTAssertEqual(a, b)
        XCTAssertFalse(a > b)
    }

    func testDoubleDigitComponentsCompareNumericallyNotLexically() {
        // "1.10.0" < "1.9.0" under a plain string compare; it must not be here.
        XCTAssertTrue(SemanticVersion(string: "1.10.0")! > SemanticVersion(string: "1.9.0")!)
    }

    func testDescriptionAlwaysRendersThreeComponents() {
        XCTAssertEqual(SemanticVersion(string: "2.5")?.description, "2.5.0")
    }
}
