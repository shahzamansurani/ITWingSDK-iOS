import Foundation
import ImageIO
import UIKit

final class MediaDiskCache {
    static let shared = MediaDiskCache()

    fileprivate static let maximumImageBytes = 12 * 1024 * 1024
    fileprivate static let maximumConcurrentDownloads = DispatchSemaphore(value: 3)
    private static let maximumImagePixelSize = 2048

    private let directory: URL
    private let queue = DispatchQueue(label: "com.itwingtech.itwingsdk.media-cache", qos: .utility)

    private init() {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = root.appendingPathComponent("itwing-media-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func loadImage(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            if let data = try? Data(contentsOf: self.fileUrl(for: urlString)),
               let image = Self.decodeImage(data) {
                DispatchQueue.main.async { completion(image) }
                return
            }

            guard let url = Self.httpUrl(from: urlString) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let download = BoundedImageDownload(request: request) { [weak self] data in
                guard let self else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                self.queue.async {
                    guard let data,
                          let image = Self.decodeImage(data) else {
                        DispatchQueue.main.async { completion(nil) }
                        return
                    }

                    try? data.write(to: self.fileUrl(for: urlString), options: [.atomic])
                    DispatchQueue.main.async { completion(image) }
                }
            }
            download.start()
        }
    }

    func prefetch(_ urls: [String]) {
        queue.async { [weak self] in
            guard let self else { return }
            // Prefetch only the first batch; cells further down the list load on demand.
            urls.prefix(12)
                .filter { !FileManager.default.fileExists(atPath: self.fileUrl(for: $0).path) }
                .forEach { urlString in
                    guard let url = Self.httpUrl(from: urlString) else { return }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 20
                    let download = BoundedImageDownload(request: request) { [weak self] data in
                        guard let self, let data else { return }
                        self.queue.async {
                            try? data.write(to: self.fileUrl(for: urlString), options: [.atomic])
                        }
                    }
                    download.start()
                }
        }
    }

    func saveResponse(_ response: MediaLibraryResponse, key: String) {
        queue.async {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(response) else { return }
            try? data.write(to: self.fileUrl(for: "response-\(key)"), options: [.atomic])
        }
    }

    func loadResponse(key: String) async -> MediaLibraryResponse? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self,
                      let data = try? Data(contentsOf: self.fileUrl(for: "response-\(key)")),
                      let response = try? JSONDecoder().decode(MediaLibraryResponse.self, from: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: response)
            }
        }
    }

    private func fileUrl(for urlString: String) -> URL {
        let name = Data(urlString.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(name)
    }

    private static func httpUrl(from value: String) -> URL? {
        ITWingURLSafety.firstHTTPURL([value])
    }

    static func decodeImage(_ data: Data) -> UIImage? {
        guard !data.isEmpty,
              data.count <= maximumImageBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumImagePixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}

private final class BoundedImageDownload: NSObject, URLSessionDataDelegate {
    private let request: URLRequest
    private var completion: ((Data?) -> Void)?
    private var responseData = Data()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var finished = false
    private var holdsDownloadSlot = false

    init(request: URLRequest, completion: @escaping (Data?) -> Void) {
        self.request = request
        self.completion = completion
        super.init()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }

    func start() {
        DispatchQueue.global(qos: .utility).async { [self] in
            MediaDiskCache.maximumConcurrentDownloads.wait()
            guard let session else {
                MediaDiskCache.maximumConcurrentDownloads.signal()
                return
            }
            holdsDownloadSlot = true
            task = session.dataTask(with: request)
            task?.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let response = response as? HTTPURLResponse,
           !(200 ... 299).contains(response.statusCode) {
            completionHandler(.cancel)
            finish(with: nil)
            return
        }
        if response.expectedContentLength > Int64(MediaDiskCache.maximumImageBytes) {
            completionHandler(.cancel)
            finish(with: nil)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }
        guard data.count <= MediaDiskCache.maximumImageBytes - responseData.count else {
            dataTask.cancel()
            finish(with: nil)
            return
        }
        responseData.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(with: error == nil ? responseData : nil)
    }

    private func finish(with data: Data?) {
        guard !finished else { return }
        finished = true
        let completion = self.completion
        self.completion = nil
        responseData.removeAll(keepingCapacity: false)
        let session = self.session
        self.session = nil
        task = nil
        session?.finishTasksAndInvalidate()
        if holdsDownloadSlot {
            holdsDownloadSlot = false
            MediaDiskCache.maximumConcurrentDownloads.signal()
        }
        completion?(data)
    }
}
