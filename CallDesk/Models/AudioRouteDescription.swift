import Foundation

nonisolated enum AudioRouteType: String, Codable, CaseIterable, Sendable {
    case builtInSpeaker
    case receiver
    case headphones
    case bluetooth
    case airPlay
    case wired
    case unknown
}

nonisolated struct AudioRouteDescription: Equatable, Hashable, Codable, Sendable {
    let type: AudioRouteType
    let name: String

    static let defaultSpeaker = AudioRouteDescription(
        uncheckedType: .builtInSpeaker,
        name: "Built-in Speaker"
    )
    static let unknown = AudioRouteDescription(uncheckedType: .unknown, name: "Unknown")

    var isExternal: Bool {
        switch type {
        case .headphones, .bluetooth, .airPlay, .wired:
            true
        case .builtInSpeaker, .receiver, .unknown:
            false
        }
    }

    init(type: AudioRouteType, name: String) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw DomainValidationError.emptyText(field: "name")
        }

        self.init(uncheckedType: type, name: normalizedName)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            type: container.decode(AudioRouteType.self, forKey: .type),
            name: container.decode(String.self, forKey: .name)
        )
    }

    private init(uncheckedType type: AudioRouteType, name: String) {
        self.type = type
        self.name = name
    }
}
