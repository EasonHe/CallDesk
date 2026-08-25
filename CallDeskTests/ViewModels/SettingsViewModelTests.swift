import Foundation
import Testing
@testable import CallDesk

@MainActor
@Suite("Settings view model")
struct SettingsViewModelTests {
    private func makeViewModel(
        settings: CallDeskSettings = .default,
        audioEnvironment: FixedAudioEnvironmentMonitor = FixedAudioEnvironmentMonitor(),
        externalDisplay: FixedExternalDisplayMonitor = FixedExternalDisplayMonitor(),
        voiceProvider: FixedSpeechVoiceProvider = FixedSpeechVoiceProvider(),
        voicePreview: any VoicePreviewPlaying = SilentVoicePreviewPlayer(),
        promptTonePreview: any PromptTonePreviewPlaying = SilentPromptTonePreviewPlayer()
    ) -> (SettingsViewModel, InMemorySettingsStore) {
        let store = InMemorySettingsStore(settings: settings)
        return (
            SettingsViewModel(
                store: store,
                audioEnvironment: audioEnvironment,
                externalDisplay: externalDisplay,
                voiceProvider: voiceProvider,
                voicePreview: voicePreview,
                promptTonePreview: promptTonePreview
            ),
            store
        )
    }

    @Test("The stored settings are loaded on creation")
    func storedSettingsAreLoadedOnCreation() throws {
        let settings = CallDeskSettings(
            voice: try VoiceSettings(
                localeIdentifier: "zh-CN",
                rate: 0.4,
                pitchMultiplier: 1,
                volume: 0.8
            )
        )
        let (viewModel, _) = makeViewModel(settings: settings)

        #expect(viewModel.settings == settings)
        #expect(viewModel.settings.voice.localeIdentifier == "zh-CN")
        #expect(viewModel.settings.promptTone == .default)
    }

    @Test("Voice changes are applied and saved immediately")
    func voiceChangesAreAppliedAndSavedImmediately() {
        let (viewModel, store) = makeViewModel()

        viewModel.setVoiceIdentifier("voice.tingting.enhanced")
        viewModel.setVoiceRate(0.7)
        viewModel.setVoicePitchMultiplier(1.5)
        viewModel.setVoiceVolume(0.6)
        viewModel.setVoiceSoftness(0.5)
        viewModel.setVoiceNoiseScale(0.6)

        let saved = store.load().voice
        #expect(saved.voiceIdentifier == "voice.tingting.enhanced")
        #expect(saved.rate == 0.7)
        #expect(saved.pitchMultiplier == 1.5)
        #expect(saved.volume == 0.6)
        #expect(saved.softness == 0.5)
        #expect(saved.noiseScale == 0.6)
        #expect(viewModel.settings.voice == saved)
    }

    @Test("Changing the voice preserves the existing voice tuning")
    func changingVoicePreservesExistingVoiceTuning() throws {
        let settings = CallDeskSettings(
            voice: try VoiceSettings(
                localeIdentifier: "zh-CN",
                rate: 0.7,
                pitchMultiplier: 1.2,
                volume: 0.8,
                softness: 0.6,
                noiseScale: 0.5,
                hapticFeedback: false
            )
        )
        let (viewModel, store) = makeViewModel(settings: settings)

        viewModel.setVoiceIdentifier("voice.tingting.enhanced")

        let saved = store.load().voice
        #expect(saved.voiceIdentifier == "voice.tingting.enhanced")
        #expect(saved.softness == 0.6)
        #expect(saved.noiseScale == 0.5)
        #expect(!saved.hapticFeedback)
    }

