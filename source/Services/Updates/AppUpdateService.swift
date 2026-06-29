import AppKit
import Foundation

final class AppUpdateService: @unchecked Sendable {
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

    func checkForUpdate(completion: @escaping @Sendable (Result<AppUpdateCheckResult, Error>) -> Void) {
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

    func downloadAndInstall(update: AppUpdate, completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        guard let assetURL = update.assetDownloadURL else {
            completion(.failure(AppUpdateServiceError.missingDownloadAsset))
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
                let updateDirectoryURL = try self.temporaryUpdateDirectory()
                let dmgURL = updateDirectoryURL.appendingPathComponent(
                    self.sanitizedFileName(update.assetName ?? "Window Arranger \(update.version).dmg"),
                    isDirectory: false
                )

                if self.fileManager.fileExists(atPath: dmgURL.path) {
                    try self.fileManager.removeItem(at: dmgURL)
                }

                try self.fileManager.moveItem(at: temporaryURL, to: dmgURL)

                var mountedUpdate: MountedUpdate?

                do {
                    mountedUpdate = try self.mountUpdateDMG(dmgURL, in: updateDirectoryURL)
                    guard let mountedUpdate else {
                        throw AppUpdateServiceError.appBundleNotFound
                    }

                    try self.validateMountedUpdate(mountedUpdate, for: update)

                    let destinationURL = try self.installDestinationURL()
                    try self.validateInstallDestination(destinationURL)
                    try self.launchInstaller(
                        mountedUpdate: mountedUpdate,
                        destinationURL: destinationURL,
                        cleanupDirectoryURL: updateDirectoryURL
                    )

                    Task { @MainActor in
                        completion(.success(destinationURL))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            NSApp.terminate(nil)
                        }
                    }
                } catch {
                    if let mountedUpdate {
                        self.detachMountedUpdate(mountedUpdate)
                    }

                    try? self.fileManager.removeItem(at: updateDirectoryURL)
                    throw error
                }
            } catch {
                completion(.failure(error))
            }
        }
        .resume()
    }

    @MainActor
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

    private struct MountedUpdate {
        let mountPointURL: URL
        let appBundleURL: URL
    }

    private func sanitizedFileName(_ rawFileName: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " .-_"))
        let scalars = rawFileName.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : "-"
        }
        let fileName = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)

        return fileName.isEmpty ? "Window Arranger.dmg" : fileName
    }

    private func temporaryUpdateDirectory() throws -> URL {
        let parentDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("Window Arranger Updates", isDirectory: true)
        let updateDirectoryURL = parentDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(
            at: updateDirectoryURL,
            withIntermediateDirectories: true
        )

        return updateDirectoryURL
    }

    private func mountUpdateDMG(_ dmgURL: URL, in updateDirectoryURL: URL) throws -> MountedUpdate {
        let mountPointURL = updateDirectoryURL.appendingPathComponent("mount", isDirectory: true)
        try fileManager.createDirectory(at: mountPointURL, withIntermediateDirectories: true)

        _ = try runProcess(
            executablePath: "/usr/bin/hdiutil",
            arguments: ["attach", dmgURL.path, "-readonly", "-nobrowse", "-mountpoint", mountPointURL.path]
        )

        guard let appBundleURL = try appBundleURL(in: mountPointURL) else {
            throw AppUpdateServiceError.appBundleNotFound
        }

        return MountedUpdate(mountPointURL: mountPointURL, appBundleURL: appBundleURL)
    }

    private func appBundleURL(in directoryURL: URL) throws -> URL? {
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        return contents.first { url in
            url.lastPathComponent == "Window Arranger.app"
        } ?? contents.first { url in
            url.pathExtension == "app"
        }
    }

    private func validateMountedUpdate(_ mountedUpdate: MountedUpdate, for update: AppUpdate) throws {
        guard let currentBundleIdentifier = bundle.bundleIdentifier else {
            throw AppUpdateServiceError.invalidCurrentBundle
        }

        guard let updateBundle = Bundle(url: mountedUpdate.appBundleURL) else {
            throw AppUpdateServiceError.invalidUpdateBundle
        }

        guard updateBundle.bundleIdentifier == currentBundleIdentifier else {
            throw AppUpdateServiceError.bundleIdentifierMismatch
        }

        let updateVersion = (updateBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        guard compareVersions(updateVersion, currentVersion) == .orderedDescending else {
            throw AppUpdateServiceError.updateIsNotNewer
        }

        guard normalizedVersionString(update.version) == normalizedVersionString(updateVersion) else {
            throw AppUpdateServiceError.releaseVersionMismatch
        }

        _ = try runProcess(
            executablePath: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", mountedUpdate.appBundleURL.path]
        )

        let currentRequirement = try designatedRequirement(for: bundle.bundleURL)
        let updateRequirement = try designatedRequirement(for: mountedUpdate.appBundleURL)

        guard currentRequirement == updateRequirement else {
            throw AppUpdateServiceError.signingRequirementMismatch
        }
    }

    private func installDestinationURL() throws -> URL {
        let currentBundleURL = bundle.bundleURL.standardizedFileURL
        let homeApplicationsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL

        if currentBundleURL.pathExtension == "app",
           !currentBundleURL.path.hasPrefix("/Volumes/"),
           !currentBundleURL.path.hasPrefix(fileManager.temporaryDirectory.standardizedFileURL.path),
           (currentBundleURL.path.hasPrefix("/Applications/") || currentBundleURL.path.hasPrefix(homeApplicationsURL.path + "/")) {
            return currentBundleURL
        }

        return URL(fileURLWithPath: "/Applications/Window Arranger.app", isDirectory: true)
    }

    private func validateInstallDestination(_ destinationURL: URL) throws {
        let parentDirectoryURL = destinationURL.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: parentDirectoryURL.path) {
            try fileManager.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
        }

        guard fileManager.isWritableFile(atPath: parentDirectoryURL.path) else {
            throw AppUpdateServiceError.installLocationNotWritable(parentDirectoryURL.path)
        }
    }

    private func launchInstaller(
        mountedUpdate: MountedUpdate,
        destinationURL: URL,
        cleanupDirectoryURL: URL
    ) throws {
        let scriptURL = cleanupDirectoryURL.appendingPathComponent("install-window-arranger-update.sh", isDirectory: false)
        let script = """
        #!/bin/sh
        set -eu

        current_pid="$1"
        source_app="$2"
        destination_app="$3"
        mount_point="$4"
        cleanup_dir="$5"
        app_name="$6"
        executable_name="$7"
        log_file="$cleanup_dir/install.log"

        {
          while kill -0 "$current_pid" 2>/dev/null; do
            sleep 0.2
          done

          parent_dir="$(dirname "$destination_app")"
          mkdir -p "$parent_dir"

          tmp_app="$parent_dir/.$app_name.update.$$"
          backup_app="$parent_dir/.$app_name.previous.$$"
          rm -rf "$tmp_app" "$backup_app"

          ditto "$source_app" "$tmp_app"
          xattr -cr "$tmp_app"
          codesign --verify --deep --strict "$tmp_app"

          if [ -d "$destination_app" ]; then
            mv "$destination_app" "$backup_app"
          fi

          if mv "$tmp_app" "$destination_app"; then
            rm -rf "$backup_app"
          else
            if [ -d "$backup_app" ]; then
              mv "$backup_app" "$destination_app"
            fi
            exit 1
          fi

          hdiutil detach "$mount_point" -quiet || true

          launched=0
          for attempt in 1 2 3 4 5 6 7 8 9 10; do
            if /usr/bin/open -n "$destination_app"; then
              for wait_attempt in 1 2 3 4 5; do
                if /usr/bin/pgrep -x "$executable_name" >/dev/null 2>&1; then
                  launched=1
                  break
                fi
                sleep 0.25
              done
            fi

            if [ "$launched" -eq 1 ]; then
              break
            fi

            sleep 0.5
          done

          if [ "$launched" -ne 1 ]; then
            echo "Failed to relaunch $destination_app"
            exit 1
          fi

          rm -rf "$cleanup_dir"
        } >> "$log_file" 2>&1 &
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            mountedUpdate.appBundleURL.path,
            destinationURL.path,
            mountedUpdate.mountPointURL.path,
            cleanupDirectoryURL.path,
            destinationURL.deletingPathExtension().lastPathComponent,
            bundle.executableURL?.lastPathComponent ?? destinationURL.deletingPathExtension().lastPathComponent
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw AppUpdateServiceError.installerLaunchFailed
        }
    }

    private func detachMountedUpdate(_ mountedUpdate: MountedUpdate) {
        _ = try? runProcess(
            executablePath: "/usr/bin/hdiutil",
            arguments: ["detach", mountedUpdate.mountPointURL.path, "-quiet"]
        )
    }

    private func designatedRequirement(for appBundleURL: URL) throws -> String {
        let output = try runProcess(
            executablePath: "/usr/bin/codesign",
            arguments: ["-d", "--requirements", "-", appBundleURL.path]
        )

        let prefix = "designated => "
        guard let requirementLine = output
            .split(whereSeparator: \.isNewline)
            .first(where: { $0.hasPrefix(prefix) })
        else {
            throw AppUpdateServiceError.missingDesignatedRequirement
        }

        return String(requirementLine.dropFirst(prefix.count))
    }

    private func runProcess(executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        var outputData = Data()
        outputData.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        outputData.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        let output = String(data: outputData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw AppUpdateServiceError.commandFailed((executablePath as NSString).lastPathComponent, output)
        }

        return output
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
    case missingDownloadAsset
    case invalidCurrentBundle
    case invalidUpdateBundle
    case bundleIdentifierMismatch
    case updateIsNotNewer
    case releaseVersionMismatch
    case appBundleNotFound
    case signingRequirementMismatch
    case missingDesignatedRequirement
    case installLocationNotWritable(String)
    case installerLaunchFailed
    case commandFailed(String, String)

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
        case .missingDownloadAsset:
            return "The release does not include a DMG update."
        case .invalidCurrentBundle:
            return "The running app bundle could not be validated."
        case .invalidUpdateBundle:
            return "The downloaded app bundle could not be read."
        case .bundleIdentifierMismatch:
            return "The downloaded app does not match Window Arranger."
        case .updateIsNotNewer:
            return "The downloaded app is not newer than the installed version."
        case .releaseVersionMismatch:
            return "The downloaded app version does not match the GitHub release."
        case .appBundleNotFound:
            return "The downloaded DMG did not contain Window Arranger.app."
        case .signingRequirementMismatch:
            return "The downloaded app is signed by a different identity, so it was not installed automatically."
        case .missingDesignatedRequirement:
            return "The app signing requirement could not be read."
        case .installLocationNotWritable(let path):
            return "Window Arranger could not write to \(path). Install the DMG manually or move the app to a writable Applications folder."
        case .installerLaunchFailed:
            return "The update installer could not be started."
        case .commandFailed(let command, let output):
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedOutput.isEmpty else {
                return "\(command) failed while preparing the update."
            }

            return "\(command) failed: \(trimmedOutput)"
        }
    }
}
