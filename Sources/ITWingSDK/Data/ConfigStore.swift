import Foundation

final class ConfigStore {
    private let url: URL

    init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.url = directory.appendingPathComponent("itwing-config.json")
    }

    func save(_ config: ITWingConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func load() -> ITWingConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ITWingConfig.self, from: data)
    }
}

