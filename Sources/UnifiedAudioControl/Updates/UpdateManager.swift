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
            UserDefaults.standard.set(autoCheckEnabled, forKey: "autoCheckForUpdates")
        }
    }
    
    private init() {
        // Load preferences from UserDefaults
        self.autoCheckEnabled = UserDefaults.standard.bool(forKey: "autoCheckForUpdates")
        
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
                
                // Compare versions
                if let currentVer = SemanticVersion(string: currentVersion),
                   let latestVer = SemanticVersion(string: release.version) {
                    self.updateAvailable = latestVer > currentVer
                    
                    // Show notification if update is available and not silent
                    if !silent && self.updateAvailable {
                        self.showUpdateNotification()
                    }
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
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "Server returned error code \(code)"
        case .noStableRelease:
            return "No stable release available"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let updateAvailable = Notification.Name("updateAvailable")
}
