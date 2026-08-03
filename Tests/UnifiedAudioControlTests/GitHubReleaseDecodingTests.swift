import XCTest
@testable import UnifiedAudioControl

/// Tests for decoding the GitHub releases API payload into `GitHubRelease`.
/// A decode failure here is user-visible: `UpdateManager` reports it as a generic
/// "the data couldn't be read" error, hiding a perfectly valid release.
final class GitHubReleaseDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
    }

    func test_decodesFullyPopulatedRelease() throws {
        let release = try decode("""
        {
          "tag_name": "v1.0.5",
          "name": "Version 1.0.5",
          "body": "Notes",
          "html_url": "https://example.com/r/1",
          "published_at": "2026-01-01T00:00:00Z",
          "assets": [
            {
              "name": "UnifiedAudioControl-v1.0.5.zip",
              "browser_download_url": "https://example.com/a.zip",
              "size": 42,
              "content_type": "application/zip"
            }
          ],
          "prerelease": false,
          "draft": false
        }
        """)

        XCTAssertEqual(release.name, "Version 1.0.5")
        XCTAssertEqual(release.version, "1.0.5")
        XCTAssertEqual(release.appAsset?.name, "UnifiedAudioControl-v1.0.5.zip")
    }

    /// Regression: `name` was non-optional, but GitHub returns `null` for a release
    /// published without a title — the whole decode threw and the update check
    /// reported a decoding error instead of the available release.
    func test_decodesRelease_whenNameIsNull() throws {
        let release = try decode("""
        {
          "tag_name": "v1.0.6",
          "name": null,
          "body": null,
          "html_url": "https://example.com/r/2",
          "published_at": "2026-01-02T00:00:00Z",
          "assets": [],
          "prerelease": false,
          "draft": false
        }
        """)

        XCTAssertNil(release.name)
        XCTAssertEqual(release.version, "1.0.6")
        XCTAssertNil(release.appAsset)
    }

    func test_appAsset_picksTheZipAsset() throws {
        let release = try decode("""
        {
          "tag_name": "1.0.7",
          "name": "No v prefix",
          "body": null,
          "html_url": "https://example.com/r/3",
          "published_at": "2026-01-03T00:00:00Z",
          "assets": [
            {
              "name": "checksums.txt",
              "browser_download_url": "https://example.com/c.txt",
              "size": 1,
              "content_type": "text/plain"
            },
            {
              "name": "UnifiedAudioControl.zip",
              "browser_download_url": "https://example.com/b.zip",
              "size": 2,
              "content_type": "application/zip"
            }
          ],
          "prerelease": false,
          "draft": false
        }
        """)

        XCTAssertEqual(release.version, "1.0.7")
        XCTAssertEqual(release.appAsset?.name, "UnifiedAudioControl.zip")
    }
}
