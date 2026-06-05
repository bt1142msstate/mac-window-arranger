import Foundation

struct AppUpdate: Codable, Equatable {
    let version: String
    let tagName: String
    let releaseURL: URL
    let assetDownloadURL: URL?
    let assetName: String?
    let releaseTitle: String?
    let releaseNotes: String?

    var title: String {
        guard let releaseTitle, !releaseTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Version \(version)"
        }

        return releaseTitle
    }
}

enum AppUpdateCheckResult: Equatable {
    case upToDate(currentVersion: String, latestUpdate: AppUpdate)
    case updateAvailable(AppUpdate)
}

enum AppUpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(version: String, latestUpdate: AppUpdate?)
    case available(AppUpdate)
    case downloading(AppUpdate)
    case downloaded(AppUpdate, URL)
    case failed(String)
}
