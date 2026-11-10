import Foundation

/// A link to GitHub's new-issue page with the title, body and labels filled
/// in, for Settings → Feedback. Nothing is sent: the browser opens the page
/// and the person submits it themselves.
public enum GitHubIssueLink {
    /// `repository` is "owner/name". Nil only if the pieces can't form a URL.
    public static func newIssue(repository: String, title: String, body: String,
                                labels: [String] = []) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repository)/issues/new"
        var items = [("title", title), ("body", body)]
        if !labels.isEmpty { items.append(("labels", labels.joined(separator: ","))) }
        // Encoded by hand: URLQueryItem leaves "+" alone, and in a query
        // string "+" reads as a space, so "C++" would arrive as "C  ".
        components.percentEncodedQuery = items
            .map { "\($0.0)=\(encode($0.1))" }
            .joined(separator: "&")
        return components.url
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