    @Test("Changing softness preserves disabled haptic feedback")
    func changingSoftnessPreservesDisabledHapticFeedback() throws {
        let settings = CallDeskSettings(
            voice: try VoiceSettings(
                localeIdentifier: "zh-CN",
                rate: 0.5,
                pitchMultiplier: 1,
                volume: 1,
                softness: 0.3,
                noiseScale: 0.4,
                hapticFeedback: false
            )
        )
        let (viewModel, store) = makeViewModel(settings: settings)

        viewModel.setVoiceSoftness(0.6)

        let saved = store.load().voice
        #expect(saved.softness == 0.6)
        #expect(!saved.hapticFeedback)
    }

    @Test("Out-of-range naturalness values are rejected")
    func outOfRangeNoiseScaleIsRejected() {
        let (viewModel, store) = makeViewModel()

        viewModel.setVoiceNoiseScale(0.9)
        viewModel.setVoiceNoiseScale(0.05)

        let saved = store.load().voice
        #expect(saved.noiseScale == VoiceSettings.default.noiseScale)
    }

    @Test("Prompt tone changes are applied and saved immediately")
    func promptToneChangesAreAppliedAndSavedImmediately() {
        let (viewModel, store) = makeViewModel()

        viewModel.setPromptToneEnabled(false)
        viewModel.setPromptToneVolume(0.3)
        viewModel.setPromptToneDelay(1.5)

        let saved = store.load().promptTone
        #expect(!saved.isEnabled)
        #expect(saved.volume == 0.3)
        #expect(saved.delay == 1.5)
    }

    @Test("Prompt-tone selection is applied and saved immediately")
    func promptToneStyleChangesAreAppliedAndSavedImmediately() {
        let (viewModel, store) = makeViewModel()

        viewModel.setPromptToneStyle(.doubleChime)

        #expect(viewModel.settings.promptTone.style == .doubleChime)
        #expect(store.load().promptTone.style == .doubleChime)
    }

    @Test("Prompt-tone preview uses the selected tone and volume")
    func promptTonePreviewUsesTheSelectedStyle() async {
        let preview = RecordingPromptTonePlayer()
        let (viewModel, _) = makeViewModel(promptTonePreview: preview)
        viewModel.setPromptToneStyle(.tripleChime)
        viewModel.setPromptToneVolume(0.6)

        await viewModel.previewPromptTone()

        #expect(preview.playedStyles == [.tripleChime])
        #expect(preview.playedVolumes == [0.6])
    }

    @Test("Calling changes are applied and saved immediately")
    func callingChangesAreAppliedAndSavedImmediately() {
        let (viewModel, store) = makeViewModel()

        viewModel.setActiveSpeechPolicy(.queueNext)
        viewModel.setDefaultRepeatCount(3)
        viewModel.setRepeatDelay(2)

        let saved = store.load().calling
        #expect(saved.activeSpeechPolicy == .queueNext)
        #expect(saved.defaultRepeatCount == 3)
        #expect(saved.repeatDelay == 2)
    }

    @Test("History and recent call count changes are applied and saved immediately")
    func historyAndRecentCallCountChangesAreAppliedAndSavedImmediately() {
        let (viewModel, store) = makeViewModel()

        viewModel.setRetentionDays(30)
        viewModel.setMaximumRecordCount(1_000)
        viewModel.setRecentCallCount(8)

        let saved = store.load()
        #expect(saved.history.retentionDays == 30)
        #expect(saved.history.maximumRecordCount == 1_000)
        #expect(saved.display.recentCallCount == 8)
    }

    @Test("Changing the restaurant title saves immediately")
    func changingRestaurantTitleSavesImmediately() {
        let (viewModel, store) = makeViewModel()

        viewModel.setRestaurantTitle("幸福餐厅")

        #expect(viewModel.settings.display.restaurantTitle == "幸福餐厅")
        #expect(store.load().display.restaurantTitle == "幸福餐厅")
    }

    @Test("An invalid restaurant title keeps the existing display value")
    func invalidRestaurantTitleKeepsExistingDisplayValue() {
        let (viewModel, store) = makeViewModel()
        viewModel.setRestaurantTitle("幸福餐厅")

        viewModel.setRestaurantTitle(" \n ")

        #expect(viewModel.settings.display.restaurantTitle == "幸福餐厅")
        #expect(store.load().display.restaurantTitle == "幸福餐厅")
    }

