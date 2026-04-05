import Foundation

final class ProfileManager {
    private let configDir: URL

    init() {
        configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".xray/configs")
    }

    func scan() -> [Profile] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: configDir,
            includingPropertiesForKeys: [.nameKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .map { Profile(url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func configURL(for profile: Profile) -> URL {
        profile.url
    }
}
