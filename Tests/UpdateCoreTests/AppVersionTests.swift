import XCTest
@testable import UpdateCore

final class AppVersionTests: XCTestCase {
    private func v(_ s: String) -> AppVersion { AppVersion(s)! }

    func testParsesPlainAndTaggedVersions() {
        XCTAssertEqual(v("1.2.3").components, [1, 2, 3])
        XCTAssertEqual(v("v1.2.3").components, [1, 2, 3])
        XCTAssertEqual(v(" V2.0 ").components, [2, 0])
        XCTAssertEqual(v("1.5.0-beta.2").prerelease, "beta.2")
    }

    func testRejectsNonVersions() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("v"))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("1.x"))
    }

    func testNumericNotLexicalOrdering() {
        XCTAssertLessThan(v("1.9.0"), v("1.10.0"))
        XCTAssertLessThan(v("0.1.0"), v("1.0.0"))
        XCTAssertGreaterThan(v("2.0"), v("1.99.99"))
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(v("1.2"), v("1.2.0"))
        XCTAssertFalse(v("1.2") < v("1.2.0"))
        XCTAssertLessThan(v("1.2"), v("1.2.1"))
    }

    func testPrereleaseSortsBeforeItsRelease() {
        XCTAssertLessThan(v("1.5.0-beta.1"), v("1.5.0"))
        XCTAssertLessThan(v("1.5.0-beta.2"), v("1.5.0-beta.10"))
        XCTAssertGreaterThan(v("1.5.0-beta.1"), v("1.4.9"))
        XCTAssertNotEqual(v("1.5.0-beta.1"), v("1.5.0"))
    }

    func testDescription() {
        XCTAssertEqual(v("v1.2.3").description, "1.2.3")
        XCTAssertEqual(v("1.5.0-rc.1").description, "1.5.0-rc.1")
    }
}
