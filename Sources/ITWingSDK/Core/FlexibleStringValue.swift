import Foundation

struct ITWingFlexibleStringValue: Codable, Sendable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { value = nil }
        else if let string = try? container.decode(String.self) { value = string }
        else if let bool = try? container.decode(Bool.self) { value = bool ? "true" : "false" }
        else if let int = try? container.decode(Int.self) { value = String(int) }
        else if let double = try? container.decode(Double.self) { value = String(double) }
        else { value = nil }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
