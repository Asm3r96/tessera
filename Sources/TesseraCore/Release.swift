import Foundation

/// A GitHub release of Tessera that has a downloadable app.
public struct Release: Equatable {
    public let version: Version
    public let page: URL
    public let download: URL

    /// Reads the GitHub "latest release" response. Returns nil without a valid version tag or an https Tessera.zip asset.
    public static func parse(_ data: Data) -> Release? {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let assets: [Asset]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let version = Version(payload.tag_name),
              let asset = payload.assets.first(where: { $0.name == "Tessera.zip" }),
              asset.browser_download_url.scheme == "https" else { return nil }
        return Release(version: version, page: payload.html_url, download: asset.browser_download_url)
    }
}