    @Test("Appearance changes are applied and saved immediately")
    func appearanceChangesAreAppliedAndSavedImmediately() {
        let (viewModel, store) = makeViewModel()

        viewModel.setAppearance(.dark)

        #expect(viewModel.settings.display.appearance == .dark)
        #expect(store.load().display.appearance == .dark)
    }

    @Test("Toggling action detail is applied and saved immediately")
    func togglingActionDetailIsAppliedAndSavedImmediately() {
        let (viewModel, store) = makeViewModel()

        viewModel.setShowsActionDetail(false)

        #expect(!viewModel.settings.display.showsActionDetail)
        #expect(!store.load().display.showsActionDetail)
    }

    @Test("Display changes preserve the other display values")
    func displayChangesPreserveTheOtherDisplayValues() {
        let (viewModel, store) = makeViewModel()
        viewModel.setAppearance(.light)
        viewModel.setRecentCallCount(7)
        viewModel.setRestaurantTitle("幸福餐厅")
        viewModel.setShowsActionDetail(false)

        let saved = store.load().display
        #expect(saved.recentCallCount == 7)
        #expect(saved.appearance == .light)
        #expect(saved.restaurantTitle == "幸福餐厅")
        #expect(!saved.showsActionDetail)

        viewModel.setRecentCallCount(8)
        viewModel.setAppearance(.dark)
        viewModel.setShowsActionDetail(true)

        #expect(store.load().display.recentCallCount == 8)
        #expect(store.load().display.restaurantTitle == "幸福餐厅")
        #expect(store.load().display.showsActionDetail)
    }

    @Test("Invalid values are ignored and nothing is saved")
    func invalidValuesAreIgnored() {
        let (viewModel, store) = makeViewModel()

        viewModel.setVoiceRate(1.5)
        viewModel.setVoicePitchMultiplier(3)
        viewModel.setDefaultRepeatCount(9)
        viewModel.setRecentCallCount(-1)

        #expect(viewModel.settings == .default)
        #expect(store.load() == .default)
    }

    @Test("Restoring defaults resets the store and the published settings")
    func restoringDefaultsResetsStoreAndPublishedSettings() {
        let (viewModel, store) = makeViewModel()
        viewModel.setVoiceIdentifier("voice.tingting.enhanced")
        viewModel.setRetentionDays(10)

        viewModel.restoreDefaults()

        #expect(viewModel.settings == .default)
        #expect(store.load() == .default)
    }

