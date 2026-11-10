import Foundation

/// The fields DeskStop reads from GitHub's "latest release" API response
/// (`GET /repos/{owner}/{repo}/releases/latest`).
public struct GitHubRelease: Decodable, Equatable {
    public struct Asset: Decodable, Equatable {
        public let name: String
        public let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }

        public init(name: String, downloadURL: URL) {
            self.name = name
            self.downloadURL = downloadURL
        }
    }

    public let tagName: String
    public let pageURL: URL
    public let notes: String?
    public let isDraft: Bool
    public let isPrerelease: Bool
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
        case notes = "body"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
        case assets
    }

    public init(tagName: String, pageURL: URL, notes: String? = nil,
                isDraft: Bool = false, isPrerelease: Bool = false, assets: [Asset] = []) {
        self.tagName = tagName
        self.pageURL = pageURL
        self.notes = notes
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.assets = assets
    }

    public var version: AppVersion? { AppVersion(tagName) }

    /// The packaged app the release workflow attaches (`DeskStop-1.2.0.zip`),
    /// or nil when the release has none — the caller then opens `pageURL`.
    public var appDownloadURL: URL? {
        assets.first { $0.name.hasPrefix("DeskStop") && $0.name.hasSuffix(".zip") }?.downloadURL
    }
}
