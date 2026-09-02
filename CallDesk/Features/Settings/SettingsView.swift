import SwiftUI

struct SettingsView: View {
    /// Editing bounds mirror the validation ranges in `CallDeskSettings`.
    private enum EditingLimits {
        static let rateRange = 0.0...1.0
        static let pitchRange = 0.5...2.0
        static let volumeRange = 0.0...1.0
        static let softnessRange = 0.0...1.0
        static let noiseScaleRange = 0.1...0.7
        static let delayRange = 0.0...10.0
        static let delayStep = 0.5
        static let repeatCountRange = 0...5
        static let retentionDaysRange = 0...730
        static let retentionDaysStep = 5
        static let maximumRecordsRange = 0...50_000
        static let maximumRecordsStep = 500
        static let recentCallCountRange = 0...10
    }

    @StateObject private var viewModel: SettingsViewModel
    @State private var isRestoreDialogPresented = false

    init(dependencies: AppDependencies) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(dependencies: dependencies))
    }

    var body: some View {
        List {
            voiceSection
            promptToneSection
            callingSection
            displaySection
            historySection
            audioOutputSection
            audioClipsSection
            externalDisplaySection
            dataAboutSection
        }
        .navigationTitle(AppTab.settings.title)
    }

    private var voiceSection: some View {
        Section {
            Picker("语音模型", selection: voiceIdentifierBinding) {
                Text("自动（最佳质量）").tag(String?.none)
                ForEach(viewModel.voiceOptions) { option in
                    Text(voiceDisplayName(for: option)).tag(String?.some(option.id))
                }
            }
            Button {
                Task { await viewModel.previewVoice() }
            } label: {
                HStack {
                    Label(
                        viewModel.isPreviewingVoice ? "播放中…" : "试听语音",
                        systemImage: viewModel.isPreviewingVoice ? "speaker.wave.2" : "play.circle"
                    )
                    if viewModel.isPreviewingVoice {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(viewModel.isPreviewingVoice)
            sliderRow(
                "语速",
                value: voiceRateBinding,
                in: EditingLimits.rateRange,
                display: Text(viewModel.settings.voice.rate, format: .percent.precision(.fractionLength(0)))
            )
            sliderRow(
                "音高",
                value: voicePitchBinding,
                in: EditingLimits.pitchRange,
                display: Text(viewModel.settings.voice.pitchMultiplier, format: .number.precision(.fractionLength(1)))
            )
            sliderRow(
                "音量",
                value: voiceVolumeBinding,
                in: EditingLimits.volumeRange,
                display: Text(viewModel.settings.voice.volume, format: .percent.precision(.fractionLength(0)))
            )
            sliderRow(
                "柔和度",
                value: voiceSoftnessBinding,
                in: EditingLimits.softnessRange,
                display: Text(viewModel.settings.voice.softness, format: .percent.precision(.fractionLength(0)))
            )
            sliderRow(
                "自然度",
                value: voiceNoiseScaleBinding,
                in: EditingLimits.noiseScaleRange,
                display: Text(viewModel.settings.voice.noiseScale, format: .number.precision(.fractionLength(1)))
            )
            if HapticFeedbackSupport.isAvailable {
                Toggle("触屏震动", isOn: voiceHapticFeedbackBinding)
            } else {
                LabeledContent("触屏震动") {
                    Text("此 iPad 不支持")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("语音", systemImage: "waveform")
        } footer: {
            Text("播报使用 App 内置的天然中文语音，完全离线可用。柔和度降低明亮的高频让声音更温暖；自然度增加气息与人类变化。")
        }
    }

    private func voiceDisplayName(for option: SpeechVoiceOption) -> String {
        // The speaker ID is stored as "zf_NNN"; the numeric portion becomes
        // a stable, user-facing tag so every voice has a unique label even
        // when several voices share a descriptive name (e.g. many "活泼").
        let number = Int(option.id.dropFirst("zf_".count)) ?? 0
        let tag = String(format: "#%02d", number)
        return "\(tag) · \(option.name) · \(qualityName(for: option.quality))"
    }

    private func qualityName(for quality: SpeechVoiceQuality) -> String {
        switch quality {
        case .premium:
            return String(localized: "优质")
        case .enhanced:
            return String(localized: "增强")
        case .standard:
            return String(localized: "标准")
        }
    }

    private var promptToneSection: some View {
        Section {
            Toggle("提示音", isOn: promptToneEnabledBinding)
            Picker("提示音类型", selection: promptToneStyleBinding) {
                ForEach(PromptToneStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            Button {
                Task { await viewModel.previewPromptTone() }
            } label: {
                Label(
                    viewModel.isPreviewingPromptTone ? "正在试听…" : "试听提示音",
                    systemImage: viewModel.isPreviewingPromptTone ? "speaker.wave.2" : "play.circle"
                )
            }
            .disabled(viewModel.isPreviewingPromptTone)
            sliderRow(
                "音量",
                value: promptToneVolumeBinding,
                in: EditingLimits.volumeRange,
                display: Text(viewModel.settings.promptTone.volume, format: .percent.precision(.fractionLength(0)))
            )
            .disabled(!viewModel.settings.promptTone.isEnabled)
            Stepper(
                value: promptToneDelayBinding,
                in: EditingLimits.delayRange,
                step: EditingLimits.delayStep
            ) {
                LabeledContent("播报间隔") {
                    Text(secondsText(viewModel.settings.promptTone.delay))
                }
            }
            .disabled(!viewModel.settings.promptTone.isEnabled)
        } header: {
            Label("提示音", systemImage: "bell")
        }
    }

    private var callingSection: some View {
        Section {
            Picker("并发播报策略", selection: activeSpeechPolicyBinding) {
                ForEach(ActiveSpeechPolicy.allCases, id: \.self) { policy in
                    Text(policyTitle(policy)).tag(policy)
                }
            }
            Stepper(
                value: repeatCountBinding,
                in: EditingLimits.repeatCountRange
            ) {
                LabeledContent("重复次数") {
                    Text(viewModel.settings.calling.defaultRepeatCount, format: .number)
                }
            }
            Stepper(
                value: repeatDelayBinding,
                in: EditingLimits.delayRange,
                step: EditingLimits.delayStep
            ) {
                LabeledContent("重复间隔") {
                    Text(secondsText(viewModel.settings.calling.repeatDelay))
                }
            }
        } header: {
            Label("呼叫", systemImage: "megaphone")
        }
    }

    private var displaySection: some View {
        Section {
            Picker("外观", selection: appearanceBinding) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(appearanceTitle(mode)).tag(mode)
                }
            }
            TextField("外接屏标题", text: restaurantTitleBinding)
            Stepper(
                value: recentCallCountBinding,
                in: EditingLimits.recentCallCountRange
            ) {
                LabeledContent("最近呼叫数") {
                    Text(viewModel.settings.display.recentCallCount, format: .number)
                }
            }
            Toggle("显示播报详情", isOn: showsActionDetailBinding)
        } header: {
            Label("显示", systemImage: "rectangle.on.rectangle")
        }
    }

    private var historySection: some View {
        Section {
            Stepper(
                value: retentionDaysBinding,
                in: EditingLimits.retentionDaysRange,
                step: EditingLimits.retentionDaysStep
            ) {
                LabeledContent("保留天数") {
                    Text(viewModel.settings.history.retentionDays, format: .number)
                }
            }
            Stepper(
                value: maximumRecordsBinding,
                in: EditingLimits.maximumRecordsRange,
                step: EditingLimits.maximumRecordsStep
            ) {
                LabeledContent("最大记录数") {
                    Text(viewModel.settings.history.maximumRecordCount, format: .number)
                }
            }
        } header: {
            Label("历史", systemImage: "clock.arrow.circlepath")
        }
    }

    private var audioOutputSection: some View {
        Section {
            LabeledContent("当前输出") {
                Text(viewModel.audioRoute.name)
            }
            LabeledContent("输出类型") {
                Text(routeTypeTitle(viewModel.audioRoute.type))
            }
            #if canImport(AVKit)
            LabeledContent("切换输出") {
                AudioRoutePickerView()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(Text("切换输出"))
            }
            #endif
        } header: {
            Label("音频输出", systemImage: "airplayaudio")
        } footer: {
            Text("播报跟随系统选择的输出设备。")
        }
    }

    private var externalDisplaySection: some View {
        Section {
            LabeledContent("状态") {
                if viewModel.isExternalDisplayConnected {
                    Label("已连接", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("未连接")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("外接显示", systemImage: "display")
        } footer: {
            Text("用数据线或隔空播放连接屏幕后，叫号内容会自动显示。")
        }
    }

    private var audioClipsSection: some View {
        Section {
            NavigationLink {
                AudioClipManagerView(
                    viewModel: AudioClipManagerViewModel(
                        audioClips: viewModel.audioClips,
                        audioPacks: viewModel.audioPacks
                    )
                )
            } label: {
                Label("音频素材", systemImage: "waveform")
            }
        } footer: {
            Text("管理叫号使用的内置与导入音频。")
        }
    }

    private var dataAboutSection: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                Label("关于 CallDesk", systemImage: "info.circle")
            }
            Button("恢复默认设置", role: .destructive) {
                isRestoreDialogPresented = true
            }
            .confirmationDialog(
                "将所有设置恢复为默认值？",
                isPresented: $isRestoreDialogPresented,
                titleVisibility: .visible
            ) {
                Button("恢复", role: .destructive) {
                    viewModel.restoreDefaults()
                }
                Button("取消", role: .cancel) {}
            }
        } header: {
            Label("数据与关于", systemImage: "info.circle")
        }
    }

    // MARK: - Row helpers

    private func sliderRow(
        _ titleKey: LocalizedStringKey,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        display: Text
    ) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(titleKey) {
                display
            }
            Slider(value: value, in: range) {
                Text(titleKey)
            }
        }
    }

    private func secondsText(_ seconds: TimeInterval) -> String {
        Measurement(value: seconds, unit: UnitDuration.seconds)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }

    private func policyTitle(_ policy: ActiveSpeechPolicy) -> LocalizedStringKey {
        switch policy {
        case .interruptCurrent:
            return "中断当前"
        case .queueNext:
            return "排队播报"
        case .ignoreNewCall:
            return "忽略新呼叫"
        }
    }

    private func appearanceTitle(_ mode: AppearanceMode) -> LocalizedStringKey {
        switch mode {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }

    private func routeTypeTitle(_ type: AudioRouteType) -> LocalizedStringKey {
        switch type {
        case .builtInSpeaker:
            return "内置扬声器"
        case .receiver:
            return "听筒"
        case .headphones:
            return "耳机"
        case .bluetooth:
            return "蓝牙"
        case .airPlay:
            return "隔空播放"
        case .wired:
            return "有线"
        case .unknown:
            return "未知"
        }
    }

    // MARK: - Bindings

    private var voiceIdentifierBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedVoiceIdentifier },
            set: { viewModel.setVoiceIdentifier($0) }
        )
    }

    private var voiceRateBinding: Binding<Double> {
        Binding(
            get: { viewModel.settings.voice.rate },
            set: { viewModel.setVoiceRate($0) }
        )
    }

    private var voicePitchBinding: Binding<Double> {
        Binding(
            get: { viewModel.settings.voice.pitchMultiplier },
            set: { viewModel.setVoicePitchMultiplier($0) }
        )
    }

    private var voiceVolumeBinding: Binding<Double> {
        Binding(
            get: { viewModel.settings.voice.volume },
            set: { viewModel.setVoiceVolume($0) }
        )
    }

    private var voiceSoftnessBinding: Binding<Double> {
        Binding(
            get: { viewModel.settings.voice.softness },
            set: { viewModel.setVoiceSoftness($0) }
        )
    }

    private var voiceNoiseScaleBinding: Binding<Double> {
        Binding(
            get: { viewModel.settings.voice.noiseScale },
            set: { viewModel.setVoiceNoiseScale($0) }
        )
    }

    private var voiceHapticFeedbackBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.voice.hapticFeedback },
            set: { viewModel.setVoiceHapticFeedback($0) }
        )
    }

    private var promptToneEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.promptTone.isEnabled },
            set: { viewModel.setPromptToneEnabled($0) }
        )
    }

    private var promptToneStyleBinding: Binding<PromptToneStyle> {
        Binding(
            get: { viewModel.settings.promptTone.style },
            set: { viewModel.setPromptToneStyle($0) }
        )
    }

    private var promptToneVolumeBinding: Binding<Double> {
        Binding(
            get: { viewModel.settings.promptTone.volume },
            set: { viewModel.setPromptToneVolume($0) }
        )
    }

    private var promptToneDelayBinding: Binding<Double> {
        Binding(
            get: { viewModel.settings.promptTone.delay },
            set: { viewModel.setPromptToneDelay($0) }
        )
    }

    private var activeSpeechPolicyBinding: Binding<ActiveSpeechPolicy> {
        Binding(
            get: { viewModel.settings.calling.activeSpeechPolicy },
            set: { viewModel.setActiveSpeechPolicy($0) }
        )
    }

    private var repeatCountBinding: Binding<Int> {
        Binding(
            get: { viewModel.settings.calling.defaultRepeatCount },
            set: { viewModel.setDefaultRepeatCount($0) }
        )
    }

    private var repeatDelayBinding: Binding<Double> {
        Binding(
            get: { viewModel.settings.calling.repeatDelay },
            set: { viewModel.setRepeatDelay($0) }
        )
    }

    private var retentionDaysBinding: Binding<Int> {
        Binding(
            get: { viewModel.settings.history.retentionDays },
            set: { viewModel.setRetentionDays($0) }
        )
    }

    private var maximumRecordsBinding: Binding<Int> {
        Binding(
            get: { viewModel.settings.history.maximumRecordCount },
            set: { viewModel.setMaximumRecordCount($0) }
        )
    }

    private var recentCallCountBinding: Binding<Int> {
        Binding(
            get: { viewModel.settings.display.recentCallCount },
            set: { viewModel.setRecentCallCount($0) }
        )
    }

    private var showsActionDetailBinding: Binding<Bool> {
        Binding(
            get: { viewModel.settings.display.showsActionDetail },
            set: { viewModel.setShowsActionDetail($0) }
        )
    }

    private var restaurantTitleBinding: Binding<String> {
        Binding(
            get: { viewModel.settings.display.restaurantTitle },
            set: { viewModel.setRestaurantTitle($0) }
        )
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { viewModel.settings.display.appearance },
            set: { viewModel.setAppearance($0) }
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView(dependencies: .preview())
    }
}
