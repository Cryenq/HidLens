import Foundation

public enum PollingProfile: Int, CaseIterable, Sendable, Codable {
    case hz125 = 125
    case hz250 = 250
    case hz500 = 500
    case hz1000 = 1000

    public var label: String {
        "\(rawValue) Hz"
    }

    public var intervalMs: Double {
        1000.0 / Double(rawValue)
    }

    public var fullSpeedBInterval: Int {
        1000 / rawValue
    }
}
