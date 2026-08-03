import Foundation

/// Represents a GitHub release from the API
struct GitHubRelease: Codable {
    let tagName: String
    /// Optional because the GitHub API returns `null` here for a release published
    /// without a title. Declaring it non-optional made the whole decode throw, and
    /// `UpdateManager` surfaced that as "The data couldn't be read because it is
    /// missing" — a decoding error shown to the user in place of a valid release.
    let name: String?
    let body: String?
    let htmlUrl: String
    let publishedAt: String
    let assets: [ReleaseAsset]
    let prerelease: Bool
    let draft: Bool
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
        case prerelease
        case draft
    }
    
    /// Returns the version string without the 'v' prefix if present
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
    
    /// Finds the .zip asset for downloading the app
    var appAsset: ReleaseAsset? {
        assets.first { $0.name.hasSuffix(".zip") }
    }
}

/// Represents a release asset (downloadable file)
struct ReleaseAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int
    let contentType: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
        case contentType = "content_type"
    }
}

/// Compares semantic versions (e.g., "1.0.0" vs "1.0.1")
struct SemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    
    init?(string: String) {
        // Remove 'v' prefix if present
        var cleanString = string.hasPrefix("v") ? String(string.dropFirst()) : string

        // Drop any SemVer pre-release ("-beta.1") or build ("+2024") suffix before
        // parsing. Only the numeric core is compared, so "1.0.0-beta" is treated as
        // equal to "1.0.0" and never offered as an upgrade over the stable release.
        if let cut = cleanString.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            cleanString = String(cleanString[cleanString.startIndex..<cut])
        }

        // Every component must be numeric. `compactMap` would silently *drop*
        // unparseable components instead, so "1.x.2" used to parse as 1.2.0 and
        // "2024.beta.5" as 2024.5.0 — a wrong version comparison rather than a refusal.
        let rawComponents = cleanString.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(rawComponents.count) else { return nil }

        var components: [Int] = []
        for raw in rawComponents {
            guard let value = Int(raw), value >= 0 else { return nil }
            components.append(value)
        }

        self.major = components[0]
        self.minor = components[1]
        self.patch = components.count > 2 ? components[2] : 0
    }
    
    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
    
    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        return lhs.major == rhs.major &&
               lhs.minor == rhs.minor &&
               lhs.patch == rhs.patch
    }
    
    var description: String {
        "\(major).\(minor).\(patch)"
    }

    /// Decides whether `latest` is an upgrade over `current`.
    ///
    /// Returns `nil` when either string fails to parse. `nil` means "cannot tell",
    /// which is deliberately distinct from `false` ("no upgrade"): the caller must
    /// surface an error rather than leave a previous verdict standing. Since the
    /// parser became strict (it now refuses "1.x.2" instead of mis-reading it as
    /// 1.2.0), an unparseable tag is a reachable outcome, not a theoretical one.
    static func upgradeAvailable(current: String, latest: String) -> Bool? {
        guard let currentVer = SemanticVersion(string: current),
              let latestVer = SemanticVersion(string: latest) else {
            return nil
        }
        return latestVer > currentVer
    }
}
