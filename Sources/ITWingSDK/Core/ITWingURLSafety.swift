import Foundation

enum ITWingURLSafety {
    static func firstHTTPURL(_ candidates: [String?]) -> URL? {
        for candidate in candidates {
            guard let candidate,
                  let components = URLComponents(string: candidate),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = components.host,
                  !host.isEmpty,
                  components.user == nil,
                  components.password == nil,
                  let url = components.url else { continue }
            return url
        }
        return nil
    }
}
