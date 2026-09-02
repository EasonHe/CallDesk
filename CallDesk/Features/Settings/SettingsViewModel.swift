import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    /// The sample sentence spoken when auditioning a voice. Announcements
    /// are Chinese-only, so the sample stays Chinese on every device.
    static let voicePreviewSampleText = "请 A102 号，到 3 号柜台"

    @Published private(set) var settings: CallDeskSettings
    /// The output route announcements currently play through; updates
    /// live when the system route changes.
    @Published private(set) var audioRoute: AudioRouteDescription
    /// Whether an external (second) display is currently connected.
    @Published private(set) var isExternalDisplayConnected: Bool
    /// Whether a voice preview is currently playing. The Settings view uses
    /// this to drive the preview button's loading indicator so the tap
    /// always gets visible feedback.
    @Published private(set) var isPreviewingVoice: Bool = false
    @Published private(set) var isPreviewingPromptTone: Bool = false
    /// The Chinese voices installed on this device, best first.
    let voiceOptions: [SpeechVoiceOption]

    /// The composite audio clip store used to resolve bundled and
    /// user-imported clips. Surfaced so the settings screen can hand it
    /// to the audio-clip manager.
    let audioClips: any AudioClipStoring
    /// The pack store. Surfaced so the settings screen can hand it to the
    /// audio-clip manager alongside `audioClips`.
    let audioPacks: any AudioPackStoring

    private let store: any SettingsStore
    private let voicePreview: any VoicePreviewPlaying
    private let promptTonePreview: any PromptTonePreviewPlaying
    private var routeSubscription: AnyCancellable?
    private var displaySubscription: AnyCancellable?

    init(
        store: any SettingsStore,
        audioEnvironment: any AudioEnvironmentMonitoring = FixedAudioEnvironmentMonitor(),
        externalDisplay: any ExternalDisplayMonitoring = FixedExternalDisplayMonitor(),
        voiceProvider: any SpeechVoiceProviding = FixedSpeechVoiceProvider(),
        voicePreview: any VoicePreviewPlaying = SilentVoicePreviewPlayer(),
        promptTonePreview: any PromptTonePreviewPlaying = SilentPromptTonePreviewPlayer(),
        audioClips: any AudioClipStoring = FileSystemAudioClipStore(),
        audioPacks: any AudioPackStoring = FileSystemAudioPackStore()
    ) {
        self.store = store
        self.settings = store.load()
        self.audioRoute = audioEnvironment.currentRoute
        self.isExternalDisplayConnected = externalDisplay.isConnected
        self.voiceOptions = voiceProvider.chineseVoices()
        self.voicePreview = voicePreview
        self.promptTonePreview = promptTonePreview
        self.audioClips = audioClips
        self.audioPacks = audioPacks
        routeSubscription = audioEnvironment.routePublisher
            .sink { [weak self] route in
                self?.audioRoute = route
            }
        displaySubscription = externalDisplay.isConnectedPublisher
            .sink { [weak self] isConnected in
                self?.isExternalDisplayConnected = isConnected
            }
    }

    convenience init(dependencies: AppDependencies) {
        self.init(
            store: dependencies.settingsStore,
            audioEnvironment: dependencies.audioEnvironment,
            externalDisplay: dependencies.externalDisplay,
            voiceProvider: MatchaVoiceProvider(),
            voicePreview: SpeechVoicePreviewPlayer(),
            promptTonePreview: PromptTonePreviewPlayer(),
            audioClips: dependencies.audioClips,
            audioPacks: dependencies.audioPacks
        )
    }

    /// The stored voice pick, or `nil` (automatic) when the stored voice is
    /// no longer installed on this device.
    var selectedVoiceIdentifier: String? {
        guard let identifier = settings.voice.voiceIdentifier,
              voiceOptions.contains(where: { $0.id == identifier }) else {
            return nil
        }
        return identifier
    }

    // MARK: - Voice

    func setVoiceIdentifier(_ identifier: String?) {
        updateVoice { current in
            try VoiceSettings(
                localeIdentifier: current.localeIdentifier,
                voiceIdentifier: identifier,
                rate: current.rate,
                pitchMultiplier: current.pitchMultiplier,
                volume: current.volume,
                softness: current.softness,
                noiseScale: current.noiseScale,
                hapticFeedback: current.hapticFeedback
            )
        }
    }

    /// Speaks the sample sentence with the currently configured voice.
    /// Returns when playback finishes (or fails) so the caller can drive
    /// a loading indicator for the full duration.
    func previewVoice() async {
        isPreviewingVoice = true
        defer { isPreviewingVoice = false }
        await voicePreview.preview(Self.voicePreviewSampleText, voice: settings.voice)
    }

    func setVoiceRate(_ rate: Double) {
        updateVoice { current in
            try VoiceSettings(
                localeIdentifier: current.localeIdentifier,
                voiceIdentifier: current.voiceIdentifier,
                rate: rate,
                pitchMultiplier: current.pitchMultiplier,
                volume: current.volume,
                softness: current.softness,
                noiseScale: current.noiseScale,
                hapticFeedback: current.hapticFeedback
            )
        }
    }

    func setVoicePitchMultiplier(_ pitchMultiplier: Double) {
        updateVoice { current in
            try VoiceSettings(
                localeIdentifier: current.localeIdentifier,
                voiceIdentifier: current.voiceIdentifier,
                rate: current.rate,
                pitchMultiplier: pitchMultiplier,
                volume: current.volume,
                softness: current.softness,
                noiseScale: current.noiseScale,
                hapticFeedback: current.hapticFeedback
            )
        }
    }

    func setVoiceVolume(_ volume: Double) {
        updateVoice { current in
            try VoiceSettings(
                localeIdentifier: current.localeIdentifier,
                voiceIdentifier: current.voiceIdentifier,
                rate: current.rate,
                pitchMultiplier: current.pitchMultiplier,
                volume: volume,
                softness: current.softness,
                noiseScale: current.noiseScale,
                hapticFeedback: current.hapticFeedback
            )
        }
    }

    func setVoiceSoftness(_ softness: Double) {
        updateVoice { current in
            try VoiceSettings(
                localeIdentifier: current.localeIdentifier,
                voiceIdentifier: current.voiceIdentifier,
                rate: current.rate,
                pitchMultiplier: current.pitchMultiplier,
                volume: current.volume,
                softness: softness,
                noiseScale: current.noiseScale,
                hapticFeedback: current.hapticFeedback
            )
        }
    }

    func setVoiceNoiseScale(_ noiseScale: Double) {
        updateVoice { current in
            try VoiceSettings(
                localeIdentifier: current.localeIdentifier,
                voiceIdentifier: current.voiceIdentifier,
                rate: current.rate,
                pitchMultiplier: current.pitchMultiplier,
                volume: current.volume,
                softness: current.softness,
                noiseScale: noiseScale,
                hapticFeedback: current.hapticFeedback
            )
        }
        Task { await MatchaSynthesizer.shared.setNoiseScale(noiseScale) }
    }

    func setVoiceHapticFeedback(_ isEnabled: Bool) {
        updateVoice { current in
            try VoiceSettings(
                localeIdentifier: current.localeIdentifier,
                voiceIdentifier: current.voiceIdentifier,
                rate: current.rate,
                pitchMultiplier: current.pitchMultiplier,
                volume: current.volume,
                softness: current.softness,
                noiseScale: current.noiseScale,
                hapticFeedback: isEnabled
            )
        }
    }

    // MARK: - Prompt tone

    func setPromptToneEnabled(_ isEnabled: Bool) {
        updatePromptTone { current in
            try PromptToneSettings(
                isEnabled: isEnabled,
                style: current.style,
                volume: current.volume,
                delay: current.delay
            )
        }
    }

    func setPromptToneStyle(_ style: PromptToneStyle) {
        updatePromptTone { current in
            try PromptToneSettings(
                isEnabled: current.isEnabled,
                style: style,
                volume: current.volume,
                delay: current.delay
            )
        }
    }

    func previewPromptTone() async {
        guard !isPreviewingPromptTone else {
            return
        }
        isPreviewingPromptTone = true
        defer { isPreviewingPromptTone = false }
        await promptTonePreview.preview(settings.promptTone)
    }

    func setPromptToneVolume(_ volume: Double) {
        updatePromptTone { current in
            try PromptToneSettings(
                isEnabled: current.isEnabled,
                style: current.style,
                volume: volume,
                delay: current.delay
            )
        }
    }

    func setPromptToneDelay(_ delay: TimeInterval) {
        updatePromptTone { current in
            try PromptToneSettings(
                isEnabled: current.isEnabled,
                style: current.style,
                volume: current.volume,
                delay: delay
            )
        }
    }

    // MARK: - Calling

    func setActiveSpeechPolicy(_ policy: ActiveSpeechPolicy) {
        updateCalling { current in
            try CallingSettings(
                activeSpeechPolicy: policy,
                defaultRepeatCount: current.defaultRepeatCount,
                repeatDelay: current.repeatDelay
            )
        }
    }

    func setDefaultRepeatCount(_ count: Int) {
        updateCalling { current in
            try CallingSettings(
                activeSpeechPolicy: current.activeSpeechPolicy,
                defaultRepeatCount: count,
                repeatDelay: current.repeatDelay
            )
        }
    }

    func setRepeatDelay(_ delay: TimeInterval) {
        updateCalling { current in
            try CallingSettings(
                activeSpeechPolicy: current.activeSpeechPolicy,
                defaultRepeatCount: current.defaultRepeatCount,
                repeatDelay: delay
            )
        }
    }

    // MARK: - History and display

    func setRetentionDays(_ days: Int) {
        updateHistory { current in
            try HistorySettings(retentionDays: days, maximumRecordCount: current.maximumRecordCount)
        }
    }

    func setMaximumRecordCount(_ count: Int) {
        updateHistory { current in
            try HistorySettings(retentionDays: current.retentionDays, maximumRecordCount: count)
        }
    }

    func setRecentCallCount(_ count: Int) {
        guard let display = try? DisplaySettings(
            recentCallCount: count,
            appearance: settings.display.appearance,
            restaurantTitle: settings.display.restaurantTitle,
            showsActionDetail: settings.display.showsActionDetail
        ) else {
            return
        }
        apply(settings(replacingDisplay: display))
    }

    func setShowsActionDetail(_ showsDetail: Bool) {
        guard let display = try? DisplaySettings(
            recentCallCount: settings.display.recentCallCount,
            appearance: settings.display.appearance,
            restaurantTitle: settings.display.restaurantTitle,
            showsActionDetail: showsDetail
        ) else {
            return
        }
        apply(settings(replacingDisplay: display))
    }

    func setAppearance(_ appearance: AppearanceMode) {
        guard let display = try? DisplaySettings(
            recentCallCount: settings.display.recentCallCount,
            appearance: appearance,
            restaurantTitle: settings.display.restaurantTitle,
            showsActionDetail: settings.display.showsActionDetail
        ) else {
            return
        }
        apply(settings(replacingDisplay: display))
    }

    func setRestaurantTitle(_ title: String) {
        guard let display = try? DisplaySettings(
            recentCallCount: settings.display.recentCallCount,
            appearance: settings.display.appearance,
            restaurantTitle: title,
            showsActionDetail: settings.display.showsActionDetail
        ) else {
            return
        }
        apply(settings(replacingDisplay: display))
    }

    // MARK: - Reset

    func restoreDefaults() {
        store.reset()
        settings = store.load()
    }

    // MARK: - Private

    private func updateVoice(_ make: (VoiceSettings) throws -> VoiceSettings) {
        guard let voice = try? make(settings.voice) else {
            return
        }
        apply(
            CallDeskSettings(
                voice: voice,
                promptTone: settings.promptTone,
                calling: settings.calling,
                history: settings.history,
                display: settings.display
            )
        )
    }

    private func updatePromptTone(_ make: (PromptToneSettings) throws -> PromptToneSettings) {
        guard let promptTone = try? make(settings.promptTone) else {
            return
        }
        apply(
            CallDeskSettings(
                voice: settings.voice,
                promptTone: promptTone,
                calling: settings.calling,
                history: settings.history,
                display: settings.display
            )
        )
    }

    private func updateCalling(_ make: (CallingSettings) throws -> CallingSettings) {
        guard let calling = try? make(settings.calling) else {
            return
        }
        apply(
            CallDeskSettings(
                voice: settings.voice,
                promptTone: settings.promptTone,
                calling: calling,
                history: settings.history,
                display: settings.display
            )
        )
    }

    private func updateHistory(_ make: (HistorySettings) throws -> HistorySettings) {
        guard let history = try? make(settings.history) else {
            return
        }
        apply(
            CallDeskSettings(
                voice: settings.voice,
                promptTone: settings.promptTone,
                calling: settings.calling,
                history: history,
                display: settings.display
            )
        )
    }

    private func settings(replacingDisplay display: DisplaySettings) -> CallDeskSettings {
        CallDeskSettings(
            voice: settings.voice,
            promptTone: settings.promptTone,
            calling: settings.calling,
            history: settings.history,
            display: display
        )
    }

    /// Every change is written through immediately so it survives restarts.
    private func apply(_ newSettings: CallDeskSettings) {
        settings = newSettings
        store.save(newSettings)
    }
}
