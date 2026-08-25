import Foundation

nonisolated struct VoiceSettings: Equatable, Hashable, Codable, Sendable {
    let localeIdentifier: String
    /// The identifier of the preferred speech voice. `nil` lets playback pick
    /// the best installed Chinese voice automatically.
    let voiceIdentifier: String?
    let rate: Double
    let pitchMultiplier: Double
    let volume: Double
    /// How much high-frequency energy is rolled off during playback
    /// (0…1). Higher values make the voice softer and warmer by cutting
    /// the bright air band the speaker adds.
    let softness: Double
    /// How much breath and natural variation the synthesized voice has
    /// (Matcha `noise_scale`, 0.1…0.7). Lower sounds cleaner, higher
    /// sounds breathier and more human.
    let noiseScale: Double
    /// Whether a light haptic taps when an announcement is requested.
    let hapticFeedback: Bool

    static let `default` = VoiceSettings(
        uncheckedLocaleIdentifier: "zh-CN",
        voiceIdentifier: nil,
        rate: 0.5,
        pitchMultiplier: 1,
        volume: 1,
        softness: 1.0 / 3.0,
        noiseScale: 0.4,
        hapticFeedback: true
    )

    init(
        localeIdentifier: String,
        voiceIdentifier: String? = nil,
        rate: Double,
        pitchMultiplier: Double,
        volume: Double,
        softness: Double = 1.0 / 3.0,
        noiseScale: Double = 0.4,
        hapticFeedback: Bool = true
    ) throws {
        let normalizedLocaleIdentifier = localeIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedLocaleIdentifier.isEmpty else {
            throw DomainValidationError.emptyText(field: "localeIdentifier")
        }
        guard (0...1).contains(rate) else {
            throw DomainValidationError.invalidRange(field: "rate")
        }
        guard (0.5...2).contains(pitchMultiplier) else {
            throw DomainValidationError.invalidRange(field: "pitchMultiplier")
        }
        guard (0...1).contains(volume) else {
            throw DomainValidationError.invalidRange(field: "volume")
        }
        guard (0...1).contains(softness) else {
            throw DomainValidationError.invalidRange(field: "softness")
        }
        guard (0.1...0.7).contains(noiseScale) else {
            throw DomainValidationError.invalidRange(field: "noiseScale")
        }

        let normalizedVoiceIdentifier = voiceIdentifier?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.init(
            uncheckedLocaleIdentifier: normalizedLocaleIdentifier,
            voiceIdentifier: (normalizedVoiceIdentifier?.isEmpty ?? true) ? nil : normalizedVoiceIdentifier,
            rate: rate,
            pitchMultiplier: pitchMultiplier,
            volume: volume,
            softness: softness,
            noiseScale: noiseScale,
            hapticFeedback: hapticFeedback
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            localeIdentifier: container.decode(String.self, forKey: .localeIdentifier),
            voiceIdentifier: container.decodeIfPresent(String.self, forKey: .voiceIdentifier),
            rate: container.decode(Double.self, forKey: .rate),
            pitchMultiplier: container.decode(Double.self, forKey: .pitchMultiplier),
            volume: container.decode(Double.self, forKey: .volume),
            softness: container.decodeIfPresent(Double.self, forKey: .softness) ?? 1.0 / 3.0,
            noiseScale: container.decodeIfPresent(Double.self, forKey: .noiseScale) ?? 0.4,
            hapticFeedback: container.decodeIfPresent(Bool.self, forKey: .hapticFeedback) ?? true
        )
    }

    private init(uncheckedLocaleIdentifier localeIdentifier: String, voiceIdentifier: String?, rate: Double, pitchMultiplier: Double, volume: Double, softness: Double, noiseScale: Double, hapticFeedback: Bool) {
        self.localeIdentifier = localeIdentifier
        self.voiceIdentifier = voiceIdentifier
        self.rate = rate
        self.pitchMultiplier = pitchMultiplier
        self.volume = volume
        self.softness = softness
        self.noiseScale = noiseScale
        self.hapticFeedback = hapticFeedback
    }
}

