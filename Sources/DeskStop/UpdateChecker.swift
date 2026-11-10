import AppKit
import UpdateCore

/// Finds new versions on GitHub Releases and installs them in place.
///
/// DeskStop is distributed only through GitHub, so the latest release *is*
/// the update feed: no appcast, no third-party framework. Version rules live
/// in `UpdateCore.UpdatePolicy` (unit-tested); this type does the networking,
/// the alerts and the bundle swap.
///
/// Install path: download the release's `DeskStop-x.y.z.zip`, unpack it with
/// `ditto`, check the unpacked bundle is DeskStop at the advertised version,
/// swap it over the running bundle, relaunch. Anything that goes wrong falls
/// back to opening the release page, so the user can always update by hand.
final class UpdateChecker {
    static let repository = "LaithShareiyat/DeskStop"
    private static let latestReleaseURL =
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    static let releasesPageURL = URL(string: "https://github.com/\(repository)/releases")!

    /// Re-evaluated every few hours so a Mac that never quits still checks
    /// daily; the policy decides whether a check is actually due.
    private var timer: Timer?
    private var isChecking = false

    var currentVersion: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap(AppVersion.init)
    }

    /// For display; `swift run` builds have no bundle version.
    var currentVersionString: String {
        currentVersion?.description ?? "development build"
    }

    func start() {
        remindAboutFinderAfterUpdate()
        checkIfDue()
        let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Menu and Settings entry point: always reports back, including
    /// "you're up to date" and errors.
    func checkNow() {
        check(userInitiated: true)
    }

    private func checkIfDue() {
        let defaults = UserDefaults.standard
        guard defaults.automaticallyCheckForUpdates,
              UpdatePolicy.isAutomaticCheckDue(lastCheck: defaults.lastUpdateCheck, now: Date())
        else { return }
        check(userInitiated: false)
    }

    // MARK: - After an update

    /// Releases are ad-hoc signed, so each version's signature differs. macOS
    /// 15 kept the Finder permission across that when tested, but if it ever
    /// doesn't, nothing else would tell the user, so the first launch of a new
    /// version checks. Dispatched so the alert doesn't hold up the rest of launch.
    private func remindAboutFinderAfterUpdate() {
        let defaults = UserDefaults.standard
        let current = currentVersion?.description
        let updated = UpdatePolicy.isFirstLaunchOfNewVersion(lastRun: defaults.lastRunVersion,
                                                             current: current)
        if let current { defaults.lastRunVersion = current }
        // Onboarding asks for Finder access itself.
        guard updated, defaults.hasCompletedOnboarding else { return }
        DispatchQueue.main.async {
            let permissions = PermissionCenter.shared
            permissions.refresh()
            guard permissions.status(of: .finderAutomation) != .granted else { return }
            let alert = NSAlert()
            alert.messageText = "Allow Finder access again"
            alert.informativeText = "After this update, macOS no longer lets DeskStop control Finder. DeskStop needs that to save and restore icon positions."
            alert.addButton(withTitle: "Allow Finder Access")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                permissions.startOver(.finderAutomation)
            }
        }
    }

    // MARK: - Check

    private func check(userInitiated: Bool) {
        guard !isChecking else { return }
        guard let current = currentVersion else {
            // `swift run` has no bundle, so no version to compare against.
            if userInitiated {
                Alerts.show(title: "Can't check for updates",
                            info: "This copy of DeskStop has no version number. Build it with Scripts/build-app.sh, or download it from GitHub.")
            }
            return
        }
        isChecking = true

        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DeskStop/\(current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                self.handle(data: data, response: response, error: error,
                            current: current, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func handle(data: Data?, response: URLResponse?, error: Error?,
                        current: AppVersion, userInitiated: Bool) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil, status == 200, let data,
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            // 404 means the repository has no published release yet.
            let reason = error?.localizedDescription
                ?? (status == 404 ? "No release has been published yet." : "GitHub returned status \(status).")
            NSLog("DeskStop update check failed: \(reason)")
            if userInitiated {
                Alerts.show(title: "Couldn't check for updates", info: reason, style: .warning)
            }
            return
        }
        UserDefaults.standard.lastUpdateCheck = Date()

        let skipped = userInitiated ? nil : UserDefaults.standard.skippedUpdateVersion
        switch UpdatePolicy.evaluate(release, current: current, skippedVersion: skipped) {
        case .available(let latest):
            offer(release, latest: latest, current: current)
        case .upToDate, .ignored:
            if userInitiated {
                Alerts.show(title: "You're up to date",
                            info: "Version \(current) is the latest.")
            }
        case .skipped:
            break
        }
    }

    // MARK: - Offer

    private func offer(_ release: GitHubRelease, latest: AppVersion, current: AppVersion) {
        let alert = NSAlert()
        alert.messageText = "DeskStop \(latest) is available"
        var info = "You have version \(current)."
        if let notes = release.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            // The alert has no scroll view; long notes belong on the release page.
            info += "\n\n" + (notes.count > 600 ? String(notes.prefix(600)) + "\u{2026}" : notes)
        }
        alert.informativeText = info
        let canInstall = release.appDownloadURL != nil && Self.canReplaceRunningApp
        alert.addButton(withTitle: canInstall ? "Install and Relaunch" : "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if canInstall, let zip = release.appDownloadURL {
                install(from: zip, expecting: latest, fallback: release.pageURL)
            } else {
                NSWorkspace.shared.open(release.pageURL)
            }
        case .alertThirdButtonReturn:
            UserDefaults.standard.skippedUpdateVersion = latest.description
        default:
            break
        }
    }

    // MARK: - Install

    /// In-place install needs a real `.app` whose folder we can write to.
    /// A translocated copy (run straight from Downloads) or a read-only
    /// location gets the manual download instead.
    private static var canReplaceRunningApp: Bool {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app",
              !bundle.path.contains("/AppTranslocation/") else { return false }
        return FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
    }

    private func install(from zipURL: URL, expecting version: AppVersion, fallback: URL) {
        URLSession.shared.downloadTask(with: zipURL) { [weak self] location, response, error in
            // `location` is deleted when this handler returns, so unpack here.
            let result: Result<URL, Error>
            if let location, error == nil,
               (response as? HTTPURLResponse)?.statusCode == 200 {
                result = Result { try Self.unpack(location, expecting: version) }
            } else {
                result = .failure(error ?? UpdateError.download as Error)
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let newApp):
                    self?.replaceAndRelaunch(with: newApp, fallback: fallback)
                case .failure(let error):
                    Self.fail(error, fallback: fallback)
                }
            }
        }.resume()
    }

    /// Unzips into a fresh temporary folder and returns the `.app` inside,
    /// after checking it is DeskStop at the version the release advertised.
    /// The folder is on the running app's volume, because `replaceItemAt`
    /// cannot swap across volumes.
    private static func unpack(_ zip: URL, expecting version: AppVersion) throws -> URL {
        let dir = try FileManager.default.url(for: .itemReplacementDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: Bundle.main.bundleURL,
                                              create: true)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, dir.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw UpdateError.unpack }

        let app = dir.appendingPathComponent("DeskStop.app")
        guard let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              let shipped = (info["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
              shipped == version
        else { throw UpdateError.unexpectedBundle }
        return app
    }

    private func replaceAndRelaunch(with newApp: URL, fallback: URL) {
        let current = Bundle.main.bundleURL
        do {
            // Atomic swap: the running process keeps its already-mapped
            // binary, and the next launch from this path is the new version.
            _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp,
                                                      backupItemName: nil,
                                                      options: [])
        } catch {
            Self.fail(error, fallback: fallback)
            return
        }
        NSLog("DeskStop updated in place; relaunching")
        AppRelaunch.relaunchApp()
    }

    private static func fail(_ error: Error, fallback: URL) {
        NSLog("DeskStop update install failed: \(error)")
        let alert = NSAlert()
        alert.messageText = "Couldn't install the update"
        alert.informativeText = "\(error.localizedDescription)\n\nDownload it from GitHub instead, then drag it into Applications."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Download Page")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(fallback)
        }
    }

    private enum UpdateError: LocalizedError {
        case download, unpack, unexpectedBundle

        var errorDescription: String? {
            switch self {
            case .download: return "The download didn't complete."
            case .unpack: return "The downloaded file couldn't be unpacked."
            case .unexpectedBundle: return "The downloaded file isn't the expected version of DeskStop."
            }
        }
    }
}

extension UserDefaults {
    private static let autoUpdateKey = "automaticallyCheckForUpdates"
    private static let lastUpdateCheckKey = "lastUpdateCheck"
    private static let skippedUpdateKey = "skippedUpdateVersion"
    private static let lastRunVersionKey = "lastRunVersion"

    /// Default on: an app distributed outside the App Store has no other way
    /// to tell its users a fix exists.
    var automaticallyCheckForUpdates: Bool {
        get { object(forKey: Self.autoUpdateKey) as? Bool ?? true }
        set { set(newValue, forKey: Self.autoUpdateKey) }
    }

    var lastUpdateCheck: Date? {
        get { object(forKey: Self.lastUpdateCheckKey) as? Date }
        set { set(newValue, forKey: Self.lastUpdateCheckKey) }
    }

    var skippedUpdateVersion: String? {
        get { string(forKey: Self.skippedUpdateKey) }
        set { set(newValue, forKey: Self.skippedUpdateKey) }
    }

    var lastRunVersion: String? {
        get { string(forKey: Self.lastRunVersionKey) }
        set { set(newValue, forKey: Self.lastRunVersionKey) }
    }
}
