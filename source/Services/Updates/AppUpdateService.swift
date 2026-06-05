import AppKit
import Foundation

final class AppUpdateService {
    private struct GitHubReleaseResponse: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL
        let assets: [GitHubReleaseAsset]

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct GitHubReleaseAsset: Decodable {
        let name: String
        let label: String?
        let browserDownloadURL: URL
        let contentType: String?

        var displayName: String {
            guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return name
            }

            return label
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case label
            case browserDownloadURL = "browser_download_url"
            case contentType = "content_type"
        }
    }

    private enum Constants {
        static let defaultLatestReleaseAPIURL = "https://api.github.com/repos/bt1142msstate/mac-window-arranger/releases/latest"
        static let latestReleaseInfoKey = "WAGitHubLatestReleaseAPIURL"
        static let updatesEnabledInfoKey = "WAGitHubUpdatesEnabled"
        static let cachedUpdateDefaultsKey = "cachedAvailableUpdate.v1"
        static let lastAutomaticCheckDefaultsKey = "lastAutomaticUpdateCheckDate.v1"
        static let automaticCheckInterval: TimeInterval = 60 * 60 * 24
    }

    private let bundle: Bundle
    private let defaults: UserDefaults
    private let session: URLSession
    private let fileManager: FileManager

    init(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.bundle = bundle
        self.defaults = defaults
        self.session = session
        self.fileManager = fileManager
    }

    var isGitHubUpdateCheckEnabled: Bool {
        if let value = bundle.object(forInfoDictionaryKey: Constants.updatesEnabledInfoKey) as? Bool {
            return value
        }

        return true
    }

    var currentVersion: String {
        (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    var currentVersionDisplay: String {
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        guard !build.isEmpty else {
            return currentVersion
        }

        return "\(currentVersion) (\(build))"
    }

    func shouldRunAutomaticCheck(now: Date = Date()) -> Bool {
        guard isGitHubUpdateCheckEnabled else {
            return false
        }

        guard let lastCheck = defaults.object(forKey: Constants.lastAutomaticCheckDefaultsKey) as? Date else {
            return true
        }

        return now.timeIntervalSince(lastCheck) >= Constants.automaticCheckInterval
    }

    func markAutomaticCheckCompleted(now: Date = Date()) {
        defaults.set(now, forKey: Constants.lastAutomaticCheckDefaultsKey)
    }

    func cachedAvailableUpdate() -> AppUpdate? {
        guard
            let data = defaults.data(forKey: Constants.cachedUpdateDefaultsKey),
            let update = try? JSONDecoder().decode(AppUpdate.self, from: data)
        else {
            return nil
        }

        guard isNewerThanCurrent(update) else {
            clearCachedAvailableUpdate()
            return nil
        }

        return update
    }

    func cacheAvailableUpdate(_ update: AppUpdate) {
        guard let data = try? JSONEncoder().encode(update) else {
            return
        }

        defaults.set(data, forKey: Constants.cachedUpdateDefaultsKey)
    }

    func clearCachedAvailableUpdate() {
        defaults.removeObject(forKey: Constants.cachedUpdateDefaultsKey)
    }

    func checkForUpdate(completion: @escaping (Result<AppUpdateCheckResult, Error>) -> Void) {
        guard isGitHubUpdateCheckEnabled else {
            completion(.failure(AppUpdateServiceError.disabled))
            return
        }

        guard let latestReleaseAPIURL else {
            completion(.failure(AppUpdateServiceError.invalidFeedURL))
            return
        }

        var request = URLRequest(url: latestReleaseAPIURL)
        request.timeoutInterval = 18
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                return
            }

            if let error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    if httpResponse.statusCode == 404 {
                        completion(.failure(AppUpdateServiceError.noRelease))
                    } else {
                        completion(.failure(AppUpdateServiceError.badStatus(httpResponse.statusCode)))
                    }
                    return
                }
            }

            guard let data else {
                completion(.failure(AppUpdateServiceError.missingData))
                return
            }

            do {
                let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
                let update = self.update(from: release)

                if self.isNewerThanCurrent(update) {
                    self.cacheAvailableUpdate(update)
                    completion(.success(.updateAvailable(update)))
                } else {
                    self.clearCachedAvailableUpdate()
                    completion(.success(.upToDate(currentVersion: self.currentVersionDisplay, latestUpdate: update)))
                }
            } catch {
                completion(.failure(error))
            }
        }
        .resume()
    }

    func downloadAndOpen(update: AppUpdate, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let assetURL = update.assetDownloadURL else {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(update.releaseURL)
                completion(.success(update.releaseURL))
            }
            return
        }

        var request = URLRequest(url: assetURL)
        request.timeoutInterval = 60
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        session.downloadTask(with: request) { [weak self] temporaryURL, response, error in
            guard let self else {
                return
            }

            if let error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                completion(.failure(AppUpdateServiceError.badStatus(httpResponse.statusCode)))
                return
            }

            guard let temporaryURL else {
                completion(.failure(AppUpdateServiceError.missingData))
                return
            }

            do {
                let destinationURL = try self.destinationURL(for: update)

                if self.fileManager.fileExists(atPath: destinationURL.path) {
                    try self.fileManager.removeItem(at: destinationURL)
                }

                try self.fileManager.moveItem(at: temporaryURL, to: destinationURL)

                DispatchQueue.main.async {
                    NSWorkspace.shared.open(destinationURL)
                    completion(.success(destinationURL))
                }
            } catch {
                completion(.failure(error))
            }
        }
        .resume()
    }

    func openReleasePage(for update: AppUpdate) {
        NSWorkspace.shared.open(update.releaseURL)
    }

    private var latestReleaseAPIURL: URL? {
        let rawURL = (bundle.object(forInfoDictionaryKey: Constants.latestReleaseInfoKey) as? String)
            ?? Constants.defaultLatestReleaseAPIURL
        return URL(string: rawURL)
    }

    private var userAgent: String {
        "Mac-Window-Arranger/\(currentVersion)"
    }

    private func update(from release: GitHubReleaseResponse) -> AppUpdate {
        let asset = preferredDownloadAsset(from: release.assets)

        return AppUpdate(
            version: normalizedVersionString(release.tagName),
            tagName: release.tagName,
            releaseURL: release.htmlURL,
            assetDownloadURL: asset?.browserDownloadURL,
            assetName: asset?.displayName,
            releaseTitle: release.name,
            releaseNotes: release.body
        )
    }

    private func preferredDownloadAsset(from assets: [GitHubReleaseAsset]) -> GitHubReleaseAsset? {
        assets.first { asset in
            asset.name.lowercased().hasSuffix(".dmg")
        } ?? assets.first { asset in
            asset.contentType == "application/x-apple-diskimage"
        }
    }

    private func destinationURL(for update: AppUpdate) throws -> URL {
        let downloadsDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let rawFileName = update.assetName ?? "Window Arranger \(update.version).dmg"
        let fileName = sanitizedFileName(rawFileName)

        return downloadsDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private func sanitizedFileName(_ rawFileName: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " .-_"))
        let scalars = rawFileName.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : "-"
        }
        let fileName = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)

        return fileName.isEmpty ? "Window Arranger.dmg" : fileName
    }

    private func isNewerThanCurrent(_ update: AppUpdate) -> Bool {
        compareVersions(update.version, currentVersion) == .orderedDescending
    }

    private func normalizedVersionString(_ rawVersion: String) -> String {
        let trimmed = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.lowercased().hasPrefix("v") else {
            return trimmed
        }

        return String(trimmed.dropFirst())
    }

    private func compareVersions(_ leftVersion: String, _ rightVersion: String) -> ComparisonResult {
        let leftParts = versionParts(leftVersion)
        let rightParts = versionParts(rightVersion)
        let count = max(leftParts.count, rightParts.count)

        for index in 0..<count {
            let left = leftParts[safe: index] ?? 0
            let right = rightParts[safe: index] ?? 0

            if left > right {
                return .orderedDescending
            }

            if left < right {
                return .orderedAscending
            }
        }

        return .orderedSame
    }

    private func versionParts(_ version: String) -> [Int] {
        let normalized = normalizedVersionString(version)

        return normalized
            .split(separator: ".")
            .map { component in
                let numericPrefix = component.prefix { character in
                    character.isNumber
                }

                return Int(numericPrefix) ?? 0
            }
    }
}

enum AppUpdateServiceError: LocalizedError {
    case disabled
    case invalidFeedURL
    case noRelease
    case badStatus(Int)
    case missingData

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "GitHub update checks are disabled for this build."
        case .invalidFeedURL:
            return "The GitHub update feed URL is invalid."
        case .noRelease:
            return "No GitHub release was found yet."
        case .badStatus(let statusCode):
            return "GitHub returned HTTP \(statusCode)."
        case .missingData:
            return "The update response was empty."
        }
    }
}
