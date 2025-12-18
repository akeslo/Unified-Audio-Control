import Foundation

/// Represents a GitHub release from the API
struct GitHubRelease: Codable {
    let tagName: String
    let name: String
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
        let cleanString = string.hasPrefix("v") ? String(string.dropFirst()) : string
        
        let components = cleanString.split(separator: ".").compactMap { Int($0) }
        guard components.count >= 2 else { return nil }
        
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
}
