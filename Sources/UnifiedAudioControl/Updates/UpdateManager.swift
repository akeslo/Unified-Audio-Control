import Foundation
import AppKit

/// Manages checking for and downloading updates from GitHub releases
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    // GitHub repository information
    private let repoOwner = "akeslo"
    private let repoName = "Unified-Audio-Control"
    private let apiBaseURL = "https://api.github.com"
    
    // Published state for UI binding
    @Published var isChecking = false
    @Published var latestRelease: GitHubRelease?
    @Published var updateAvailable = false
    @Published var lastCheckDate: Date?
    @Published var errorMessage: String?
    
    // User preferences (stored in UserDefaults)
    @Published var autoCheckEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckEnabled, forKey: UpdateManager.autoCheckDefaultsKey)
        }
    }
    
    /// Key for the "check on launch" preference.
    static let autoCheckDefaultsKey = "autoCheckForUpdates"

    /// Seeds the launch-check preference to on for installs that have never set it.
    ///
    /// `UserDefaults.bool(forKey:)` returns false for an absent key, so a fresh
    /// install started with the updater silently off: the README advertises a
    /// built-in updater, the app runs the launch check behind
    /// `autoCheckEnabled == true`, and nothing ever ran it until the user found the
    /// toggle in Preferences. `register(defaults:)` supplies a value only when the
    /// key is absent, so anyone who deliberately turned it off keeps it off.
    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [autoCheckDefaultsKey: true])
    }

    private init() {
        // Load preferences from UserDefaults
        UpdateManager.registerDefaults()
        self.autoCheckEnabled = UserDefaults.standard.bool(forKey: UpdateManager.autoCheckDefaultsKey)

        if let lastCheck = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date {
            self.lastCheckDate = lastCheck
        }
    }
    
    /// Returns the current app version from the bundle
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    /// Check for updates manually or automatically
    func checkForUpdates(silent: Bool = false) async {
        await MainActor.run {
            isChecking = true
            errorMessage = nil
        }
        
        do {
            let release = try await fetchLatestRelease()
            
            await MainActor.run {
                self.latestRelease = release
                self.lastCheckDate = Date()
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
                
                // Compare versions. A nil verdict means one of the two strings did not
                // parse — report it instead of falling through, which used to leave a
                // stale `updateAvailable` from an earlier check standing with no error
                // shown anywhere in the UI.
                if let upgrade = SemanticVersion.upgradeAvailable(
                    current: currentVersion,
                    latest: release.version
                ) {
                    self.updateAvailable = upgrade

                    // Show notification if update is available and not silent
                    if !silent && self.updateAvailable {
                        self.showUpdateNotification()
                    }
                } else {
                    self.updateAvailable = false
                    self.errorMessage = UpdateError.unreadableVersion(
                        current: currentVersion,
                        latest: release.version
                    ).localizedDescription
                }

                self.isChecking = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isChecking = false
            }
        }
    }
    
    /// Fetch the latest release from GitHub API
    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "\(apiBaseURL)/repos/\(repoOwner)/\(repoName)/releases/latest")!
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw UpdateError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        let release = try decoder.decode(GitHubRelease.self, from: data)
        
        // Filter out drafts and prereleases
        guard !release.draft && !release.prerelease else {
            throw UpdateError.noStableRelease
        }
        
        return release
    }
    
    /// Download the update file
    func downloadUpdate() {
        guard let release = latestRelease,
              let asset = release.appAsset,
              let downloadURL = URL(string: asset.browserDownloadUrl) else {
            // Same silent-failure shape documented elsewhere in this class: without
            // this, clicking "Download Update" when the release has no .zip asset (or
            // no release has been fetched yet) does nothing and shows no error.
            errorMessage = UpdateError.missingDownloadAsset.localizedDescription
            return
        }
        
        // Open the download URL in the default browser
        NSWorkspace.shared.open(downloadURL)
        
        // Also open the release page for instructions
        if let releaseURL = URL(string: release.htmlUrl) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSWorkspace.shared.open(releaseURL)
            }
        }
    }
    
    /// Show a notification that an update is available
    private func showUpdateNotification() {
        // Post notification for UI to handle
        NotificationCenter.default.post(name: .updateAvailable, object: latestRelease)
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case noStableRelease
    case unreadableVersion(current: String, latest: String)
    case missingDownloadAsset

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "Server returned error code \(code)"
        case .noStableRelease:
            return "No stable release available"
        case .unreadableVersion(let current, let latest):
            return "Could not compare versions (installed \"\(current)\", released \"\(latest)\")"
        case .missingDownloadAsset:
            return "No downloadable .zip asset found in the latest release"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let updateAvailable = Notification.Name("updateAvailable")
}