/// The short, restaurant-appropriate chime pattern played before a call.
nonisolated enum PromptToneStyle: String, CaseIterable, Codable, Sendable {
    case pickupChime
    case doubleChime
    case tripleChime

    var displayName: String {
        switch self {
        case .pickupChime:
            "取餐叮咚"
        case .doubleChime:
            "双铃提示"
        case .tripleChime:
            "连响提醒"
        }
    }

    var chimeCount: Int {
        switch self {
        case .pickupChime:
            1
        case .doubleChime:
            2
        case .tripleChime:
            3
        }
    }
}

nonisolated struct PromptToneSettings: Equatable, Hashable, Codable, Sendable {
    let isEnabled: Bool
    let style: PromptToneStyle
    let volume: Double
    let delay: TimeInterval

    static let `default` = PromptToneSettings(
        uncheckedIsEnabled: false,
        style: .pickupChime,
        volume: 1,
        delay: 0
    )

    init(
        isEnabled: Bool = true,
        style: PromptToneStyle = .pickupChime,
        volume: Double = 1,
        delay: TimeInterval = 0
    ) throws {
        guard (0...1).contains(volume) else {
            throw DomainValidationError.invalidRange(field: "volume")
        }
        guard delay >= 0 else {
            throw DomainValidationError.invalidRange(field: "delay")
        }

        self.init(uncheckedIsEnabled: isEnabled, style: style, volume: volume, delay: delay)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            isEnabled: container.decode(Bool.self, forKey: .isEnabled),
            style: container.decodeIfPresent(PromptToneStyle.self, forKey: .style) ?? .pickupChime,
            volume: container.decode(Double.self, forKey: .volume),
            delay: container.decode(TimeInterval.self, forKey: .delay)
        )
    }

    private init(
        uncheckedIsEnabled isEnabled: Bool,
        style: PromptToneStyle,
        volume: Double,
        delay: TimeInterval
    ) {
        self.isEnabled = isEnabled
        self.style = style
        self.volume = volume
        self.delay = delay
    }
}

nonisolated enum ActiveSpeechPolicy: String, CaseIterable, Codable, Sendable {
    case interruptCurrent
    case queueNext
    case ignoreNewCall
}

nonisolated struct CallingSettings: Equatable, Hashable, Codable, Sendable {
    let activeSpeechPolicy: ActiveSpeechPolicy
    let defaultRepeatCount: Int
    let repeatDelay: TimeInterval

    static let `default` = CallingSettings(
        uncheckedActiveSpeechPolicy: .queueNext,
        defaultRepeatCount: 0,
        repeatDelay: 0
    )

    init(
        activeSpeechPolicy: ActiveSpeechPolicy = .queueNext,
        defaultRepeatCount: Int,
        repeatDelay: TimeInterval
    ) throws {
        guard (0...5).contains(defaultRepeatCount) else {
            throw DomainValidationError.invalidRange(field: "defaultRepeatCount")
        }
        guard repeatDelay >= 0 else {
            throw DomainValidationError.invalidRange(field: "repeatDelay")
        }

        self.init(
            uncheckedActiveSpeechPolicy: activeSpeechPolicy,
            defaultRepeatCount: defaultRepeatCount,
            repeatDelay: repeatDelay
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            activeSpeechPolicy: container.decode(ActiveSpeechPolicy.self, forKey: .activeSpeechPolicy),
            defaultRepeatCount: container.decode(Int.self, forKey: .defaultRepeatCount),
            repeatDelay: container.decode(TimeInterval.self, forKey: .repeatDelay)
        )
    }

    private init(
        uncheckedActiveSpeechPolicy activeSpeechPolicy: ActiveSpeechPolicy,
        defaultRepeatCount: Int,
        repeatDelay: TimeInterval
    ) {
        self.activeSpeechPolicy = activeSpeechPolicy
        self.defaultRepeatCount = defaultRepeatCount
        self.repeatDelay = repeatDelay
    }
}

