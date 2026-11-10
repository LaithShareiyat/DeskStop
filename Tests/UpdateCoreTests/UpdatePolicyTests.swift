import XCTest
@testable import UpdateCore

final class UpdatePolicyTests: XCTestCase {
    private let page = URL(string: "https://github.com/LaithShareiyat/DeskStop/releases/tag/v1.2.0")!

    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) -> GitHubRelease {
        GitHubRelease(tagName: tag, pageURL: page, isDraft: draft, isPrerelease: prerelease)
    }

    func testNewerReleaseIsAvailable() {
        let verdict = UpdatePolicy.evaluate(release("v1.2.0"), current: AppVersion("1.1.0")!,
                                            skippedVersion: nil)
        XCTAssertEqual(verdict, .available(AppVersion("1.2.0")!))
    }

    func testSameOrOlderIsUpToDate() {
        XCTAssertEqual(UpdatePolicy.evaluate(release("v1.2.0"), current: AppVersion("1.2.0")!,
                                             skippedVersion: nil), .upToDate)
        XCTAssertEqual(UpdatePolicy.evaluate(release("v1.2"), current: AppVersion("1.2.0")!,
                                             skippedVersion: nil), .upToDate)
        XCTAssertEqual(UpdatePolicy.evaluate(release("v1.1.0"), current: AppVersion("1.2.0")!,
                                             skippedVersion: nil), .upToDate)
    }

    func testSkippedVersionIsNotOfferedButANewerOneIs() {
        XCTAssertEqual(UpdatePolicy.evaluate(release("v1.2.0"), current: AppVersion("1.1.0")!,
                                             skippedVersion: "1.2.0"),
                       .skipped(AppVersion("1.2.0")!))
        XCTAssertEqual(UpdatePolicy.evaluate(release("v1.3.0"), current: AppVersion("1.1.0")!,
                                             skippedVersion: "1.2.0"),
                       .available(AppVersion("1.3.0")!))
    }

    func testDraftsPrereleasesAndOddTagsAreIgnored() {
        let current = AppVersion("1.0.0")!
        XCTAssertEqual(UpdatePolicy.evaluate(release("v2.0.0", draft: true), current: current,
                                             skippedVersion: nil), .ignored)
        XCTAssertEqual(UpdatePolicy.evaluate(release("v2.0.0", prerelease: true), current: current,
                                             skippedVersion: nil), .ignored)
        XCTAssertEqual(UpdatePolicy.evaluate(release("nightly"), current: current,
                                             skippedVersion: nil), .ignored)
    }

    func testAutomaticCheckCadence() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(UpdatePolicy.isAutomaticCheckDue(lastCheck: nil, now: now))
        XCTAssertFalse(UpdatePolicy.isAutomaticCheckDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(UpdatePolicy.isAutomaticCheckDue(lastCheck: now.addingTimeInterval(-86_400), now: now))
        // Clock moved backwards past the last check.
        XCTAssertTrue(UpdatePolicy.isAutomaticCheckDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }

    func testDecodesGitHubResponseAndFindsTheZip() throws {
        let json = """
        {
          "tag_name": "v1.2.0",
          "html_url": "https://github.com/LaithShareiyat/DeskStop/releases/tag/v1.2.0",
          "body": "Fixes.",
          "draft": false,
          "prerelease": false,
          "assets": [
            {"name": "checksums.txt",
             "browser_download_url": "https://github.com/LaithShareiyat/DeskStop/releases/download/v1.2.0/checksums.txt"},
            {"name": "DeskStop-1.2.0.zip",
             "browser_download_url": "https://github.com/LaithShareiyat/DeskStop/releases/download/v1.2.0/DeskStop-1.2.0.zip"}
          ]
        }
        """
        let decoded = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.version, AppVersion("1.2.0"))
        XCTAssertEqual(decoded.notes, "Fixes.")
        XCTAssertEqual(decoded.appDownloadURL?.lastPathComponent, "DeskStop-1.2.0.zip")
    }

    func testDecodesReleaseWithNullBodyAndNoAssets() throws {
        let json = """
        {"tag_name": "v1.0.0", "html_url": "https://example.com/r",
         "body": null, "draft": false, "prerelease": false, "assets": []}
        """
        let decoded = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        XCTAssertNil(decoded.notes)
        XCTAssertNil(decoded.appDownloadURL)
    }

    func testFirstLaunchOfNewVersion() {
        XCTAssertTrue(UpdatePolicy.isFirstLaunchOfNewVersion(lastRun: "1.1.0", current: "1.2.0"))
        XCTAssertFalse(UpdatePolicy.isFirstLaunchOfNewVersion(lastRun: "1.2.0", current: "1.2.0"))
        // A fresh install, and a `swift run` build with no version.
        XCTAssertFalse(UpdatePolicy.isFirstLaunchOfNewVersion(lastRun: nil, current: "1.2.0"))
        XCTAssertFalse(UpdatePolicy.isFirstLaunchOfNewVersion(lastRun: "1.2.0", current: nil))
    }
}
