import AppKit
import SwiftUI

enum VideoInspectorTab: String, CaseIterable, Identifiable {
    case episodes
    case video
    case audio
    case subtitles

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .episodes: "Episodes"
        case .video: "Video"
        case .audio: "Audio"
        case .subtitles: "Subtitles"
        }
    }

    var systemName: String {
        switch self {
        case .episodes: "list.number"
        case .video: "film"
        case .audio: "waveform"
        case .subtitles: "captions.bubble"
        }
    }

    var nativeSegmentTitle: String {
        switch self {
        case .episodes: String(localized: "Episodes")
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        case .subtitles: String(localized: "Subtitles")
        }
    }
}

struct VideoInspectorView: View {
    static let minimumWidth: CGFloat = 300
    static let idealWidth: CGFloat = 340
    static let maximumWidth: CGFloat = 400

    @Environment(UserConfig.self) private var userConfig
    @Binding var selectedTab: VideoInspectorTab
    @State private var speedInputText = ""
    @State private var subtitleTimingInputText = ""
    @State private var isShowingJimakuBrowser = false
    @State private var isShowingAJATTBrowser = false

    let state: VideoInspectorState
    let playlist: VideoPlaylist
    let currentURL: URL?
    let currentTitle: String?
    let primarySubtitleName: String?
    let isPrimarySubtitleActive: Bool
    let remoteSubtitleOptions: [RemoteVideoSubtitleOption]
    let selectedRemoteSubtitleID: String?
    let selectedJimakuSubtitleID: String?
    let selectedJimakuSubtitleName: String?
    let selectedAJATTSubtitleID: String?
    let selectedAJATTSubtitleName: String?
    let remoteQualityOptions: [RemoteVideoQualityOption]
    let selectedRemoteQualityID: String?

    var onSelectEpisode: (URL) -> Void
    var onSetSpeed: (Double) -> Void
    var onSetSubtitleDelay: (TimeInterval) -> Void
    var onSetAudioDelay: (TimeInterval) -> Void
    var onSetLoopMode: (VideoLoopMode) -> Void
    var onSetABLoopStart: () -> Void
    var onSetABLoopEnd: () -> Void
    var onClearABLoop: () -> Void
    var onSetAspectRatio: (VideoAspectRatio) -> Void
    var onRotateClockwise: () -> Void
    var onSetVideoShaderPreset: (VideoShaderPreset) -> Void
    var onSelectTrack: (VideoTrackType, Int?) -> Void
    var onSelectRemoteSubtitle: (RemoteVideoSubtitleOption) -> Void
    var onSelectJimakuSubtitle: (JimakuSubtitleFile) -> Void
    var onSelectAJATTSubtitle: (AJATTSubtitleFile) -> Void
    var onSelectExternalSubtitle: () -> Void
    var onSelectRemoteQuality: (RemoteVideoQualityOption) -> Void
    var onOpenSubtitle: () -> Void
    var onClearPrimarySubtitle: () -> Void
    var onOpenTranscript: () -> Void
    var onClose: () -> Void

    private let speedChoices = VideoPlaybackSpeed.presetChoices
    private let speedRows = [
        [0.25, 0.5, 1, 1.5],
        [2, 3, 4, 5],
    ]
    private static let subtitleTimingLargeStepMilliseconds = 1_000
    private static let subtitleTimingSmallStepMilliseconds = 50

    var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker

            Divider()
                .opacity(0.5)