nonisolated struct HistorySettings: Equatable, Hashable, Codable, Sendable {
    let retentionDays: Int
    let maximumRecordCount: Int

    static let `default` = HistorySettings(uncheckedRetentionDays: 730, maximumRecordCount: 20_000)

    init(retentionDays: Int, maximumRecordCount: Int) throws {
        guard retentionDays >= 0 else {
            throw DomainValidationError.invalidRange(field: "retentionDays")
        }
        guard maximumRecordCount >= 0 else {
            throw DomainValidationError.invalidRange(field: "maximumRecordCount")
        }

        self.init(uncheckedRetentionDays: retentionDays, maximumRecordCount: maximumRecordCount)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            retentionDays: container.decode(Int.self, forKey: .retentionDays),
            maximumRecordCount: container.decode(Int.self, forKey: .maximumRecordCount)
        )
    }

    private init(uncheckedRetentionDays retentionDays: Int, maximumRecordCount: Int) {
        self.retentionDays = retentionDays
        self.maximumRecordCount = maximumRecordCount
    }
}

/// The app-wide color scheme override. `system` follows the device setting.
nonisolated enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark
}

nonisolated struct DisplaySettings: Equatable, Hashable, Codable, Sendable {
    let recentCallCount: Int
    let appearance: AppearanceMode
    let restaurantTitle: String
    /// Whether calling tiles show their detail text under the number. When
    /// off, tiles show only the number so a board reads as a clean grid.
    let showsActionDetail: Bool

    static let defaultRestaurantTitle = "美味餐厅"
    static let `default` = DisplaySettings(
        uncheckedRecentCallCount: 6,
        appearance: .system,
        restaurantTitle: defaultRestaurantTitle,
        showsActionDetail: true
    )

    init(
        recentCallCount: Int,
        appearance: AppearanceMode = .system,
        restaurantTitle: String = DisplaySettings.defaultRestaurantTitle,
        showsActionDetail: Bool = true
    ) throws {
        guard (0...10).contains(recentCallCount) else {
            throw DomainValidationError.invalidRange(field: "recentCallCount")
        }
        let normalizedRestaurantTitle = restaurantTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedRestaurantTitle.isEmpty else {
            throw DomainValidationError.emptyText(field: "restaurantTitle")
        }
        guard (1...24).contains(normalizedRestaurantTitle.count) else {
            throw DomainValidationError.invalidRange(field: "restaurantTitle")
        }

        self.init(
            uncheckedRecentCallCount: recentCallCount,
            appearance: appearance,
            restaurantTitle: normalizedRestaurantTitle,
            showsActionDetail: showsActionDetail
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Payloads written before these display options existed have no
        // corresponding key, so decoding falls back to their defaults.
        try self.init(
            recentCallCount: container.decode(Int.self, forKey: .recentCallCount),
            appearance: container.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system,
            restaurantTitle: container.decodeIfPresent(String.self, forKey: .restaurantTitle)
                ?? Self.defaultRestaurantTitle,
            showsActionDetail: container.decodeIfPresent(Bool.self, forKey: .showsActionDetail) ?? true
        )
    }

    private init(
        uncheckedRecentCallCount recentCallCount: Int,
        appearance: AppearanceMode,
        restaurantTitle: String,
        showsActionDetail: Bool
    ) {
        self.recentCallCount = recentCallCount
        self.appearance = appearance
        self.restaurantTitle = restaurantTitle
        self.showsActionDetail = showsActionDetail
    }
}

nonisolated struct CallDeskSettings: Equatable, Hashable, Codable, Sendable {
    let voice: VoiceSettings
    let promptTone: PromptToneSettings
    let calling: CallingSettings
    let history: HistorySettings
    let display: DisplaySettings

    static let `default` = CallDeskSettings(
        voice: .default,
        promptTone: .default,
        calling: .default,
        history: .default,
        display: .default
    )

    init(
        voice: VoiceSettings = .default,
        promptTone: PromptToneSettings = .default,
        calling: CallingSettings = .default,
        history: HistorySettings = .default,
        display: DisplaySettings = .default
    ) {
        self.voice = voice
        self.promptTone = promptTone
        self.calling = calling
        self.history = history
        self.display = display
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            voice: try container.decode(VoiceSettings.self, forKey: .voice),
            promptTone: try container.decode(PromptToneSettings.self, forKey: .promptTone),
            calling: try container.decode(CallingSettings.self, forKey: .calling),
            history: try container.decode(HistorySettings.self, forKey: .history),
            display: try container.decode(DisplaySettings.self, forKey: .display)
        )
    }
}
