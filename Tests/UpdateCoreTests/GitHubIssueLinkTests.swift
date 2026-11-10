import XCTest
@testable import UpdateCore

final class GitHubIssueLinkTests: XCTestCase {
    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testPointsAtTheRepositorysNewIssuePage() {
        let url = GitHubIssueLink.newIssue(repository: "Owner/Repo", title: "Bug: ", body: "x")
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "github.com")
        XCTAssertEqual(url?.path, "/Owner/Repo/issues/new")
    }

    func testTitleBodyAndLabelsRoundTrip() throws {
        let body = "### What happened?\n\nIt moved & then 50% + more #3 / ? = fine — ✓\n"
        let url = try XCTUnwrap(GitHubIssueLink.newIssue(repository: "Owner/Repo", title: "Bug: a+b",
                                                        body: body, labels: ["bug", "needs triage"]))
        let q = query(url)
        XCTAssertEqual(q["title"], "Bug: a+b")
        XCTAssertEqual(q["body"], body)
        XCTAssertEqual(q["labels"], "bug,needs triage")
    }

    func testPlusIsEncodedSoItIsNotReadAsASpace() throws {
        // A query string's "+" means a space to most servers, GitHub's
        // included; a literal plus must travel as %2B.
        let url = try XCTUnwrap(GitHubIssueLink.newIssue(repository: "O/R", title: "C++", body: "a+b"))
        XCTAssertFalse(url.absoluteString.contains("+"))
        XCTAssertTrue(url.absoluteString.contains("%2B"))
    }

    func testNoLabelsLeavesTheParameterOut() throws {
        let url = try XCTUnwrap(GitHubIssueLink.newIssue(repository: "O/R", title: "t", body: "b"))
        XCTAssertNil(query(url)["labels"])
    }
}
