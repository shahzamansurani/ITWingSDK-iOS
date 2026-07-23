import Foundation
import UIKit

final class ConfigRepository {
    private let apiKey: String
    private let options: ITWingOptions
    private let signer: RequestSigner
    private let store = ConfigStore()

    init(apiKey: String, options: ITWingOptions) {
        self.apiKey = apiKey
        self.options = options
        self.signer = RequestSigner(apiKey: apiKey)
    }

    func bootstrap() async throws -> ITWingConfig {
        try await postConfig(path: "/bootstrap", lastVersion: nil)
    }

    func syncConfig(lastVersion: Int) async throws -> ITWingConfig? {
        do {
            return try await postConfig(path: "/config/sync", lastVersion: lastVersion)
        } catch ConfigError.notModified {
            return nil
        }
    }

    func loadCachedConfig() -> ITWingConfig? {
        store.load()
    }

    func reportApiKeyUsage(configKey: String, selectedKeyId: String?) async throws -> Bool {
        var payload: [String: Any] = [
            "install_id": installId()
        ]
        if let selectedKeyId, !selectedKeyId.isEmpty {
            payload["selected_key_id"] = selectedKeyId
        }

        let data = try await signedRequest(path: "/api-keys/\(configKey.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/usage", payload: payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let responseData = json?["data"] as? [String: Any]
        return responseData?["rotate"] as? Bool ?? false
    }

    func submitAnalytics(events: [[String: Any]]) async throws {
        let payload: [String: Any] = [
            "install_id": installId(),
            "country": Locale.current.regionCode ?? "",
            "timezone": TimeZone.current.identifier,
            "events": events
        ]
        _ = try await signedRequest(path: "/analytics/events", payload: payload)
    }

    func fetchMedia(kind: String, placement: String?, categoryId: String?, limit: Int?, sort: String?, selectedItemIds: [String] = []) async throws -> MediaLibraryResponse {
        var payload: [String: Any] = [
            "kind": kind,
            "install_id": installId()
        ]
        if let placement, !placement.isEmpty { payload["placement"] = placement }
        if let categoryId, !categoryId.isEmpty { payload["category_id"] = categoryId }
        if let limit { payload["limit"] = limit }
        if let sort, !sort.isEmpty { payload["sort"] = sort }
        if !selectedItemIds.isEmpty { payload["item_ids"] = selectedItemIds }

        let path = kind == "wallpapers" ? "/wallpapers" : "/media/\(kind)"
        let cacheKey = "\(kind)-\(placement ?? "")-\(categoryId ?? "")-\(limit ?? 0)-\(sort ?? "")-\(selectedItemIds.joined(separator: ","))"
        do {
            let data = try await signedRequest(path: path, payload: payload)
            let response = try JSONDecoder().decode(MediaLibraryEnvelope.self, from: data).data
            MediaDiskCache.shared.saveResponse(response, key: cacheKey)
            return response
        } catch {
            if let cached = MediaDiskCache.shared.loadResponse(key: cacheKey) {
                return cached
            }
            throw error
        }
    }

    func submitMediaEvent(kind: String, itemId: String, eventType: String, metadata: [String: Any] = [:]) async throws {
        var payload: [String: Any] = [
            "install_id": installId(),
            "event_type": eventType,
            "metadata": metadata
        ]
        if kind != "wallpapers" {
            payload["kind"] = kind
        }
        let path = kind == "wallpapers" ? "/wallpapers/\(itemId)/events" : "/media/\(kind)/\(itemId)/events"
        _ = try await signedRequest(path: path, payload: payload)
    }

    func fetchCustomAds(format: String?, placement: String?) async throws -> [ITWingCustomAd] {
        var query: [URLQueryItem] = []
        if let format, !format.isEmpty { query.append(URLQueryItem(name: "format", value: format)) }
        if let placement, !placement.isEmpty { query.append(URLQueryItem(name: "placement", value: placement)) }
        let suffix: String
        if query.isEmpty {
            suffix = ""
        } else {
            var components = URLComponents()
            components.queryItems = query
            suffix = components.string ?? ""
        }
        let data = try await signedRequest(path: "/custom-ads\(suffix)", method: "GET", payload: nil)
        return try JSONDecoder().decode(CustomAdsEnvelope.self, from: data).data.ads
    }

    func submitCustomAdEvent(adId: String, eventType: String, metadata: [String: Any] = [:]) async throws {
        let payload: [String: Any] = [
            "install_id": installId(),
            "event_type": eventType,
            "country": Locale.current.regionCode ?? "",
            "metadata": metadata
        ]
        _ = try await signedRequest(path: "/custom-ads/\(adId)/events", payload: payload)
    }

    func pendingNotifications() async throws -> [ITWingInAppNotification] {
        let payload: [String: Any] = [
            "install_id": installId()
        ]
        let data = try await signedRequest(path: "/notifications/pending", payload: payload)
        return try JSONDecoder().decode(InAppNotificationEnvelope.self, from: data).data
    }

    func submitNotificationEvent(campaignId: String, event: String) async throws {
        let payload: [String: Any] = [
            "install_id": installId(),
            "event": event
        ]
        _ = try await signedRequest(path: "/notifications/\(campaignId)/event", payload: payload)
    }

    func registerPushToken(_ token: String) async throws {
        let payload: [String: Any] = [
            "install_id": installId(),
            "token": token,
            "platform": "ios",
            "bundle_id": Bundle.main.bundleIdentifier ?? ""
        ]
        _ = try await signedRequest(path: "/notifications/device", payload: payload)
    }

    func verifyPurchase(payload: [String: Any]) async throws -> Bool {
        let data = try await signedRequest(path: "/subscriptions/verify", payload: payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let responseData = json?["data"] as? [String: Any]
        return responseData?["active"] as? Bool ?? responseData?["success"] as? Bool ?? false
    }

    private func postConfig(path: String, lastVersion: Int?) async throws -> ITWingConfig {
        var payload: [String: Any] = [
            "install_id": installId(),
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "os_version": UIDevice.current.systemVersion,
            "device_model": UIDevice.current.model,
            "premium": false
        ]

        if let lastVersion {
            payload["last_config_version"] = lastVersion
        }

        let data = try await signedRequest(path: path, payload: payload)

        let envelope = try JSONDecoder().decode(ApiEnvelope.self, from: data)
        store.save(envelope.data)
        return envelope.data
    }

    private func signedRequest(path: String, payload: [String: Any]) async throws -> Data {
        try await signedRequest(path: path, method: "POST", payload: payload)
    }

    private func signedRequest(path: String, method: String, payload: [String: Any]?) async throws -> Data {
        let body = payload == nil ? Data() : try JSONSerialization.data(withJSONObject: payload ?? [:])
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let nonce = UUID().uuidString
        let bodyHash = signer.sha256(body)
        let requestPath = path.components(separatedBy: "?").first ?? path
        let endpointPath = options.endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let signedPath = "/" + [endpointPath, requestPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))].filter { !$0.isEmpty }.joined(separator: "/")
        let signature = signer.sign(method: method, path: signedPath, timestamp: timestamp, nonce: nonce, bodyHash: bodyHash)

        guard let url = URL(string: options.endpoint.absoluteString + path) else {
            throw ConfigError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if method != "GET" {
            request.httpBody = body
        }
        request.timeoutInterval = options.bootstrapTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-ITW-Key")
        request.setValue(timestamp, forHTTPHeaderField: "X-ITW-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-ITW-Nonce")
        request.setValue(signature, forHTTPHeaderField: "X-ITW-Signature")
        request.setValue("ios", forHTTPHeaderField: "X-ITW-Platform")
        request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-ITW-App-Identifier")
        request.setValue(ITWingSDK.version, forHTTPHeaderField: "X-ITW-SDK-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConfigError.invalidResponse }
        if http.statusCode == 304 { throw ConfigError.notModified }
        guard (200..<300).contains(http.statusCode) else { throw ConfigError.http(http.statusCode) }

        return data
    }

    private func installId() -> String {
        if let existing = UserDefaults.standard.string(forKey: "itwing_install_id") {
            return existing
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: "itwing_install_id")
        return value
    }
}

private struct ApiEnvelope: Decodable {
    let data: ITWingConfig
}

enum ConfigError: Error {
    case invalidResponse
    case notModified
    case http(Int)
}
