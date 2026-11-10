import Foundation

/// Decides whether a fetched release should be offered, and when the next
/// automatic check is due. Pure, so the rules are unit-tested; the networking
/// and alerts live in the app target's `UpdateChecker`.
public enum UpdatePolicy {
    /// One automatic check per day is plenty for a small utility, and keeps
    /// well inside GitHub's 60-requests-per-hour unauthenticated limit.
    public static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    public enum Verdict: Equatable {
        case upToDate
        case available(AppVersion)
        /// Newer, but the user chose Skip This Version for exactly this one.
        case skipped(AppVersion)
        /// Draft, pre-release, or a tag that is not a version number.
        case ignored
    }

    public static func evaluate(_ release: GitHubRelease,
                                current: AppVersion,
                                skippedVersion: String?) -> Verdict {
        guard !release.isDraft, !release.isPrerelease,
              let latest = release.version else { return .ignored }
        guard current < latest else { return .upToDate }
        if let skipped = skippedVersion.flatMap(AppVersion.init), skipped == latest {
            return .skipped(latest)
        }
        return .available(latest)
    }

    public static func isAutomaticCheckDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        // A clock set backwards would otherwise postpone checks indefinitely.
        if lastCheck > now { return true }
        return now.timeIntervalSince(lastCheck) >= automaticCheckInterval
    }

    /// Whether this launch is the first of a different version. A nil
    /// `lastRun` is a fresh install; a nil `current` is a `swift run` build.
    public static func isFirstLaunchOfNewVersion(lastRun: String?, current: String?) -> Bool {
        guard let lastRun, let current else { return false }
        return lastRun != current
    }
}