            ScrollView {
                tabContent
                    .padding(12)
            }
            .scrollIndicators(.hidden)
        }
        .frame(minWidth: Self.minimumWidth, idealWidth: Self.idealWidth, maxWidth: Self.maximumWidth)
        .modifier(VideoInspectorGlassSurface(cornerRadius: 24))
        .onAppear {
            synchronizeSpeedInput()
            synchronizeSubtitleTimingInput()
        }
        .onChange(of: state.speed) { _, _ in
            synchronizeSpeedInput()
        }
        .onChange(of: state.subtitleDelay) { _, _ in
            synchronizeSubtitleTimingInput()
        }
        .sheet(isPresented: $isShowingJimakuBrowser) {
            JimakuSubtitleBrowserView(
                suggestion: subtitleCatalogSuggestion,
                selectedFileID: selectedJimakuSubtitleID,
                onSelectFile: onSelectJimakuSubtitle
            )
        }
        .sheet(isPresented: $isShowingAJATTBrowser) {
            AJATTSubtitleBrowserView(
                suggestion: subtitleCatalogSuggestion,
                selectedFileID: selectedAJATTSubtitleID,
                onSelectFile: onSelectAJATTSubtitle
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Inspector", systemImage: "sidebar.trailing")
                .font(.headline)
                .labelStyle(.titleAndIcon)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.glass)
            .clipShape(Circle())
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var tabPicker: some View {
        VideoInspectorSegmentedPicker(
            selection: $selectedTab,
            values: VideoInspectorTab.allCases,
            minSegmentWidth: 62,
            fillsWidth: true
        ) { tab in
            Label(tab.nativeSegmentTitle, systemImage: tab.systemName)
                .labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .episodes:
            episodesTab
        case .video:
            videoTab
        case .audio:
            audioTab
        case .subtitles:
            subtitlesTab
        }
    }

    private var episodesTab: some View {
        inspectorSection("Episodes", systemName: "list.number") {
            if playlist.items.isEmpty {
                emptyRow("No episodes")
            } else {
                ForEach(playlist.items, id: \.standardizedFileURL) { url in
                    selectionRow(
                        title: url.lastPathComponent,
                        subtitle: nil,
                        isSelected: url.standardizedFileURL == currentURL?.standardizedFileURL
                    ) {
                        onSelectEpisode(url)
                    }
                }
            }
        }
    }

    private var videoTab: some View {
        VStack(spacing: 12) {
            inspectorSection("Playback Speed", systemName: "speedometer") {
                ForEach(speedRows, id: \.self) { row in
                    VideoInspectorSegmentedPicker(
                        selection: Binding<Double>(
                            get: { selectedPresetSpeed },
                            set: { setSpeed($0) }
                        ),
                        values: row,
                        minSegmentWidth: 44,
                        fillsWidth: true
                    ) { speed in
                        Text(Self.speedLabel(speed))
                    }
                }

                HStack(spacing: 10) {
                    Slider(
                        value: Binding<Double>(
                            get: { sliderSpeed },
                            set: { setSpeed($0) }
                        ),
                        in: VideoPlaybackSpeed.customInputLowerBound...VideoPlaybackSpeed.maximum,
                        step: VideoPlaybackSpeed.customStep
                    )

                    HStack(spacing: 3) {
                        TextField("Custom", text: $speedInputText)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .frame(width: 48)
                            .onSubmit {
                                commitSpeedInput()
                            }
                        Text(verbatim: "x")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .modifier(VideoInspectorTextFieldGlassSurface(cornerRadius: 10))
                }
            }

            if !remoteQualityOptions.isEmpty {
                inspectorSection("YouTube Quality", systemName: "rectangle.badge.checkmark") {
                    ForEach(remoteQualityOptions, id: \.id) { option in
                        selectionRow(
                            title: "\(option.height)p",
                            subtitle: nil,
                            isSelected: option.id == selectedRemoteQualityID
                        ) {
                            onSelectRemoteQuality(option)
                        }
                    }
                }
            }

            videoEnhancementSection

            trackSection(
                title: "Video Track",
                systemName: "film",
                type: .video,
                allowsOff: false
            )

            inspectorSection("Aspect Ratio", systemName: "rectangle.inset.filled") {
                VideoInspectorSegmentedPicker(
                    selection: Binding<VideoAspectRatio>(
                        get: { state.aspectRatio },
                        set: { onSetAspectRatio($0) }
                    ),
                    values: VideoAspectRatio.allCases,
                    minSegmentWidth: 48,
                    fillsWidth: true
                ) { aspectRatio in
                    Text(aspectRatio.title)
                }

                Button {
                    onRotateClockwise()
                } label: {
                    Label("Rotate Clockwise", systemImage: "rotate.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }

            inspectorSection("Loop", systemName: "repeat") {
                VideoInspectorSegmentedPicker(
                    selection: Binding<Bool>(
                        get: { state.loopMode == .file },
                        set: { onSetLoopMode($0 ? .file : .none) }
                    ),
                    values: [false, true],
                    minSegmentWidth: 100,
                    fillsWidth: true
                ) { isLooping in
                    Text(isLooping ? "Loop File" : "Off")
                }

                HStack(spacing: 8) {
                    Button("Set A Point", action: onSetABLoopStart)
                    Button("Set B Point", action: onSetABLoopEnd)
                    Button("Clear", action: onClearABLoop)
                        .disabled(state.abLoop == nil)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var videoEnhancementSection: some View {
        inspectorSection("Video Enhancement", systemName: "sparkles.tv") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 8) {
                    Toggle("Hardware Decoding", isOn: videoHardwareDecodingEnabled)
                    Toggle("Deinterlace", isOn: videoDeinterlacingEnabled)
                    Toggle("HDR", isOn: videoHDREnhancementEnabled)
                }
                .toggleStyle(.switch)

                Divider()
                    .opacity(0.45)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Anime4K Upscaling")
                        .font(.caption.weight(.medium))
                    VideoAnime4KPresetControl(
                        minimumPickerWidth: 170,
                        onActivate: onSetVideoShaderPreset
                    )
                }

                Divider()
                    .opacity(0.45)

                ForEach(VideoEqualizerAdjustment.allCases, id: \.self) { adjustment in
                    videoEqualizerSlider(
                        adjustment,
                        value: videoEqualizerBinding(adjustment)
                    )
                }
            }
        }
    }

    private var audioTab: some View {
        VStack(spacing: 12) {
            trackSection(
                title: "Audio Track",
                systemName: "waveform",
                type: .audio,
                allowsOff: true
            )
            timingSection(
                title: "Audio Timing",
                systemName: "waveform.badge.clock",
                value: state.audioDelay,
                onEarlier: { onSetAudioDelay(max(state.audioDelay - 0.5, -30)) },
                onReset: { onSetAudioDelay(0) },
                onLater: { onSetAudioDelay(min(state.audioDelay + 0.5, 30)) }
            )
        }
    }

    private var subtitlesTab: some View {
        VStack(spacing: 12) {
            if !remoteSubtitleOptions.isEmpty {
                inspectorSection("YouTube Subtitles", systemName: "captions.bubble.fill") {
                    ForEach(remoteSubtitleOptions, id: \.id) { option in
                        selectionRow(
                            title: remoteSubtitleTitle(option),
                            subtitle: option.language,
                            isSelected: option.id == selectedRemoteSubtitleID
                        ) {
                            onSelectRemoteSubtitle(option)
                        }
                    }
                }
            }

            inspectorSection("External Subtitles", systemName: "captions.bubble") {
                Button {
                    isShowingJimakuBrowser = true
                } label: {
                    Label("Get Subtitles (Jimaku)", systemImage: "icloud.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Button {
                    isShowingAJATTBrowser = true
                } label: {
                    Label("Get Subtitles (AJATT)", systemImage: "icloud.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Button {
                    onOpenSubtitle()
                } label: {
                    Label("Open Subtitles", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                if let primarySubtitleName {
                    selectionRow(
                        title: primarySubtitleName,
                        subtitle: primarySubtitleSourceName,
                        isSelected: isPrimarySubtitleActive,
                        action: {
                            if !isPrimarySubtitleActive {
                                onSelectExternalSubtitle()
                            }
                        }
                    )
                }

            }

            trackSection(
                title: "Subtitle Track",
                systemName: "captions.bubble",
                type: .subtitle,
                allowsOff: true,
                selectingSubtitleTrackClearsExternal: true
            )

            subtitleTimingSection

            subtitleAppearanceSection

            subtitleMaskSection

            inspectorSection("Transcript", systemName: "text.alignleft") {
                Button {
                    onOpenTranscript()
                } label: {
                    Label("Open Transcript", systemImage: "text.alignleft")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var subtitleCatalogSuggestion: JimakuMediaSuggestion {
        JimakuMediaSuggestion(
            sourceIdentifier: currentURL?.absoluteString ?? currentTitle ?? "video",
            mediaTitle: currentTitle ?? currentURL?.deletingPathExtension().lastPathComponent ?? ""
        )
    }

    private var primarySubtitleSourceName: String {
        if selectedAJATTSubtitleName != nil {
            return "AJATT"
        } else if selectedJimakuSubtitleName != nil {
            return "Jimaku"
        } else {
            return String(localized: "Primary subtitle")
        }
    }

    private var subtitleAppearanceSection: some View {
        inspectorSection("Subtitle Appearance", systemName: "textformat.size") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Respect ASS subtitle styles", isOn: Binding(
                    get: { userConfig.videoRespectASSStyle },
                    set: { userConfig.videoRespectASSStyle = $0 }
                ))
                HStack(spacing: 12) {
                    Text("Subtitle Font")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 12)
                    NativeGlassMenuPicker(
                        selection: subtitleFontFamily,
                        values: [""] + Self.subtitleFontFamilies,
                        minWidth: 170
                    ) { family in
                        if family.isEmpty {
                            Text("System Default")
                        } else {
                            Text(verbatim: family)
                        }
                    }
                    .frame(maxWidth: 220)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Subtitle Size")
                        Spacer()
                        Text("\(Int(userConfig.videoSubtitleFontSize)) px")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    Slider(
                        value: subtitleFontSize,
                        in: 12...72,
                        step: 1
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Subtitle Weight")
                        Spacer()
                        Stepper(
                            "\(userConfig.videoSubtitleFontWeight)",
                            value: subtitleFontWeight,
                            in: 100...900,
                            step: 100
                        )
                        .labelsHidden()
                    }
                    .font(.caption)
                }

                HStack(spacing: 12) {
                    Text("Edge Style")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 12)
                    NativeGlassMenuPicker(
                        selection: subtitleEdgeStyle,
                        values: VideoSubtitleEdgeStyle.allCases,
                        minWidth: 150
                    ) { style in
                        Text(style.localizedTitle)
                    }
                    .frame(maxWidth: 200)
                }

                subtitleAppearanceSlider(
                    title: "Edge Strength",
                    value: "\(Int((userConfig.videoSubtitleEdgeStrength * 100).rounded()))%",
                    binding: subtitleEdgeStrength,
                    range: 0...1,
                    step: 0.05
                )
                .disabled(userConfig.videoSubtitleEdgeStyle == .off)

                subtitleAppearanceSlider(
                    title: "Background Opacity",
                    value: "\(Int(userConfig.videoSubtitleBackgroundOpacity * 100))%",
                    binding: subtitleBackgroundOpacity,
                    range: 0...1,
                    step: 0.05
                )
                .disabled(userConfig.videoSubtitleBackgroundDisabled)

                Toggle("No Background", isOn: subtitleBackgroundDisabled)
                    .toggleStyle(.switch)
                    .font(.caption)

                subtitlePositionSlider(
                    title: "Vertical Position",
                    binding: subtitleVerticalPosition
                )

                ColorPicker("Subtitle Color", selection: subtitleColor)
                    .font(.caption)

                ColorPicker("Lookup Highlight Color", selection: subtitleLookupHighlightColor)
                    .font(.caption)

                ColorPicker("Lookup Highlight Text Color", selection: subtitleLookupHighlightTextColor)
                    .font(.caption)

                Button {
                    userConfig.resetVideoSubtitleAppearance()
                } label: {
                    Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var subtitleMaskSection: some View {
        inspectorSection("Subtitle Mask", systemName: "eye.slash") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Mask subtitles until hover", isOn: subtitleMaskEnabled)
                    .toggleStyle(.switch)

                VideoInspectorSegmentedPicker(
                    selection: subtitleMaskMode,
                    values: VideoSubtitleMaskMode.allCases,
                    minSegmentWidth: 96,
                    fillsWidth: true
                ) { mode in
                    Text(subtitleMaskModeTitle(mode))
                }
                .disabled(!userConfig.videoSubtitleMaskEnabled)

                if userConfig.videoSubtitleMaskMode == .blur {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Blur Radius")
                            Spacer()
                            Text("\(Int(userConfig.videoSubtitleMaskBlurRadius)) px")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                        Slider(
                            value: subtitleMaskBlurRadius,
                            in: 0...20,
                            step: 1
                        )
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Hidden Opacity")
                            Spacer()
                            Text("\(Int(userConfig.videoSubtitleMaskHiddenOpacity * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                        Slider(
                            value: subtitleMaskHiddenOpacity,
                            in: 0...1,
                            step: 0.05
                        )
                    }
                }
            }
        }
    }

    private var subtitleTimingSection: some View {
        inspectorSection("Subtitle Timing", systemName: "captions.bubble") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Positive values delay subtitles; negative values show subtitles earlier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding<Double>(
                        get: { Double(VideoSubtitleTiming.clampedSliderMilliseconds(subtitleTimingMilliseconds)) },
                        set: { applySubtitleTimingMilliseconds(Int($0.rounded())) }
                    ),
                    in: Double(VideoSubtitleTiming.sliderMilliseconds.lowerBound)...Double(VideoSubtitleTiming.sliderMilliseconds.upperBound),
                    step: Double(Self.subtitleTimingSmallStepMilliseconds)
                )

                HStack(spacing: 12) {
                    Button {
                        let current = subtitleTimingMilliseconds
                        applySubtitleTimingMilliseconds(current - Self.subtitleTimingLargeStepMilliseconds)
                    } label: {
                        Image(systemName: "chevron.left.2")
                            .frame(width: 30, height: 30)
                    }
                    .help("Back 1000 ms")

                    Button {
                        let current = subtitleTimingMilliseconds
                        applySubtitleTimingMilliseconds(current - Self.subtitleTimingSmallStepMilliseconds)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 30, height: 30)
                    }
                    .help("Back 50 ms")

                    Spacer()

                    Text(subtitleTimingValueText)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(minWidth: 86)

                    Spacer()

                    Button {
                        let current = subtitleTimingMilliseconds
                        applySubtitleTimingMilliseconds(current + Self.subtitleTimingSmallStepMilliseconds)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 30, height: 30)
                    }
                    .help("Forward 50 ms")

                    Button {
                        let current = subtitleTimingMilliseconds
                        applySubtitleTimingMilliseconds(current + Self.subtitleTimingLargeStepMilliseconds)
                    } label: {
                        Image(systemName: "chevron.right.2")
                            .frame(width: 30, height: 30)
                    }
                    .help("Forward 1000 ms")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Offset (ms)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)

                    HStack(spacing: 8) {
                        TextField("Offset", text: $subtitleTimingInputText)
                            .textFieldStyle(.plain)
                            .font(.title3.monospacedDigit())
                            .onSubmit {
                                commitSubtitleTimingInput()
                            }

                        Image(systemName: "keyboard")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .modifier(VideoInspectorTextFieldGlassSurface(cornerRadius: 12))
                }
            }
        }
    }

    private func trackSection(
        title: LocalizedStringKey,
        systemName: String,
        type: VideoTrackType,
        allowsOff: Bool,
        selectingSubtitleTrackClearsExternal: Bool = false
    ) -> some View {
        let tracks = state.tracks.filter { $0.type == type }
        return inspectorSection(title, systemName: systemName) {
            if allowsOff {
                selectionRow(
                    title: "Off",
                    subtitle: nil,
                    isSelected: !tracks.contains(where: \.isSelected)
                        && (type != .subtitle || (!isPrimarySubtitleActive && selectedRemoteSubtitleID == nil))
                ) {
                    onSelectTrack(type, nil)
                }
            }

            if tracks.isEmpty {
                emptyRow("No tracks")
            } else {
                ForEach(tracks) { track in
                    selectionRow(
                        title: track.displayName,
                        subtitle: track.codec,
                        isSelected: track.isSelected
                    ) {
                        onSelectTrack(type, track.id)
                    }
                }
            }
        }
    }

    private func timingSection(
        title: LocalizedStringKey,
        systemName: String,
        value: TimeInterval,
        onEarlier: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onLater: @escaping () -> Void
    ) -> some View {
        inspectorSection(title, systemName: systemName) {
            HStack(spacing: 8) {
                Button("-0.5 s", action: onEarlier)
                Spacer()
                Text(String(format: "%+.1f s", value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("+0.5 s", action: onLater)
            }
            .buttonStyle(.glass)

            Button("Reset", action: onReset)
                .buttonStyle(.glass)
        }
    }

    private var subtitleMaskEnabled: Binding<Bool> {
        Binding(
            get: { userConfig.videoSubtitleMaskEnabled },
            set: { userConfig.videoSubtitleMaskEnabled = $0 }
        )
    }

    private var subtitleFontFamily: Binding<String> {
        Binding(
            get: { userConfig.videoSubtitleFontFamily },
            set: { userConfig.videoSubtitleFontFamily = $0 }
        )
    }

    private var subtitleFontSize: Binding<Double> {
        Binding(
            get: { userConfig.videoSubtitleFontSize },
            set: { userConfig.videoSubtitleFontSize = $0 }
        )
    }

    private var subtitleFontWeight: Binding<Int> {
        Binding(
            get: { userConfig.videoSubtitleFontWeight },
            set: { userConfig.videoSubtitleFontWeight = $0 }
        )
    }

    private var subtitleEdgeStyle: Binding<VideoSubtitleEdgeStyle> {
        Binding(
            get: { userConfig.videoSubtitleEdgeStyle },
            set: { userConfig.videoSubtitleEdgeStyle = $0 }
        )
    }

    private var subtitleEdgeStrength: Binding<Double> {
        Binding(
            get: { userConfig.videoSubtitleEdgeStrength },
            set: { userConfig.videoSubtitleEdgeStrength = $0 }
        )
    }

    private var subtitleBackgroundOpacity: Binding<Double> {
        Binding(
            get: { userConfig.videoSubtitleBackgroundOpacity },
            set: { userConfig.videoSubtitleBackgroundOpacity = $0 }
        )
    }

    private var subtitleBackgroundDisabled: Binding<Bool> {
        Binding(
            get: { userConfig.videoSubtitleBackgroundDisabled },
            set: { userConfig.videoSubtitleBackgroundDisabled = $0 }
        )
    }

    private var subtitleVerticalPosition: Binding<Double> {
        Binding(
            get: { userConfig.videoSubtitleVerticalPosition },
            set: { userConfig.videoSubtitleVerticalPosition = $0 }
        )
    }

    private var subtitleColor: Binding<Color> {
        Binding(
            get: { userConfig.videoSubtitleColor },
            set: { userConfig.videoSubtitleColor = $0 }
        )
    }

    private var subtitleLookupHighlightColor: Binding<Color> {
        Binding(
            get: { userConfig.videoSubtitleLookupHighlightColor },
            set: { userConfig.videoSubtitleLookupHighlightColor = $0 }
        )
    }

    private var subtitleLookupHighlightTextColor: Binding<Color> {
        Binding(
            get: { userConfig.videoSubtitleLookupHighlightTextColor },
            set: { userConfig.videoSubtitleLookupHighlightTextColor = $0 }
        )
    }

    private var subtitleMaskMode: Binding<VideoSubtitleMaskMode> {
        Binding(
            get: { userConfig.videoSubtitleMaskMode },
            set: { userConfig.videoSubtitleMaskMode = $0 }
        )
    }

    private var subtitleMaskBlurRadius: Binding<Double> {
        Binding(
            get: { userConfig.videoSubtitleMaskBlurRadius },
            set: { userConfig.videoSubtitleMaskBlurRadius = $0 }
        )
    }

    private var subtitleMaskHiddenOpacity: Binding<Double> {
        Binding(
            get: { userConfig.videoSubtitleMaskHiddenOpacity },
            set: { userConfig.videoSubtitleMaskHiddenOpacity = $0 }
        )
    }

    private func subtitleMaskModeTitle(_ mode: VideoSubtitleMaskMode) -> String {
        switch mode {
        case .blur:
            String(localized: "Blur")
        case .transparent:
            String(localized: "Transparent")
        }
    }

    private var videoHardwareDecodingEnabled: Binding<Bool> {
        Binding(
            get: { userConfig.videoHardwareDecodingEnabled },
            set: { userConfig.videoHardwareDecodingEnabled = $0 }
        )
    }

    private var videoDeinterlacingEnabled: Binding<Bool> {
        Binding(
            get: { userConfig.videoDeinterlacingEnabled },
            set: { userConfig.videoDeinterlacingEnabled = $0 }
        )
    }

    private var videoHDREnhancementEnabled: Binding<Bool> {
        Binding(
            get: { userConfig.videoHDREnhancementEnabled },
            set: { userConfig.videoHDREnhancementEnabled = $0 }
        )
    }

    private func videoEqualizerBinding(
        _ adjustment: VideoEqualizerAdjustment
    ) -> Binding<Double> {
        Binding(
            get: {
                switch adjustment {
                case .brightness: userConfig.videoBrightness
                case .contrast: userConfig.videoContrast
                case .saturation: userConfig.videoSaturation
                case .gamma: userConfig.videoGamma
                case .hue: userConfig.videoHue
                }
            },
            set: { value in
                let normalized = VideoEqualizerAdjustment.normalized(value)
                switch adjustment {
                case .brightness: userConfig.videoBrightness = normalized
                case .contrast: userConfig.videoContrast = normalized
                case .saturation: userConfig.videoSaturation = normalized
                case .gamma: userConfig.videoGamma = normalized
                case .hue: userConfig.videoHue = normalized
                }
            }
        )
    }

    private func videoEqualizerSlider(
        _ adjustment: VideoEqualizerAdjustment,
        value: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Label(LocalizedStringKey(adjustment.title), systemImage: adjustment.systemName)
                    .labelStyle(.titleAndIcon)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)

            HStack(spacing: 8) {
                Slider(
                    value: value,
                    in: VideoEqualizerAdjustment.minimum...VideoEqualizerAdjustment.maximum,
                    step: 1
                )
                Button {
                    value.wrappedValue = VideoEqualizerAdjustment.neutral
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
                .clipShape(Circle())
                .help("Reset")
            }
        }
    }

    private func subtitleAppearanceSlider(
        title: LocalizedStringKey,
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: binding, in: range, step: step)
        }
    }

    private func subtitlePositionSlider(
        title: LocalizedStringKey,
        binding: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
            HStack(spacing: 8) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .foregroundStyle(.secondary)
                Slider(value: binding, in: VideoSubtitlePositionPolicy.range)
                    .labelsHidden()
                Image(systemName: "rectangle.bottomthird.inset.filled")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func inspectorSection<Content: View>(
        _ title: LocalizedStringKey,
        systemName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .modifier(VideoInspectorSectionGlassSurface(cornerRadius: 18))
    }

    private func selectionRow(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(VideoInspectorSelectionRowGlassSurface(isSelected: isSelected, cornerRadius: 13))
    }

    private func emptyRow(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private func remoteSubtitleTitle(_ option: RemoteVideoSubtitleOption) -> String {
        let language = Locale.current.localizedString(forLanguageCode: option.language)
            ?? option.name
        guard option.isAutomatic else { return language }
        return "\(language) · \(String(localized: "Auto-generated"))"
    }

    private static func speedLabel(_ speed: Double) -> String {
        VideoPlaybackSpeed.label(speed)
    }

    private var selectedPresetSpeed: Double {
        let normalizedSpeed = VideoPlaybackSpeed.normalized(state.speed)
        return speedChoices.first { abs($0 - normalizedSpeed) < 0.001 } ?? normalizedSpeed
    }

    private var sliderSpeed: Double {
        min(
            max(VideoPlaybackSpeed.normalized(state.speed), VideoPlaybackSpeed.customInputLowerBound),
            VideoPlaybackSpeed.maximum
        )
    }

    private func setSpeed(_ speed: Double) {
        let normalizedSpeed = VideoPlaybackSpeed.normalized(speed)
        speedInputText = VideoPlaybackSpeed.label(normalizedSpeed, includesSuffix: false)
        onSetSpeed(normalizedSpeed)
    }

    private func synchronizeSpeedInput() {
        speedInputText = VideoPlaybackSpeed.label(state.speed, includesSuffix: false)
    }

    private func commitSpeedInput() {
        let normalizedText = speedInputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let speed = Double(normalizedText) else {
            synchronizeSpeedInput()
            return
        }
        setSpeed(speed)
    }

    private var subtitleTimingMilliseconds: Int {
        Self.clampedSubtitleTimingMilliseconds(
            Int((state.subtitleDelay * 1_000).rounded())
        )
    }

    private var subtitleTimingValueText: String {
        let milliseconds = subtitleTimingMilliseconds
        return "\(milliseconds >= 0 ? "+" : "")\(milliseconds) ms"
    }

    private func applySubtitleTimingMilliseconds(_ milliseconds: Int) {
        let clampedMilliseconds = Self.clampedSubtitleTimingMilliseconds(milliseconds)
        subtitleTimingInputText = "\(clampedMilliseconds)"
        onSetSubtitleDelay(TimeInterval(clampedMilliseconds) / 1_000)
    }

    private func synchronizeSubtitleTimingInput() {
        subtitleTimingInputText = "\(subtitleTimingMilliseconds)"
    }

    private func commitSubtitleTimingInput() {
        let normalizedText = subtitleTimingInputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let milliseconds = Int(normalizedText) else {
            synchronizeSubtitleTimingInput()
            return
        }
        applySubtitleTimingMilliseconds(milliseconds)
    }

    private static func clampedSubtitleTimingMilliseconds(_ milliseconds: Int) -> Int {
        VideoSubtitleTiming.clampedMilliseconds(milliseconds)
    }

    private static let subtitleFontFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }()
}

extension VideoInspectorView: Equatable {
    static func == (lhs: VideoInspectorView, rhs: VideoInspectorView) -> Bool {
        lhs.selectedTab == rhs.selectedTab
            && lhs.state == rhs.state
            && lhs.playlist == rhs.playlist
            && lhs.currentURL?.standardizedFileURL == rhs.currentURL?.standardizedFileURL
            && lhs.currentTitle == rhs.currentTitle
            && lhs.primarySubtitleName == rhs.primarySubtitleName
            && lhs.isPrimarySubtitleActive == rhs.isPrimarySubtitleActive
            && lhs.remoteSubtitleOptions == rhs.remoteSubtitleOptions
            && lhs.selectedRemoteSubtitleID == rhs.selectedRemoteSubtitleID
            && lhs.selectedJimakuSubtitleID == rhs.selectedJimakuSubtitleID
            && lhs.selectedJimakuSubtitleName == rhs.selectedJimakuSubtitleName
            && lhs.selectedAJATTSubtitleID == rhs.selectedAJATTSubtitleID
            && lhs.selectedAJATTSubtitleName == rhs.selectedAJATTSubtitleName
            && lhs.remoteQualityOptions == rhs.remoteQualityOptions
            && lhs.selectedRemoteQualityID == rhs.selectedRemoteQualityID
    }
}

private struct VideoInspectorSegmentedPicker<SelectionValue: Hashable, SegmentLabel: View>: View {
    @Binding var selection: SelectionValue
    let values: [SelectionValue]
    var minSegmentWidth: CGFloat = 76
    var fillsWidth = false
    @ViewBuilder var label: (SelectionValue) -> SegmentLabel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.element) { index, value in
                segmentButton(value)

                if index < values.count - 1 {
                    Divider()
                        .frame(height: 16)
                        .padding(.vertical, 3)
                        .opacity(selection == value || selection == values[index + 1] ? 0 : 0.34)
                }
            }
        }
        .padding(2)
        .background(containerFill, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(containerStroke, lineWidth: 0.7)
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .fixedSize(horizontal: !fillsWidth, vertical: true)
        .animation(.smooth(duration: 0.18), value: selection)
    }

    private func segmentButton(_ value: SelectionValue) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.20)) {
                selection = value
            }
        } label: {
            label(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(minWidth: minSegmentWidth, maxWidth: fillsWidth ? .infinity : nil)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selection == value ? .primary : .secondary)
        .background {
            if selection == value {
                Capsule()
                    .fill(selectedFill)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 0.7)
                    }
            }
        }
    }

    private var containerFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.24)
    }

    private var selectedFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.44)
    }

    private var containerStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.07)
    }
}

private struct VideoInspectorGlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        GlassEffectContainer {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }

}

private struct VideoInspectorSectionGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(sectionFill, in: shape)
            .overlay {
                shape.strokeBorder(sectionStroke, lineWidth: 0.7)
            }
    }

    private var sectionFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.30)
    }

    private var sectionStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.075)
    }
}

private struct VideoInspectorSelectionRowGlassSurface: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(rowFill, in: shape)
            .overlay {
                shape.strokeBorder(rowStroke, lineWidth: 0.7)
            }
    }

    private var rowFill: Color {
        if isSelected {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.16)
        }
        return colorScheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.18)
    }

    private var rowStroke: Color {
        if isSelected {
            return Color.accentColor.opacity(0.34)
        }
        return colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.055)
    }
}

private struct VideoInspectorTextFieldGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(fieldFill, in: shape)
            .overlay {
                shape.strokeBorder(Color.accentColor.opacity(0.20), lineWidth: 0.8)
            }
    }

    private var fieldFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.34)
    }
}