    @Test("Voice options come from the provider ranked best first")
    func voiceOptionsComeFromProviderRankedBestFirst() {
        let provider = FixedSpeechVoiceProvider(voices: [
            SpeechVoiceOption(id: "cantonese.premium", name: "Sinji", quality: .premium, languageCode: "zh-HK"),
            SpeechVoiceOption(id: "tingting.standard", name: "Tingting", quality: .standard, languageCode: "zh-CN"),
            SpeechVoiceOption(id: "tingting.enhanced", name: "Tingting", quality: .enhanced, languageCode: "zh-CN")
        ])
        let (viewModel, _) = makeViewModel(voiceProvider: provider)

        #expect(viewModel.voiceOptions.map(\.id) == [
            "tingting.enhanced", "tingting.standard", "cantonese.premium"
        ])
    }

    @Test("The selected voice falls back to automatic when it is not installed")
    func selectedVoiceFallsBackToAutomaticWhenNotInstalled() throws {
        let settings = CallDeskSettings(
            voice: try VoiceSettings(
                localeIdentifier: "zh-CN",
                voiceIdentifier: "tingting.enhanced",
                rate: 0.5,
                pitchMultiplier: 1,
                volume: 1
            )
        )
        let installed = FixedSpeechVoiceProvider(voices: [
            SpeechVoiceOption(id: "tingting.enhanced", name: "Tingting", quality: .enhanced, languageCode: "zh-CN")
        ])
        let (matchingViewModel, _) = makeViewModel(settings: settings, voiceProvider: installed)
        let (missingViewModel, _) = makeViewModel(settings: settings)

        #expect(matchingViewModel.selectedVoiceIdentifier == "tingting.enhanced")
        #expect(missingViewModel.selectedVoiceIdentifier == nil)
    }

    @Test("Previewing speaks the sample sentence with the current voice")
    func previewSpeaksSampleWithCurrentVoice() async {
        let preview = RecordingVoicePreviewPlayer()
        let (viewModel, _) = makeViewModel(voicePreview: preview)
        viewModel.setVoiceRate(0.7)

        await viewModel.previewVoice()

        #expect(preview.previews.count == 1)
        #expect(preview.previews.first?.text == SettingsViewModel.voicePreviewSampleText)
        #expect(preview.previews.first?.voice == viewModel.settings.voice)
    }

    @Test("The external display state mirrors the monitor on creation")
    func externalDisplayStateMirrorsMonitorOnCreation() {
        let (disconnected, _) = makeViewModel()
        #expect(!disconnected.isExternalDisplayConnected)

        let (connected, _) = makeViewModel(externalDisplay: FixedExternalDisplayMonitor(isConnected: true))
        #expect(connected.isExternalDisplayConnected)
    }

    @Test("Display connection changes update the published state")
    func displayConnectionChangesUpdatePublishedState() {
        let externalDisplay = FixedExternalDisplayMonitor()
        let (viewModel, _) = makeViewModel(externalDisplay: externalDisplay)
        #expect(!viewModel.isExternalDisplayConnected)

        externalDisplay.setConnected(true)
        #expect(viewModel.isExternalDisplayConnected)

        externalDisplay.setConnected(false)
        #expect(!viewModel.isExternalDisplayConnected)
    }

    @Test("The audio route mirrors the monitor on creation")
    func audioRouteMirrorsMonitorOnCreation() throws {
        let route = try AudioRouteDescription(type: .bluetooth, name: "Conference Speaker")
        let (viewModel, _) = makeViewModel(audioEnvironment: FixedAudioEnvironmentMonitor(route: route))

        #expect(viewModel.audioRoute == route)
    }

    @Test("Route changes update the published audio route")
    func routeChangesUpdatePublishedAudioRoute() throws {
        let audioEnvironment = FixedAudioEnvironmentMonitor()
        let (viewModel, _) = makeViewModel(audioEnvironment: audioEnvironment)
        #expect(viewModel.audioRoute == .defaultSpeaker)

        let airPlay = try AudioRouteDescription(type: .airPlay, name: "Lobby TV")
        audioEnvironment.updateRoute(airPlay)

        #expect(viewModel.audioRoute == airPlay)
    }
}

/// Records preview requests instead of speaking them.
@MainActor
private final class RecordingVoicePreviewPlayer: VoicePreviewPlaying {
    private(set) var previews: [(text: String, voice: VoiceSettings)] = []

    func preview(_ text: String, voice: VoiceSettings) async {
        previews.append((text: text, voice: voice))
    }
}

@MainActor
private final class RecordingPromptTonePlayer: PromptTonePreviewPlaying {
    private let lock = NSLock()
    private var styleStorage: [PromptToneStyle] = []
    private var volumeStorage: [Double] = []

    var playedStyles: [PromptToneStyle] {
        lock.withLock { styleStorage }
    }

    var playedVolumes: [Double] {
        lock.withLock { volumeStorage }
    }

    func preview(_ tone: PromptToneSettings) async {
        lock.withLock {
            styleStorage.append(tone.style)
            volumeStorage.append(tone.volume)
        }
    }
}
