import AppKit
import UpdateCore

/// Settings → Feedback: bug reports and feature requests, as GitHub issues
/// the person writes and submits in their browser. DeskStop sends nothing.
enum Feedback {
    /// Where updates come from is where reports go.
    static var repository: String { UpdateChecker.repository }

    /// What the reports carry, also shown on the page and copyable: enough
    /// to reproduce a problem, nothing personal.
    static var systemDetails: String {
        let info = Bundle.main.infoDictionary
        let app: String
        if let version = info?["CFBundleShortVersionString"] as? String {
            let build = (info?["CFBundleVersion"] as? String).map { " (\($0))" } ?? ""
            app = "DeskStop \(version)\(build)"
        } else {
            app = "DeskStop development build"
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var macOS = "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        if let build = sysctlString("kern.osversion") { macOS += " (\(build))" }
        let displays = NSScreen.screens.count
        return [app,
                macOS,
                "Mac: \(sysctlString("hw.model") ?? "unknown")",
                "Displays: \(displays) connected"].joined(separator: "\n")
    }

    static var bugReportURL: URL? {
        GitHubIssueLink.newIssue(repository: repository, title: "Bug: ", body: """
            ### What happened?


            ### What did you expect to happen?


            ### Steps to reproduce
            1.
            2.
            3.

            ### System details
            \(systemDetails)
            """, labels: ["bug"])
    }

    static var featureRequestURL: URL? {
        GitHubIssueLink.newIssue(repository: repository, title: "Feature: ", body: """
            ### What would you like DeskStop to do?


            ### How would it help you?


            ### System details
            \(systemDetails)
            """, labels: ["enhancement"])
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
