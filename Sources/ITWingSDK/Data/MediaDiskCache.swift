import Foundation
import UIKit

final class MediaDiskCache {
    static let shared = MediaDiskCache()

    private let directory: URL
    private let queue = DispatchQueue(label: "com.itwingtech.itwingsdk.media-cache", qos: .utility)

    private init() {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        directory = root.appendingPathComponent("itwing-media-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cachedData(for urlString: String) -> Data? {
        guard !urlString.isEmpty else { return nil }
        return try? Data(contentsOf: fileUrl(for: urlString))
    }

    func cachedImage(for urlString: String) -> UIImage? {
        guard let data = cachedData(for: urlString) else { return nil }
        return UIImage(data: data)
    }

    func loadImage(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
        if let image = cachedImage(for: urlString) {
            completion(image)
            return
        }
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.queue.async {
                try? data.write(to: self.fileUrl(for: urlString), options: [.atomic])
            }
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }

    func prefetch(_ urls: [String]) {
        urls.filter { cachedData(for: $0) == nil }.forEach { urlString in
            guard let url = URL(string: urlString) else { return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data else { return }
                self.queue.async {
                    try? data.write(to: self.fileUrl(for: urlString), options: [.atomic])
                }
            }.resume()
        }
    }

    func saveResponse(_ response: MediaLibraryResponse, key: String) {
        queue.async {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(response) else { return }
            try? data.write(to: self.fileUrl(for: "response-\(key)"), options: [.atomic])
        }
    }

    func loadResponse(key: String) -> MediaLibraryResponse? {
        guard let data = try? Data(contentsOf: fileUrl(for: "response-\(key)")) else { return nil }
        return try? JSONDecoder().decode(MediaLibraryResponse.self, from: data)
    }

    private func fileUrl(for urlString: String) -> URL {
        let name = Data(urlString.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(name)
    }
}
