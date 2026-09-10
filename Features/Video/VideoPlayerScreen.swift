import AppKit
@preconcurrency import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let videoScreenLog = Logger(subsystem: "moe.shishamo.hoshi", category: "VideoScreen")

private nonisolated final class DroppedFileURLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }

    func urls() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
@MainActor
private final class VideoPlayerModelStore: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()

    let model = VideoPlayerViewModel(engine: MpvPlayerEngine())
}

struct VideoPlayerScreen: View {
    let isActive: Bool
    let openRequest: VideoWindowOpenRequest?
    let onConsumeOpenRequest: (UUID) -> Void
    let windowChrome: VideoWindowChromeController

    @Environment(UserConfig.self) private var userConfig
    @Environment(ShortcutManager.self) private var shortcutManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var modelStore = VideoPlayerModelStore()
    @State private var openGate = VideoWindowOpenGate()
    @State private var subtitles = VideoSubtitleController()
    @State private var lookup = VideoLookupCoordinator()
    @State private var miningHistory = VideoMiningHistoryStore()
    @State private var ambientBackdrop = VideoAmbientBackdropModel()
    @State private var profileRepository = ProfileRepository.shared
    @State private var isInspectorVisible = false
    @State private var isMiningHistoryVisible = false
    @State private var selectedStudySidebarTab: VideoStudySidebarTab = .history
    @State private var isPlaybackChromeVisible = true
    @State private var isSpeedPanelVisible = false
    @State private var isSavingScreenshot = false
    @State private var isPointerInsidePlayerSurface = true
    @State private var lastPlaybackChromePointerLocation: CGPoint?
    @State private var areSubtitlesVisible = true
    @State private var subtitleRenderingMode: VideoSubtitleRenderingMode = .overlayOnly
    @State private var lastSelectedSubtitleTrackID: Int?
    @State private var playbackChromeDragOffset: CGSize = .zero
    @State private var playbackChromeStoredOffset: CGSize = .zero
    @State private var selectedInspectorTab: VideoInspectorTab = .subtitles
    @State private var shortcutRegistrationIDs: [UUID] = []
    @State private var pendingFileImportKind: VideoFileImportKind?
    @State private var activeFileImportKind: VideoFileImportKind?
    @State private var isOpeningRemoteLink = false
    @State private var isResolvingRemoteVideo = false
    @State private var remoteVideoOpenErrorMessage: String?
    @State private var remoteVideoOpenTask: Task<Void, Never>?
    @State private var remoteVideoOpenGeneration = 0
    @State private var playbackChromeAutoHideTask: Task<Void, Never>?
    @State private var miningHistoryNotice: VideoMiningHistoryNotice?
    @State private var miningHistoryNoticeTask: Task<Void, Never>?
    @State private var miningHistoryNavigationTask: Task<Void, Never>?
    @State private var miningHistoryNavigationGeneration = 0
    @State private var videoOSD: VideoOnScreenDisplayItem?
    @State private var videoOSDTask: Task<Void, Never>?
    @State private var pendingHistoryEmbeddedSubtitleTrackID: Int?
    @State private var subtitleTrackExtractionTask: Task<Void, Never>?
    @State private var activeSubtitleTrackExtractionKey: String?
    @State private var isLoadingPrimarySubtitle = false
    @State private var primarySubtitleLoadGeneration = 0
    @State private var shouldSkipNextAutomaticSubtitleRestore = false
    @State private var remoteSubtitleLoader = RemoteSubtitleLoader()
    @State private var remoteSubtitleGeneration = 0
    @State private var selectedRemoteSubtitleID: String?
    @State private var selectedJimakuSubtitleID: String?
    @State private var selectedJimakuSubtitleName: String?
    @State private var selectedAJATTSubtitleID: String?
    @State private var selectedAJATTSubtitleName: String?
    @State private var timelinePreview: VideoTimelinePreview?
    @State private var timelinePreviewRequestedTime: TimeInterval?
    @AppStorage("videoStudySidebarWidth") private var studySidebarWidth: Double = Double(VideoMiningHistorySidebar.defaultWidth)
    @State private var studySidebarDragStartWidth: CGFloat?
    @State private var inspectorOverlayFrame: CGRect = .zero

    private static let playbackChromeEdgeInset: CGFloat = 16
    private static let inspectorOverlayTrailingInset: CGFloat = 16
    private static let inspectorOverlayVerticalInset: CGFloat = 16
    private static let minimumVideoSurfaceWidth: CGFloat = 360
    private static let videoPlayerCoordinateSpace = "video-player"
    private static let audioDelayRange: ClosedRange<TimeInterval> = -30...30

    private static let subtitleFileExtensions = ["srt", "vtt", "ass", "ssa"]

    private let subtitleTypes: [UTType] = Self.subtitleFileExtensions.compactMap {
        UTType(filenameExtension: $0)
    }

    private var model: VideoPlayerViewModel {
        modelStore.model
    }

    private var subtitleOverlayCues: [SubtitleCue] {
        switch subtitleRenderingMode {
        case .overlayOnly:
            return subtitles.currentCues
        case .preparingASS, .nativeOnly:
            return []
        case .splitASS:
            guard let primaryCueIDs = subtitles.document?.assRenderPlan?.primaryCueIDs else {
                return []
            }
            return subtitles.currentCues.filter { primaryCueIDs.contains($0.id) }
        }
    }

    var body: some View {
        lifecycleContent
    }

    private var lifecycleContent: some View {
        lifecycleFocusedContent
    }

    private var lifecycleFileImportContent: some View {
        observedContent
            .fileImporter(
                isPresented: fileImporterPresentation,
                allowedContentTypes: (pendingFileImportKind ?? activeFileImportKind)?.allowedContentTypes(
                    mediaTypes: VideoMediaTypes.contentTypes,
                    subtitleTypes: subtitleTypes
                ) ?? VideoMediaTypes.contentTypes,
                allowsMultipleSelection: false
            ) { result in
                guard let kind = activeFileImportKind ?? pendingFileImportKind else { return }
                pendingFileImportKind = nil
                activeFileImportKind = nil
                handleFileImport(result, kind: kind)
            }
            .sheet(isPresented: $isOpeningRemoteLink) {
                RemoteVideoLinkSheet { resolvedSource in
                    openRemoteLink(resolvedSource)
                }
            }
    }

    private var lifecycleActiveContent: some View {
        lifecycleFileImportContent
            .onAppear {
                synchronizePlaybackPreferences()
                miningHistory.updateLimit(userConfig.videoMiningHistoryLimit)
                installEmbeddedSubtitleHandler()
                synchronizeSelectedSubtitleTrack()
                if isActive {
                    registerKeyboardShortcuts()
                }
                schedulePlaybackChromeAutoHide()
            }
            .onChange(of: isActive, initial: true) { _, isActive in
                if isActive {
                    registerKeyboardShortcuts()
                    revealPlaybackChrome(scheduleHide: true)
                    refreshAmbientBackdrop(reason: .load)
                } else {
                    unregisterKeyboardShortcuts()
                    windowChrome.restorePlaybackCursor()
                    ambientBackdrop.suspend(clear: false)
                }
            }
    }

    private var lifecyclePreferenceContent: some View {
        lifecycleActiveContent
            .onChange(of: profileRepository.index.globalActiveProfileId) { _, _ in
                lookup.closeAll(player: model)
            }
            .onChange(of: userConfig.videoAutoPlayNext) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onChange(of: userConfig.videoRememberPlaybackPosition) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onChange(of: userConfig.videoSubtitleGapFastForwardEnabled) { _, enabled in
                model.setSubtitleGapFastForwardEnabled(enabled)
                updateSubtitleGapPlayback()
            }
            .onChange(of: userConfig.videoSubtitleGapFastForwardSpeed) { _, speed in
                model.setSubtitleGapFastForwardSpeed(speed)
                updateSubtitleGapPlayback()
            }
            .onChange(of: userConfig.videoHardwareDecodingEnabled) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onChange(of: userConfig.videoDeinterlacingEnabled) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onChange(of: userConfig.videoHDREnhancementEnabled) { _, _ in
                synchronizePlaybackPreferences()
            }
            .onChange(of: userConfig.videoShaderPreset) { _, preset in
                _ = model.setVideoShaderPreset(preset)
            }
            .onChange(of: userConfig.videoBrightness) { _, _ in
                synchronizeVideoEqualizerPreferences()
            }
            .onChange(of: userConfig.videoContrast) { _, _ in
                synchronizeVideoEqualizerPreferences()
            }
            .onChange(of: userConfig.videoSaturation) { _, _ in
                synchronizeVideoEqualizerPreferences()
            }
            .onChange(of: userConfig.videoGamma) { _, _ in
                synchronizeVideoEqualizerPreferences()
            }
            .onChange(of: userConfig.videoHue) { _, _ in
                synchronizeVideoEqualizerPreferences()
            }
            .onChange(of: userConfig.videoMiningHistoryLimit) { _, limit in
                miningHistory.updateLimit(limit)
            }
    }

    private var lifecycleExternalInputContent: some View {
        lifecyclePreferenceContent
            .onChange(of: openRequest, initial: true) { _, request in
                handleExternalOpenRequest(request)
            }
    }

    private var lifecycleChromeContent: some View {
        lifecycleExternalInputContent
            .onChange(of: isInspectorVisible) { _, inspectorVisible in
                if inspectorVisible {
                    revealPlaybackChrome(scheduleHide: false)
                } else {
                    schedulePlaybackChromeAutoHide()
                }
            }
            .onChange(of: hasActiveVideoPopup) { _, hasPopup in
                if hasPopup {
                    revealPlaybackChrome(scheduleHide: false)
                } else {
                    schedulePlaybackChromeAutoHide()
                }
            }
            .onChange(of: isSpeedPanelVisible) { _, isVisible in
                if isVisible {
                    revealPlaybackChrome(scheduleHide: false)
                } else {
                    schedulePlaybackChromeAutoHide()
                }
            }
            .onChange(of: shouldShowPlaybackChrome, initial: true) { _, isVisible in
                windowChrome.setChromeVisible(isVisible)
            }
            .onChange(of: windowChrome.pointerActivityGeneration) { _, _ in
                revealPlaybackChrome(scheduleHide: true)
            }
            .onChange(of: videoWindowAspectRatio, initial: true) { _, _ in
                synchronizeVideoWindowLayout()
            }
            .onChange(of: isMiningHistoryVisible, initial: true) { _, _ in
                synchronizeVideoWindowLayout()
            }
            .onChange(of: isMiningHistoryVisible) { _, isVisible in
                if isVisible {
                    revealPlaybackChrome(scheduleHide: false)
                } else {
                    schedulePlaybackChromeAutoHide()
                }
            }
            .onChange(of: studySidebarWidth, initial: true) { _, _ in
                synchronizeVideoWindowLayout()
            }
            .onChange(of: windowChrome.isFullScreen, initial: true) { _, isFullScreen in
                synchronizeVideoWindowLayout()
                if model.currentURL != nil {
                    revealPlaybackChrome(scheduleHide: true)
                }
                if isFullScreen {
                    ambientBackdrop.suspend(clear: false)
                } else {
                    refreshAmbientBackdrop(reason: .load)
                }
            }
            .onChange(of: windowChrome.isWindowGeometryTransitioning) { _, isTransitioning in
                if isTransitioning {
                    playbackChromeAutoHideTask?.cancel()
                    windowChrome.restorePlaybackCursor()
                    if model.currentURL != nil {
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            isPlaybackChromeVisible = true
                        }
                    }
                } else {
                    schedulePlaybackChromeAutoHide()
                }
            }
    }

    private var lifecycleModelContent: some View {
        lifecycleChromeContent
            .onChange(of: model.snapshot.tracks) { _, _ in
                restorePendingHistorySubtitleTrackIfAvailable()
                restoreRememberedSubtitleSelectionOrAutoload()
                synchronizeSelectedSubtitleTrack()
            }
            .onChange(of: model.snapshot.isLoaded) { _, isLoaded in
                guard isLoaded else { return }
                restoreRememberedSubtitleSelectionOrAutoload()
                refreshAmbientBackdrop(reason: .load)
            }
            .onChange(of: model.snapshot.isPlaying) { wasPlaying, isPlaying in
                if wasPlaying, !isPlaying {
                    refreshAmbientBackdrop(reason: .pause)
                }
                updateSubtitleGapPlayback()
            }
            .onChange(of: model.loadGeneration) { _, generation in
                ambientBackdrop.reset(for: generation)
                handleVideoLoadGeneration()
            }
    }

    private var lifecycleSceneContent: some View {
        lifecycleModelContent
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    hidePlaybackChromeForPointerExit()
                }
            }
    }

    private var lifecycleDisappearContent: some View {
        lifecycleSceneContent
            .onDisappear {
                unregisterKeyboardShortcuts()
                playbackChromeAutoHideTask?.cancel()
                windowChrome.restorePlaybackCursor()
                miningHistoryNoticeTask?.cancel()
                miningHistoryNavigationTask?.cancel()
                videoOSDTask?.cancel()
                subtitleTrackExtractionTask?.cancel()
                cancelPendingRemoteVideoOpen()
                remoteSubtitleLoader.cancelAndCleanup()
                clearTimelinePreview(clearCache: true)
                ambientBackdrop.suspend(clear: true)
                resumeVideoThumbnailsForVideoSession()
                model.engine.onEmbeddedSubtitleCuesChanged = nil
                lookup.closeAll(player: model)
                invalidatePrimarySubtitleLoad()
                _ = model.configureSubtitleRendering(.overlayOnly)
                subtitles.clear()
                model.shutdown()
            }
    }

    private var lifecycleAlertContent: some View {
        lifecycleDisappearContent
            .alert("Video Error", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    remoteVideoOpenErrorMessage
                        ?? model.errorMessage
                        ?? subtitles.errorMessage
                        ?? ""
                )
            }
    }

    private var lifecycleFocusedContent: some View {
        lifecycleAlertContent
            .focusedSceneValue(\.videoPlaybackCommandContext, videoPlaybackCommandContext)
    }

    private var observedContent: some View {
        playerSurface
            .ignoresSafeArea(.container, edges: .top)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDroppedItems(providers)
            }
            .onChange(of: model.snapshot.currentTime) { oldTime, time in
                subtitles.update(
                    time: time,
                    subtitleDelay: model.snapshot.subtitleDelay
                )
                updateSubtitleGapPlayback()
                refreshAmbientBackdrop(
                    reason: abs(time - oldTime) > 1.5 ? .seek : .playback
                )
            }
            .onChange(of: model.snapshot.subtitleDelay) { _, delay in
                subtitles.update(
                    time: model.snapshot.currentTime,
                    subtitleDelay: delay
                )
                updateSubtitleGapPlayback()
            }
            .onChange(of: model.currentURL) { oldURL, newURL in
                subtitleTrackExtractionTask?.cancel()
                subtitleTrackExtractionTask = nil
                activeSubtitleTrackExtractionKey = nil
                clearTimelinePreview(clearCache: true)
                if newURL != nil {
                    suspendVideoThumbnailsForVideoSession()
                    revealPlaybackChrome(scheduleHide: true)
                } else {
                    resumeVideoThumbnailsForVideoSession()
                    playbackChromeAutoHideTask?.cancel()
                    windowChrome.restorePlaybackCursor()
                    isPlaybackChromeVisible = true
                }
            }
    }

    private var playerSurface: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                videoSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                if isMiningHistoryVisible {
                    let sidebarWidth = clampedStudySidebarWidth(
                        CGFloat(studySidebarWidth),
                        availableSize: geometry.size
                    )
                    let isTranscriptSidebarTab = selectedStudySidebarTab == .transcript
                    let isChaptersSidebarTab = selectedStudySidebarTab == .chapters
                    let sidebarTranscript = isTranscriptSidebarTab
                        ? subtitles.transcript
                        : SubtitleTranscript(primary: nil, secondary: nil)
                    let sidebarChapters = isChaptersSidebarTab ? model.snapshot.chapters : []
                    let sidebarCurrentTime = (isTranscriptSidebarTab || isChaptersSidebarTab)
                        ? model.snapshot.currentTime
                        : 0
                    let sidebarPendingABLoopStart = isTranscriptSidebarTab
                        ? model.pendingABLoopStart
                        : nil
                    let sidebarABLoop = isTranscriptSidebarTab ? model.snapshot.abLoop : nil
                    let sidebarIsTranscriptLoading = isTranscriptSidebarTab
                        && subtitles.isTranscriptLoading
                    let sidebarTranscriptErrorMessage = isTranscriptSidebarTab
                        ? subtitles.transcriptErrorMessage
                        : nil
                    let canAlignPreviousSubtitle = isTranscriptSidebarTab
                        && subtitleAlignmentDelay(.previous) != nil
                    let canAlignNextSubtitle = isTranscriptSidebarTab
                        && subtitleAlignmentDelay(.next) != nil

                    VideoMiningHistorySidebar(
                        selectedTab: $selectedStudySidebarTab,
                        items: miningHistory.items,
                        transcript: sidebarTranscript,
                        chapters: sidebarChapters,
                        currentTime: sidebarCurrentTime,
                        pendingABLoopStart: sidebarPendingABLoopStart,
                        abLoop: sidebarABLoop,
                        isTranscriptLoading: sidebarIsTranscriptLoading,
                        transcriptErrorMessage: sidebarTranscriptErrorMessage,
                        canAlignPreviousSubtitle: canAlignPreviousSubtitle,
                        canAlignNextSubtitle: canAlignNextSubtitle,
                        onClose: {
                            withAnimation(.smooth(duration: 0.22)) {
                                isMiningHistoryVisible = false
                            }
                        },
                        onJump: { item in
                            navigateToHistoryItem(item)
                        },
                        onSeekTranscript: { time in
                            dismissVideoPopupsIfNeeded()
                            model.seek(to: time + model.snapshot.subtitleDelay)
                        },
                        onSetTranscriptABLoopStart: { time in
                            dismissVideoPopupsIfNeeded()
                            model.setABLoopStart(at: time)
                        },
                        onSetTranscriptABLoopEnd: { time in
                            dismissVideoPopupsIfNeeded()
                            model.setABLoopEnd(at: time)
                        },
                        onAlignPreviousSubtitle: {
                            _ = alignAdjacentSubtitleToCurrentTime(.previous)
                        },
                        onAlignNextSubtitle: {
                            _ = alignAdjacentSubtitleToCurrentTime(.next)
                        },
                        onSeekChapter: { chapterID in
                            dismissVideoPopupsIfNeeded()
                            model.seekToChapter(chapterID)
                        },
                        onCopy: { item in
                            copyMiningHistorySubtitle(item)
                        },
                        onDelete: { id in
                            miningHistory.delete(id: id)
                        },
                        onClear: {
                            miningHistory.clear()
                        }
                    )
                    .frame(width: sidebarWidth)
                    .overlay(alignment: .leading) {
                        VideoStudySidebarResizeHandle()
                            .gesture(
                                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { value in
                                        if studySidebarDragStartWidth == nil {
                                            studySidebarDragStartWidth = sidebarWidth
                                        }

                                        let startWidth = studySidebarDragStartWidth ?? sidebarWidth
                                        let nextWidth = startWidth - value.translation.width
                                        studySidebarWidth = Double(
                                            clampedStudySidebarWidth(
                                                nextWidth,
                                                availableSize: geometry.size
                                            )
                                        )
                                    }
                                    .onEnded { _ in
                                        studySidebarWidth = Double(
                                            clampedStudySidebarWidth(
                                                CGFloat(studySidebarWidth),
                                                availableSize: geometry.size
                                            )
                                        )
                                        studySidebarDragStartWidth = nil
                                    }
                            )
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
            .onHover { hovering in
                playerSurfaceHoverChanged(hovering)
            }
            .animation(.smooth(duration: 0.22), value: isMiningHistoryVisible)
        }
    }

    private func clampedStudySidebarWidth(
        _ width: CGFloat,
        availableSize: CGSize
    ) -> CGFloat {
        let availableMaxWidth = max(
            VideoMiningHistorySidebar.minWidth,
            min(
                VideoMiningHistorySidebar.maxWidth,
                availableSize.width - Self.minimumVideoSurfaceWidth
            )
        )
        let clampedWidth = min(max(width, VideoMiningHistorySidebar.minWidth), availableMaxWidth)
        return VideoWindowAspectLayout.aspectFittingSidebarWidth(
            contentSize: availableSize,
            videoAspectRatio: windowChrome.isFullScreen ? nil : videoWindowAspectRatio,
            proposedWidth: clampedWidth,
            minWidth: VideoMiningHistorySidebar.minWidth,
            maxWidth: availableMaxWidth
        )
    }

    private var videoSurface: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                ZStack(alignment: .trailing) {
                    videoCanvas
                    if isInspectorVisible {
                        inspectorOverlay
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: VideoInspectorOverlayFramePreferenceKey.self,
                                        value: proxy.frame(in: .named(Self.videoPlayerCoordinateSpace))
                                    )
                                }
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .contentShape(Rectangle())
                            .onTapGesture {}
                            .zIndex(10)
                    }
                }
                .animation(.smooth(duration: 0.22), value: isInspectorVisible)
                .coordinateSpace(name: Self.videoPlayerCoordinateSpace)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ambientPresentation.workspaceCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    if ambientPresentation.workspaceCornerRadius > 0 {
                        RoundedRectangle(
                            cornerRadius: ambientPresentation.workspaceCornerRadius,
                            style: .continuous
                        )
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                        .allowsHitTesting(false)
                    }
                }

                ForEach(lookup.presentation.popups) { popup in
                    popupView(popup, screenSize: geometry.size)
                }

                if let miningHistoryNotice {
                    videoMiningHistoryNotice(miningHistoryNotice)
                        .padding(.top, 42)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1000)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var ambientPresentation: VideoAmbientPresentation {
        VideoAmbientPresentation.resolve(isFullScreen: windowChrome.isFullScreen)
    }

    private var videoWindowAspectRatio: CGFloat? {
        VideoWindowAspectLayout.videoAspectRatio(
            displaySize: model.snapshot.videoDisplaySize,
            override: model.snapshot.aspectRatio,
            rotation: model.snapshot.rotation
        )
    }

    private func synchronizeVideoWindowLayout() {
        windowChrome.setVideoLayout(
            videoAspectRatio: videoWindowAspectRatio,
            studySidebarWidth: CGFloat(studySidebarWidth),
            isStudySidebarVisible: isMiningHistoryVisible && !windowChrome.isFullScreen
        )
    }

    private func refreshAmbientBackdrop(reason: VideoAmbientRefreshReason) {
        guard ambientPresentation.usesBlurredLetterbox else {
            ambientBackdrop.suspend(clear: true)
            return
        }
        ambientBackdrop.refresh(
            reason: reason,
            engine: model.engine,
            generation: model.loadGeneration,
            isLoaded: model.snapshot.isLoaded,
            isPlaying: model.snapshot.isPlaying,
            isActive: isActive && scenePhase == .active,
            isFullScreen: windowChrome.isFullScreen
        )
    }

    private func suspendVideoThumbnailsForVideoSession() {
        Task {
            await VideoThumbnailScheduler.shared.suspend(reason: .playback)
        }
    }

    private func resumeVideoThumbnailsForVideoSession() {
        Task {
            await VideoThumbnailScheduler.shared.resume(reason: .playback)
        }
    }

    private func updateTimelinePreview(at time: TimeInterval?) {
        guard let time,
              model.currentURL != nil,
              model.snapshot.duration > 0 else {
            clearTimelinePreview()
            return
        }

        let clampedTime = clampedTimelinePreviewTime(time)
        timelinePreviewRequestedTime = clampedTime
        timelinePreview = VideoTimelinePreview(time: clampedTime, pngData: nil)
    }

    private func clearTimelinePreview(clearCache _: Bool = false) {
        timelinePreviewRequestedTime = nil
        timelinePreview = nil
    }

    private func clampedTimelinePreviewTime(_ time: TimeInterval) -> TimeInterval {
        guard time.isFinite else { return 0 }
        let duration = max(model.snapshot.duration, 0)
        guard duration > 0 else { return 0 }
        return min(max(time, 0), duration)
    }

    private var videoCanvas: some View {
        GeometryReader { geometry in
            let subtitleViewport = VideoWindowAspectLayout.videoViewport(
                in: geometry.size,
                renderGeometry: model.snapshot.videoRenderGeometry,
                aspectRatio: videoWindowAspectRatio
            )

            ZStack(alignment: .bottom) {
                MpvRenderView(
                    engine: model.engine as! MpvPlayerEngine,
                    onRenderReady: handleRenderReady
                )
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        handleVideoPointerMovement(phase)
                    }
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded {
                                toggleFullScreenFromPointer()
                            }
                            .exclusively(
                                before: TapGesture(count: 1)
                                    .onEnded {
                                        togglePlaybackFromPointer()
                                    }
                            )
                    )

                VideoAmbientBackdrop(
                    image: ambientBackdrop.image,
                    presentation: ambientPresentation
                )
                .zIndex(0.25)

                if windowChrome.showsWindowedTitlebarSurface {
                    videoWindowDragStrip
                        .zIndex(0.5)
                }

                if model.currentURL != nil {
                    VideoSurfaceScrollBridge(
                        isEnabled: shouldHandleVideoSurfaceVolumeScroll,
                        excludedRects: videoSurfaceVolumeScrollExcludedRects(in: geometry.size),
                        onScroll: { delta in
                            adjustVolume(by: delta)
                            revealPlaybackChrome(scheduleHide: true)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .zIndex(1.5)
                }

                if shouldShowVideoDismissLayer {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissVideoOverlaysFromCanvas()
                        }
                        .zIndex(2.5)
                }

                if model.currentURL == nil {
                    ContentUnavailableView {
                        Label("No Video Open", systemImage: "play.rectangle")
                    } description: {
                        Text("Open a local video file to start watching.")
                    } actions: {
                        Button("Open Video") {
                            presentFileImporter(.video)
                        }
                        Button("Open Link") {
                            isOpeningRemoteLink = true
                        }
                    }
                    .foregroundStyle(.white)
                    .zIndex(2)
                } else if areSubtitlesVisible,
                          subtitleRenderingMode.usesInteractiveOverlay {
                    SubtitleOverlayView(
                        cues: subtitleOverlayCues,
                        contextCues: subtitles.document?.cues ?? subtitles.currentCues,
                        scanLength: userConfig.scanLength,
                        contentLanguage: profileRepository.activeProfile.language,
                        hoverLookupDelayMs: userConfig.desktopLookupHoverDelayMs,
                        maskEnabled: userConfig.videoSubtitleMaskEnabled,
                        maskMode: userConfig.videoSubtitleMaskMode,
                        maskBlurRadius: userConfig.videoSubtitleMaskBlurRadius,
                        maskHiddenOpacity: userConfig.videoSubtitleMaskHiddenOpacity,
                        fontFamily: userConfig.videoSubtitleFontFamily,
                        fontSize: userConfig.videoSubtitleFontSize,
                        fontWeight: userConfig.videoSubtitleFontWeight,
                        edgeStyle: userConfig.videoSubtitleEdgeStyle,
                        edgeStrength: userConfig.videoSubtitleEdgeStrength,
                        backgroundOpacity: userConfig.videoSubtitleBackgroundOpacity,
                        backgroundDisabled: userConfig.videoSubtitleBackgroundDisabled,
                        verticalPosition: userConfig.videoSubtitleVerticalPosition,
                        subtitleColor: userConfig.videoSubtitleColor,
                        lookupHighlightColor: userConfig.videoSubtitleLookupHighlightColor,
                        lookupHighlightTextColor: userConfig.videoSubtitleLookupHighlightTextColor,
                        isLookupPopupVisible: hasVisibleVideoPopup,
                        isPlaybackPaused: !model.snapshot.isPlaying
                    ) { cue, selection in
                        lookup.present(
                            selection: selection,
                            cue: cue,
                            player: model,
                            userConfig: userConfig,
                            replacingExisting: true
                        )
                    }
                    .frame(
                        width: subtitleViewport.width,
                        height: subtitleViewport.height,
                        alignment: .bottom
                    )
                    .position(
                        x: subtitleViewport.midX,
                        y: subtitleViewport.midY
                    )
                    .zIndex(2)
                }

                if shouldShowVideoLoadingIndicator {
                    ZStack {
                        Color.black

                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(.white)
                            Text("Loading Video...")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.white.opacity(0.86))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Loading Video..."))
                    .zIndex(50)
                }

                if let videoOSD, model.currentURL != nil {
                    VStack(alignment: .leading, spacing: 0) {
                        VideoOnScreenDisplayView(item: videoOSD)
                            .padding(.top, 30)
                            .padding(.leading, 28)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(2.6)
                }

                if model.currentURL != nil {
                    VideoControlsView(
                        snapshot: model.snapshot,
                        timelinePreview: timelinePreview,
                        playlist: model.playlist,
                        canSaveScreenshot: model.snapshot.isLoaded && !model.snapshot.isSeeking
                            && model.snapshot.videoDisplaySize != nil && !isSavingScreenshot,
                        canMineCurrentSubtitle: canMineCurrentSubtitle,
                        isFullScreen: windowChrome.isFullScreen,
                        isSubtitleGapFastForwardEnabled: userConfig.videoSubtitleGapFastForwardEnabled,
                        layout: userConfig.videoControlBarLayout,
                        availableWidth: geometry.size.width,
                        isSpeedPanelVisible: $isSpeedPanelVisible,
                        onTogglePlayback: {
                            model.togglePlayback()
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onSeek: { time in
                            model.seek(to: time)
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onPrevious: {
                            model.playPrevious()
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onNext: {
                            model.playNext()
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onSetVolume: { volume in
                            setVolumeWithOSD(volume)
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onToggleMuted: {
                            toggleMuteWithOSD()
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onSetSpeed: { speed in
                            dismissVideoPopupsIfNeeded()
                            setSpeedWithOSD(speed)
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onToggleMiningHistory: {
                            revealPlaybackChrome(scheduleHide: false)
                            dismissVideoPopupsThen {
                                toggleMiningHistory()
                            }
                        },
                        onOpenVideo: {
                            revealPlaybackChrome(scheduleHide: true)
                            dismissVideoPopupsThen {
                                presentFileImporter(.video)
                            }
                        },
                        onSaveScreenshot: saveCleanScreenshot,
                        onMineCurrentSubtitle: {
                            mineCurrentSubtitle()
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onToggleSubtitleGapFastForward: {
                            toggleSubtitleGapFastForward()
                            revealPlaybackChrome(scheduleHide: true)
                        },
                        onToggleInspector: {
                            revealPlaybackChrome(scheduleHide: false)
                            dismissVideoPopupsThen {
                                toggleInspector()
                            }
                        },
                        onToggleFullScreen: {
                            revealPlaybackChrome(scheduleHide: true)
                            dismissVideoPopupsThen {
                                toggleFullScreen()
                            }
                        },
                        onTimelinePreviewTimeChanged: { time in
                            updateTimelinePreview(at: time)
                            if time != nil {
                                revealPlaybackChrome(scheduleHide: false)
                            } else {
                                schedulePlaybackChromeAutoHide()
                            }
                        },
                        onDragChanged: { translation in
                            revealPlaybackChrome(scheduleHide: false)
                            var dragTransaction = Transaction(animation: nil)
                            dragTransaction.disablesAnimations = true
                            withTransaction(dragTransaction) {
                                playbackChromeDragOffset = translation
                            }
                        },
                        onDragEnded: { translation in
                            let finalOffset = clampedPlaybackChromeOffset(
                                CGSize(
                                    width: playbackChromeStoredOffset.width + translation.width,
                                    height: playbackChromeStoredOffset.height + translation.height
                                ),
                                in: geometry.size
                            )
                            withAnimation(.smooth(duration: 0.18)) {
                                playbackChromeStoredOffset = finalOffset
                                playbackChromeDragOffset = .zero
                            }
                            revealPlaybackChrome(scheduleHide: true)
                        }
                    )
                    .position(playbackChromeBasePosition(in: geometry.size))
                    .offset(playbackChromeCurrentOffset(in: geometry.size))
                    .onHover { hovering in
                        playbackChromeHoverChanged(hovering)
                    }
                    .opacity(shouldShowPlaybackChrome ? 1 : 0)
                    .allowsHitTesting(shouldShowPlaybackChrome)
                    .accessibilityHidden(!shouldShowPlaybackChrome)
                    .zIndex(3)
                }

            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.easeInOut(duration: 0.16), value: shouldShowPlaybackChrome)
            .onPreferenceChange(VideoInspectorOverlayFramePreferenceKey.self) { frame in
                inspectorOverlayFrame = frame ?? .zero
            }
            .onChange(of: geometry.size) { _, size in
                guard !windowChrome.isWindowGeometryTransitioning else { return }
                let nextStoredOffset: CGSize
                if userConfig.videoControlBarLayout == .compactBottom {
                    nextStoredOffset = .zero
                } else {
                    nextStoredOffset = clampedPlaybackChromeOffset(
                        playbackChromeStoredOffset,
                        in: size
                    )
                }
                if playbackChromeStoredOffset != nextStoredOffset {
                    playbackChromeStoredOffset = nextStoredOffset
                }
                if playbackChromeDragOffset != .zero {
                    playbackChromeDragOffset = .zero
                }
            }
            .onChange(of: userConfig.videoControlBarLayout) { _, layout in
                if layout == .compactBottom {
                    playbackChromeStoredOffset = .zero
                } else {
                    playbackChromeStoredOffset = clampedPlaybackChromeOffset(
                        playbackChromeStoredOffset,
                        in: geometry.size
                    )
                }
                playbackChromeDragOffset = .zero
            }
        }
    }

    private var videoWindowDragStrip: some View {
        VStack(spacing: 0) {
            ZStack {
                VideoTitlebarBackdrop()
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
                    .opacity(shouldShowPlaybackChrome ? 1 : 0)
                    .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .allowsWindowActivationEvents(true)
            }
            .frame(height: 32)
            Spacer(minLength: 0)
        }
    }

    private var videoControlsMetrics: VideoControlsMetrics {
        VideoControlsView.metrics(for: userConfig.videoControlBarLayout)
    }

    private var inspectorOverlay: some View {
        VideoInspectorView(
            selectedTab: $selectedInspectorTab,
            state: model.inspectorState,
            playlist: model.playlist,
            currentURL: model.currentURL,
            currentTitle: model.currentTitle,
            primarySubtitleName: selectedRemoteSubtitleID == nil
                ? (selectedAJATTSubtitleName
                    ?? selectedJimakuSubtitleName
                    ?? subtitles.document?.sourceURL.lastPathComponent)
                : nil,
            remoteSubtitleOptions: currentRemoteSubtitleOptions,
            selectedRemoteSubtitleID: selectedRemoteSubtitleID,
            selectedJimakuSubtitleID: selectedJimakuSubtitleID,
            selectedJimakuSubtitleName: selectedJimakuSubtitleName,
            selectedAJATTSubtitleID: selectedAJATTSubtitleID,
            selectedAJATTSubtitleName: selectedAJATTSubtitleName,
            remoteQualityOptions: currentRemoteQualityOptions,
            selectedRemoteQualityID: selectedRemoteQualityID,
            onSelectEpisode: { url in
                openPlaylistEpisode(url)
            },
            onSetSpeed: { speed in
                dismissVideoPopupsIfNeeded()
                setSpeedWithOSD(speed)
            },
            onSetSubtitleDelay: { delay in
                dismissVideoPopupsIfNeeded()
                setSubtitleDelayWithOSD(delay)
            },
            onSetAudioDelay: { delay in
                dismissVideoPopupsIfNeeded()
                setAudioDelayWithOSD(delay)
            },
            onSetLoopMode: { mode in
                dismissVideoPopupsIfNeeded()
                model.setLoopMode(mode)
            },
            onSetABLoopStart: {
                dismissVideoPopupsIfNeeded()
                model.setABLoopStart()
            },
            onSetABLoopEnd: {
                dismissVideoPopupsIfNeeded()
                model.setABLoopEnd()
            },
            onClearABLoop: {
                dismissVideoPopupsIfNeeded()
                model.clearABLoop()
            },
            onSetAspectRatio: { aspectRatio in
                dismissVideoPopupsIfNeeded()
                model.setAspectRatio(aspectRatio)
            },
            onRotateClockwise: {
                dismissVideoPopupsIfNeeded()
                model.rotateClockwise()
            },
            onSetVideoShaderPreset: { preset in
                dismissVideoPopupsIfNeeded()
                _ = model.setVideoShaderPreset(preset)
            },
            onSelectTrack: { type, id in
                dismissVideoPopupsIfNeeded()
                if type == .subtitle {
                    if let id {
                        selectSubtitleTrack(id, rememberSelection: true)
                    } else {
                        applySubtitlesOff(clearPrimary: true, rememberSelection: true)
                        showSubtitleTrackOSD(track: nil)
                    }
                    return
                }
                model.selectTrack(type: type, id: id)
            },
            onSelectRemoteSubtitle: { option in
                dismissVideoPopupsIfNeeded()
                loadRemoteSubtitle(option, rememberSelection: true)
            },
            onSelectJimakuSubtitle: { file in
                dismissVideoPopupsIfNeeded()
                loadJimakuSubtitle(file)
            },
            onSelectAJATTSubtitle: { file in
                dismissVideoPopupsIfNeeded()
                loadAJATTSubtitle(file)
            },
            onSelectRemoteQuality: { option in
                dismissVideoPopupsIfNeeded()
                selectRemoteQuality(option)
            },
            onOpenSubtitle: {
                dismissVideoPopupsIfNeeded()
                presentFileImporter(.primarySubtitle)
            },
            onClearPrimarySubtitle: {
                dismissVideoPopupsIfNeeded()
                applySubtitlesOff(clearPrimary: true, rememberSelection: true)
                showSubtitleTrackOSD(track: nil)
            },
            onOpenTranscript: {
                toggleTranscriptSidebar()
            },
            onClose: {
                dismissVideoPopupsIfNeeded()
                isInspectorVisible = false
            }
        )
        .equatable()
        .padding(.vertical, Self.inspectorOverlayVerticalInset)
        .padding(.trailing, Self.inspectorOverlayTrailingInset)
    }

    private var currentRemoteSubtitleOptions: [RemoteVideoSubtitleOption] {
        guard case .remoteStream(let source) = model.currentSource else { return [] }
        return source.subtitleOptions
    }

    private var currentRemoteQualityOptions: [RemoteVideoQualityOption] {
        guard case .remoteStream(let source) = model.currentSource,
              source.identity.isYouTube,
              source.qualityOptions.count > 1 else { return [] }
        return source.qualityOptions
    }

    private var selectedRemoteQualityID: String? {
        guard case .remoteStream(let source) = model.currentSource else { return nil }
        return source.qualityOptions.first {
            $0.playbackStream.url == source.playbackStream.url
                && $0.audioStream?.url == source.audioStream?.url
        }?.id
    }

    private var videoPlaybackCommandContext: VideoPlaybackCommandContext {
        VideoPlaybackCommandContext(
            snapshot: model.snapshot,
            playlist: model.playlist,
            currentURL: model.currentURL,
            areSubtitlesVisible: areSubtitlesVisible,
            primarySubtitleName: subtitles.document?.sourceURL.lastPathComponent,
            canMineCurrentSubtitle: canMineCurrentSubtitle,
            openVideo: {
                dismissVideoPopupsThen {
                    presentFileImporter(.video)
                }
            },
            openRemoteLink: {
                dismissVideoPopupsThen {
                    isOpeningRemoteLink = true
                }
            },
            playPause: {
                guard model.currentURL != nil else { return }
                model.togglePlayback()
            },
            previousEpisode: {
                guard model.playlist.previousURL != nil else { return }
                model.playPrevious()
            },
            nextEpisode: {
                guard model.playlist.nextURL != nil else { return }
                model.playNext()
            },
            setSpeed: { speed in
                dismissVideoPopupsIfNeeded()
                setSpeedWithOSD(speed)
            },
            setAspectRatio: { aspectRatio in
                dismissVideoPopupsIfNeeded()
                model.setAspectRatio(aspectRatio)
            },
            rotateClockwise: {
                dismissVideoPopupsIfNeeded()
                model.rotateClockwise()
            },
            toggleFileLoop: {
                dismissVideoPopupsIfNeeded()
                model.setLoopMode(model.snapshot.loopMode == .file ? .none : .file)
            },
            setABLoopStart: {
                dismissVideoPopupsIfNeeded()
                model.setABLoopStart()
            },
            setABLoopEnd: {
                dismissVideoPopupsIfNeeded()
                model.setABLoopEnd()
            },
            clearABLoop: {
                dismissVideoPopupsIfNeeded()
                model.clearABLoop()
            },
            selectTrack: { type, id in
                dismissVideoPopupsIfNeeded()
                if type == .subtitle {
                    if let id {
                        selectSubtitleTrack(id, rememberSelection: true)
                    } else {
                        applySubtitlesOff(clearPrimary: true, rememberSelection: true)
                        showSubtitleTrackOSD(track: nil)
                    }
                    return
                }
                model.selectTrack(type: type, id: id)
            },
            toggleMuted: {
                toggleMuteWithOSD()
            },
            adjustVolume: { delta in
                adjustVolume(by: delta)
            },
            adjustAudioDelay: { delta in
                adjustAudioDelayWithOSD(by: delta)
            },
            resetAudioDelay: {
                setAudioDelayWithOSD(0)
            },
            openSubtitles: {
                dismissVideoPopupsIfNeeded()
                presentFileImporter(.primarySubtitle)
            },
            clearPrimarySubtitle: {
                dismissVideoPopupsIfNeeded()
                applySubtitlesOff(clearPrimary: true, rememberSelection: true)
                showSubtitleTrackOSD(track: nil)
            },
            toggleSubtitlesVisible: {
                toggleSubtitlesVisible()
            },
            previousSubtitleCue: {
                _ = seekRelativeSubtitleCue(offset: -1)
            },
            nextSubtitleCue: {
                _ = seekRelativeSubtitleCue(offset: 1)
            },
            cycleSubtitleTrack: {
                _ = cycleSubtitleTrack()
            },
            adjustSubtitleDelay: { delta in
                adjustSubtitleDelayWithOSD(by: delta)
            },
            resetSubtitleDelay: {
                setSubtitleDelayWithOSD(0)
            },
            openTranscript: {
                toggleTranscriptSidebar()
            },
            mineCurrentSubtitle: {
                mineCurrentSubtitle()
            }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: {
                remoteVideoOpenErrorMessage != nil
                    || model.errorMessage != nil
                    || subtitles.errorMessage != nil
            },
            set: { visible in
                if !visible {
                    remoteVideoOpenErrorMessage = nil
                    model.errorMessage = nil
                    subtitles.errorMessage = nil
                }
            }
        )
    }

    private func handleFileImport(
        _ result: Result<[URL], any Error>,
        kind: VideoFileImportKind
    ) {
        switch kind {
        case .video:
            handleVideoImport(result)
        case .primarySubtitle:
            handleSubtitleImport(result)
        }
    }

    private func handleVideoImport(
        _ result: Result<[URL], any Error>
    ) {
        if let url = try? result.get().first {
            openVideo(url)
        }
    }

    private func openVideo(
        _ url: URL,
        subtitleURL: URL? = nil,
        startsFromBeginning: Bool = false
    ) {
        openVideo(
            .localFile(url),
            subtitleURL: subtitleURL,
            startsFromBeginning: startsFromBeginning
        )
    }

    private func openVideo(
        _ source: VideoPlaybackSource,
        subtitleURL: URL? = nil,
        startsFromBeginning: Bool = false
    ) {
        cancelPendingRemoteVideoOpen()
        remoteVideoOpenErrorMessage = nil
        lookup.closeAll(player: model)
        invalidatePrimarySubtitleLoad()
        configureSubtitleRendering(.overlayOnly)
        subtitles.clear()
        selectedRemoteSubtitleID = nil
        selectedJimakuSubtitleID = nil
        selectedJimakuSubtitleName = nil
        selectedAJATTSubtitleID = nil
        selectedAJATTSubtitleName = nil
        remoteSubtitleGeneration &+= 1
        remoteSubtitleLoader.cancelAndCleanup()
        let isRemoteSource: Bool
        if case .remoteStream = source {
            isRemoteSource = true
        } else {
            isRemoteSource = false
        }
        shouldSkipNextAutomaticSubtitleRestore = subtitleURL != nil || isRemoteSource
        model.open(source, startsFromBeginning: startsFromBeginning)
        guard model.errorMessage == nil else {
            shouldSkipNextAutomaticSubtitleRestore = false
            return
        }
        if let subtitleURL {
            loadPrimarySubtitle(from: subtitleURL, loadIntoMpv: true)
        } else if case .remoteStream(let remoteSource) = source {
            let rememberedSelection = model.consumePendingSubtitleSelection()
            if case .off = rememberedSelection {
                applySubtitlesOff(clearPrimary: true, rememberSelection: false)
                return
            }
            let subtitle = rememberedSelection
                .flatMap { remoteSubtitle(selection: $0, in: remoteSource) }
                ?? preferredRemoteSubtitle(in: remoteSource)
            if let subtitle {
                loadRemoteSubtitle(subtitle, rememberSelection: false)
            }
        }
    }

    private func openRemoteLink(_ resolvedSource: ResolvedRemoteVideoSource) {
        openVideo(.remoteStream(resolvedSource), subtitleURL: nil)
    }

    private func loadRemoteSubtitle(
        _ subtitle: RemoteVideoSubtitleOption,
        rememberSelection: Bool
    ) {
        selectedJimakuSubtitleID = nil
        selectedJimakuSubtitleName = nil
        selectedAJATTSubtitleID = nil
        selectedAJATTSubtitleName = nil
        invalidatePrimarySubtitleLoad()
        configureSubtitleRendering(.overlayOnly)
        subtitles.discardTemporaryASSEffects()
        subtitles.clearPrimary()
        model.selectTrack(type: .subtitle, id: nil)
        lastSelectedSubtitleTrackID = nil
        remoteSubtitleGeneration &+= 1
        let generation = remoteSubtitleGeneration
        Task { @MainActor in
            do {
                guard let tempURL = try await remoteSubtitleLoader.load(
                    option: subtitle,
                    generation: generation
                ), generation == remoteSubtitleGeneration else { return }
                await loadPrimarySubtitle(
                    from: tempURL,
                    loadIntoMpv: false,
                    rememberSelection: false
                ).value
                guard generation == remoteSubtitleGeneration,
                      subtitles.document?.sourceURL.standardizedFileURL
                        == tempURL.standardizedFileURL else { return }
                selectedRemoteSubtitleID = subtitle.id
                if rememberSelection {
                    model.rememberSubtitleSelection(
                        .remoteOption(subtitle.selectionIdentity)
                    )
                }
            } catch {
                guard !Task.isCancelled,
                      generation == remoteSubtitleGeneration else { return }
                subtitles.errorMessage = String(localized: "Unable to load the remote subtitle.")
            }
        }
    }

    private func loadJimakuSubtitle(_ file: JimakuSubtitleFile) {
        loadCatalogSubtitle(
            option: file.remoteSubtitleOption,
            id: file.id,
            name: file.name,
            source: .jimaku
        )
    }

    private func loadAJATTSubtitle(_ file: AJATTSubtitleFile) {
        loadCatalogSubtitle(
            option: file.remoteSubtitleOption,
            id: file.id,
            name: file.name,
            source: .ajatt
        )
    }

    private enum CatalogSubtitleSource {
        case jimaku
        case ajatt

        var allowedDownloadHosts: Set<String>? {
            switch self {
            case .jimaku: nil
            case .ajatt: ["raw.githubusercontent.com"]
            }
        }

        var errorMessage: String {
            switch self {
            case .jimaku:
                String(localized: "Unable to load the Jimaku subtitle.")
            case .ajatt:
                String(localized: "Unable to load the AJATT subtitle.")
            }
        }

        var maximumResponseSize: Int {
            switch self {
            case .jimaku: 64 * 1_024 * 1_024
            case .ajatt: 10 * 1_024 * 1_024
            }
        }
    }

    private func loadCatalogSubtitle(
        option: RemoteVideoSubtitleOption,
        id: String,
        name: String,
        source: CatalogSubtitleSource
    ) {
        invalidatePrimarySubtitleLoad()
        configureSubtitleRendering(.overlayOnly)
        subtitles.discardTemporaryASSEffects()
        subtitles.clearPrimary()
        model.selectTrack(type: .subtitle, id: nil)
        lastSelectedSubtitleTrackID = nil
        selectedRemoteSubtitleID = nil
        selectedJimakuSubtitleID = nil
        selectedJimakuSubtitleName = nil
        selectedAJATTSubtitleID = nil
        selectedAJATTSubtitleName = nil
        remoteSubtitleGeneration &+= 1
        let generation = remoteSubtitleGeneration
        Task { @MainActor in
            do {
                guard let tempURL = try await remoteSubtitleLoader.load(
                    option: option,
                    allowedDownloadHosts: source.allowedDownloadHosts,
                    maximumResponseSize: source.maximumResponseSize,
                    generation: generation
                ), generation == remoteSubtitleGeneration else { return }
                await loadPrimarySubtitle(
                    from: tempURL,
                    loadIntoMpv: false,
                    rememberSelection: false
                ).value
                guard generation == remoteSubtitleGeneration,
                      subtitles.document?.sourceURL.standardizedFileURL
                        == tempURL.standardizedFileURL else { return }
                switch source {
                case .jimaku:
                    selectedJimakuSubtitleID = id
                    selectedJimakuSubtitleName = name
                case .ajatt:
                    selectedAJATTSubtitleID = id
                    selectedAJATTSubtitleName = name
                }
            } catch {
                guard !Task.isCancelled,
                      generation == remoteSubtitleGeneration else { return }
                subtitles.errorMessage = source.errorMessage
            }
        }
    }

    private func preferredRemoteSubtitle(
        in source: ResolvedRemoteVideoSource
    ) -> RemoteVideoSubtitleOption? {
        source.preferredSubtitle(
            preferredLanguages: [source.selectedSubtitleLanguage].compactMap { $0 },
            fallbackLanguages: ["ja", "en"]
        )
    }

    private func remoteSubtitle(
        selection: VideoSubtitleSelection,
        in source: ResolvedRemoteVideoSource
    ) -> RemoteVideoSubtitleOption? {
        switch selection {
        case .remoteOption(let identity):
            source.subtitleOption(matching: identity)
        case .remote(let language):
            source.preferredSubtitle(language: language)
        default:
            nil
        }
    }

    private func selectRemoteQuality(_ option: RemoteVideoQualityOption) {
        guard case .remoteStream(let source) = model.currentSource,
              source.identity.isYouTube,
              option.id != selectedRemoteQualityID,
              let selectedSource = source.selectingQuality(id: option.id) else {
            return
        }
        shouldSkipNextAutomaticSubtitleRestore = true
        if !model.switchRemoteQuality(to: selectedSource) {
            shouldSkipNextAutomaticSubtitleRestore = false
        }
    }

    private func openPlaylistEpisode(_ url: URL) {
        lookup.closeAll(player: model)
        invalidatePrimarySubtitleLoad()
        configureSubtitleRendering(.overlayOnly)
        subtitles.clear()
        selectedRemoteSubtitleID = nil
        selectedJimakuSubtitleID = nil
        selectedJimakuSubtitleName = nil
        selectedAJATTSubtitleID = nil
        selectedAJATTSubtitleName = nil
        remoteSubtitleGeneration &+= 1
        remoteSubtitleLoader.cancelAndCleanup()
        model.selectPlaylistItem(url)
    }

    private func handleExternalOpenRequest(_ request: VideoWindowOpenRequest?) {
        guard let request,
              let readyRequest = openGate.receive(request) else { return }
        openExternalRequest(readyRequest)
    }

    private func handleRenderReady() {
        guard let request = openGate.renderDidBecomeReady() else { return }
        openExternalRequest(request)
    }

    private func openExternalRequest(_ request: VideoWindowOpenRequest) {
        onConsumeOpenRequest(request.id)
        switch request.source {
        case .playback(let source):
            openVideo(
                source,
                subtitleURL: request.subtitleURL,
                startsFromBeginning: request.startsFromBeginning
            )
        case .unresolvedRemote(let remoteRequest):
            openRemoteVideo(remoteRequest)
        }
    }

    private var shouldShowVideoLoadingIndicator: Bool {
        isResolvingRemoteVideo
            || (
                model.currentURL != nil
                    && !model.snapshot.isLoaded
                    && model.errorMessage == nil
            )
    }

    private func openRemoteVideo(_ request: RemoteVideoWindowOpenRequest) {
        cancelPendingRemoteVideoOpen()
        remoteVideoOpenErrorMessage = nil
        isResolvingRemoteVideo = true
        remoteVideoOpenGeneration &+= 1
        let generation = remoteVideoOpenGeneration
        let resolver = RemoteVideoResolverRegistry()
        remoteVideoOpenTask = Task { @MainActor in
            do {
                let resolvedSource = try await resolver.resolve(
                    identity: request.identity,
                    preferredSubtitleLanguages: request.preferredSubtitleLanguages,
                    forceRefresh: request.forceRefresh
                )
                guard generation == remoteVideoOpenGeneration,
                      !Task.isCancelled else {
                    return
                }
                _ = VideoLibraryStore.shared.addRemoteItem(resolvedSource)
                isResolvingRemoteVideo = false
                remoteVideoOpenTask = nil
                openVideo(
                    .remoteStream(resolvedSource),
                    subtitleURL: nil,
                    startsFromBeginning: request.startsFromBeginning
                )
            } catch {
                guard generation == remoteVideoOpenGeneration else {
                    return
                }
                isResolvingRemoteVideo = false
                remoteVideoOpenTask = nil
                guard !Task.isCancelled,
                      !(error is CancellationError),
                      !Self.isRemoteResolutionCancellation(error) else {
                    return
                }
                remoteVideoOpenErrorMessage = error.localizedDescription
            }
        }
    }

    private func cancelPendingRemoteVideoOpen() {
        remoteVideoOpenGeneration &+= 1
        remoteVideoOpenTask?.cancel()
        remoteVideoOpenTask = nil
        isResolvingRemoteVideo = false
    }

    private static func isRemoteResolutionCancellation(_ error: any Error) -> Bool {
        guard let resolverError = error as? RemoteVideoResolverError else {
            return false
        }
        if case .cancelled = resolverError {
            return true
        }
        return false
    }

    private func autoloadSubtitleIfAvailable(for mediaURL: URL) {
        guard let subtitleURL = VideoSubtitleAutoloadCandidate.bestCandidate(for: mediaURL) else {
            return
        }
        loadPrimarySubtitle(
            from: subtitleURL,
            loadIntoMpv: false,
            useSelectedMpvTrackRenderer: true
        )
    }

    private func handleSubtitleImport(
        _ result: Result<[URL], any Error>
    ) {
        if let url = try? result.get().first {
            lookup.closeAll(player: model)
            loadPrimarySubtitle(from: url, loadIntoMpv: true)
        }
    }

    @discardableResult
    private func loadPrimarySubtitle(
        from url: URL,
        loadIntoMpv: Bool,
        useSelectedMpvTrackRenderer: Bool = false,
        rememberSelection: Bool = true
    ) -> Task<Void, Never> {
        if rememberSelection {
            selectedRemoteSubtitleID = nil
            selectedJimakuSubtitleID = nil
            selectedJimakuSubtitleName = nil
            selectedAJATTSubtitleID = nil
            selectedAJATTSubtitleName = nil
        }
        cancelSubtitleTrackExtraction()
        primarySubtitleLoadGeneration &+= 1
        let loadGeneration = primarySubtitleLoadGeneration
        isLoadingPrimarySubtitle = true
        let selectedTrack = model.snapshot.tracks.first {
            $0.type == .subtitle && $0.isSelected
        }
        let initialMode: VideoSubtitleRenderingMode
        if loadIntoMpv {
            initialMode = VideoSubtitleRenderingPolicy.initialMode(forSubtitleURL: url)
        } else if useSelectedMpvTrackRenderer, let selectedTrack {
            initialMode = VideoSubtitleRenderingPolicy.initialMode(for: selectedTrack)
        } else {
            initialMode = .overlayOnly
        }
        configureSubtitleRendering(initialMode)
        subtitles.clearPrimary()
        if loadIntoMpv {
            model.loadExternalSubtitle(url)
        }
        let loadTask = subtitles.load(url)
        return Task { @MainActor in
            await loadTask.value
            guard loadGeneration == primarySubtitleLoadGeneration else { return }
            isLoadingPrimarySubtitle = false
            if subtitles.document?.sourceURL.standardizedFileURL
                == url.standardizedFileURL {
                areSubtitlesVisible = true
                let logicalTrackID: Int?
                if loadIntoMpv {
                    logicalTrackID = nil
                } else {
                    logicalTrackID = model.snapshot.tracks.first {
                        $0.type == .subtitle && $0.isSelected
                    }?.id ?? selectedTrack?.id
                }
                applyPreparedSubtitleRendering(logicalTrackID: logicalTrackID)
                if rememberSelection {
                    model.rememberSubtitleSelection(
                        .external(path: url.standardizedFileURL.path)
                    )
                }
            } else if initialMode == .preparingASS {
                // Preparation owns the transition: keep the original ASS
                // hidden until parsing completes, then atomically fall back
                // to libass if no interactive document was produced.
                configureSubtitleRendering(.nativeOnly)
            }
            subtitles.update(
                time: model.snapshot.currentTime,
                subtitleDelay: model.snapshot.subtitleDelay
            )
        }
    }

    private func handleDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let accumulator = DroppedFileURLAccumulator()

        for provider in fileProviders {
            group.enter()
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                defer { group.leave() }
                guard let url = Self.fileURL(from: item) else { return }
                accumulator.append(url.standardizedFileURL)
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                handleDroppedFileURLs(accumulator.urls())
            }
        }
        return true
    }

    private func handleDroppedFileURLs(_ urls: [URL]) {
        let mediaURL = urls.first(where: isMediaFile)
        let subtitleURL = urls.first(where: isSubtitleFile)

        if let mediaURL {
            loadDroppedMedia(mediaURL, subtitleURL: subtitleURL)
        } else if let subtitleURL {
            loadDroppedSubtitle(subtitleURL)
        }
    }

    private func loadDroppedMedia(_ mediaURL: URL, subtitleURL: URL?) {
        openVideo(mediaURL, subtitleURL: subtitleURL)
    }

    private func loadDroppedSubtitle(_ subtitleURL: URL) {
        guard model.currentURL != nil else { return }
        lookup.closeAll(player: model)
        loadPrimarySubtitle(from: subtitleURL, loadIntoMpv: true)
    }

    private func isMediaFile(_ url: URL) -> Bool {
        VideoMediaTypes.isMediaFile(url)
    }

    private func isSubtitleFile(_ url: URL) -> Bool {
        Self.subtitleFileExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated private static func fileURL(from item: Any?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    private func popupView(_ popup: PopupItem, screenSize: CGSize) -> some View {
        let popupID = popup.id
        return PopupView(
            userConfig: userConfig,
            isVisible: Binding(
                get: {
                    lookup.presentation.popups
                        .first(where: { $0.id == popupID })?
                        .showPopup ?? false
                },
                set: { visible in
                    lookup.presentation.setVisibility(id: popupID, visible: visible)
                }
            ),
            selectionData: popup.currentSelection,
            lookupResults: popup.lookupResults,
            dictionaryStyles: popup.dictionaryStyles,
            screenSize: screenSize,
            isVertical: false,
            isFullWidth: false,
            bottomInset: videoControlsMetrics.popupBottomInset,
            coverURL: nil,
            documentTitle: model.currentTitle,
            profileID: profileRepository.activeProfile.id,
            clearSelection: popup.clearSelection,
            onTextSelected: { selection in
                lookup.presentation.closeChildren(of: popupID)
                return lookup.present(
                    selection: selection,
                    player: model,
                    userConfig: userConfig
                )
            },
            onTapOutside: {
                lookup.presentation.handleTapInsidePopup(id: popupID)
            },
            onSwipeDismiss: {
                lookup.dismiss(id: popupID, player: model)
            },
            miningContextProvider: { _, selectedContext in
                guard let cue = lookup.activeCue,
                      let videoURL = model.currentURL else {
                    return MiningContext(
                        sentence: popup.currentSelection?.sentence ?? "",
                        documentTitle: model.currentTitle,
                        coverURL: nil
                    )
                }
                let needsScreenshot = AnkiManager.shared.needsVideoScreenshot
                let needsAudioClip = AnkiManager.shared.needsVideoAudioClip
                let ankiMediaDirectory = (needsScreenshot || needsAudioClip)
                    ? await AnkiManager.shared.getMediaDirPath()
                    : nil
                return await VideoMiningCoordinator.context(
                    cue: cue,
                    selectedContext: selectedContext,
                    document: subtitles.document,
                    videoURL: videoURL,
                    videoTitle: model.currentTitle ?? videoURL.lastPathComponent,
                    mediaIdentity: model.currentMediaIdentity
                        ?? .localFile(path: videoURL.standardizedFileURL.path),
                    engine: model.engine,
                    captureScreenshot: needsScreenshot,
                    compressScreenshot: AnkiManager.shared.compressImages,
                    imageFormat: AnkiManager.shared.imageCompressionFormat,
                    screenshotQuality: AnkiManager.shared.imageCompressionQuality,
                    animatedAVIFMaximumHeight: AnkiManager.shared.animatedAVIFMaximumHeight,
                    animatedAVIFFramesPerSecond: AnkiManager.shared.animatedAVIFFramesPerSecond,
                    captureAudioClip: needsAudioClip,
                    audioFormat: AnkiManager.shared.audioCompressionFormat,
                    audioBitrateKbps: AnkiManager.shared.audioCompressionBitrateKbps,
                    ankiMediaDirectory: ankiMediaDirectory
                )
            }
        )
        .id(popupID)
        .zIndex(Double(100 + (
            lookup.presentation.popups.firstIndex(where: { $0.id == popupID }) ?? 0
        )))
    }

    private func registerKeyboardShortcuts() {
        guard shortcutRegistrationIDs.isEmpty else { return }

        shortcutRegistrationIDs = [
            shortcutManager.register(
                scope: .popup,
                handlers: [
                    PopupShortcutActions.dismiss.id: {
                        guard let popup = lookup.presentation.popups.last else {
                            return false
                        }
                        lookup.dismiss(id: popup.id, player: model)
                        return true
                    }
                ]
            ),
            shortcutManager.register(
                scope: .video,
                handlers: [
                    VideoShortcutActions.playPause.id: {
                        guard model.currentURL != nil else { return false }
                        model.togglePlayback()
                        return true
                    },
                    VideoShortcutActions.seekBackward.id: {
                        guard model.currentURL != nil else { return false }
                        model.skip(by: -userConfig.videoSeekInterval)
                        return true
                    },
                    VideoShortcutActions.seekForward.id: {
                        guard model.currentURL != nil else { return false }
                        model.skip(by: userConfig.videoSeekInterval)
                        return true
                    },
                    VideoShortcutActions.previousEpisode.id: {
                        guard model.playlist.previousURL != nil else { return false }
                        model.playPrevious()
                        return true
                    },
                    VideoShortcutActions.nextEpisode.id: {
                        guard model.playlist.nextURL != nil else { return false }
                        model.playNext()
                        return true
                    },
                    VideoShortcutActions.decreaseSpeed.id: {
                        setSpeedWithOSD(model.snapshot.speed - VideoPlaybackSpeed.customStep)
                        return true
                    },
                    VideoShortcutActions.increaseSpeed.id: {
                        setSpeedWithOSD(model.snapshot.speed + VideoPlaybackSpeed.customStep)
                        return true
                    },
                    VideoShortcutActions.resetSpeed.id: {
                        setSpeedWithOSD(1)
                        return true
                    },
                    VideoShortcutActions.toggleMute.id: {
                        toggleMuteWithOSD()
                        return true
                    },
                    VideoShortcutActions.volumeDown.id: {
                        adjustVolume(by: -5)
                        return true
                    },
                    VideoShortcutActions.volumeUp.id: {
                        adjustVolume(by: 5)
                        return true
                    },
                    VideoShortcutActions.mineCurrentSubtitle.id: {
                        mineCurrentSubtitle()
                        return true
                    },
                    VideoShortcutActions.previousSubtitleCue.id: {
                        seekRelativeSubtitleCue(offset: -1)
                    },
                    VideoShortcutActions.nextSubtitleCue.id: {
                        seekRelativeSubtitleCue(offset: 1)
                    },
                    VideoShortcutActions.toggleSubtitlesVisible.id: {
                        toggleSubtitlesVisible()
                        return true
                    },
                    VideoShortcutActions.toggleSubtitleGapFastForward.id: {
                        toggleSubtitleGapFastForward()
                        return true
                    },
                    VideoShortcutActions.cycleSubtitleTrack.id: {
                        cycleSubtitleTrack()
                    },
                    VideoShortcutActions.subtitleEarlier.id: {
                        adjustSubtitleDelayWithOSD(by: -0.05)
                        return true
                    },
                    VideoShortcutActions.subtitleLater.id: {
                        adjustSubtitleDelayWithOSD(by: 0.05)
                        return true
                    },
                    VideoShortcutActions.resetSubtitleTiming.id: {
                        setSubtitleDelayWithOSD(0)
                        return true
                    },
                    VideoShortcutActions.alignPreviousSubtitleToCurrentTime.id: {
                        alignAdjacentSubtitleToCurrentTime(.previous)
                    },
                    VideoShortcutActions.alignNextSubtitleToCurrentTime.id: {
                        alignAdjacentSubtitleToCurrentTime(.next)
                    },
                    VideoShortcutActions.audioEarlier.id: {
                        adjustAudioDelayWithOSD(by: -0.5)
                        return true
                    },
                    VideoShortcutActions.audioLater.id: {
                        adjustAudioDelayWithOSD(by: 0.5)
                        return true
                    },
                    VideoShortcutActions.toggleFileLoop.id: {
                        model.setLoopMode(
                            model.snapshot.loopMode == .file ? .none : .file
                        )
                        return true
                    },
                    VideoShortcutActions.setABLoopStart.id: {
                        model.setABLoopStart()
                        return true
                    },
                    VideoShortcutActions.setABLoopEnd.id: {
                        model.setABLoopEnd()
                        return true
                    },
                    VideoShortcutActions.toggleTranscript.id: {
                        toggleTranscriptSidebar()
                        return true
                    },
                    VideoShortcutActions.rotateClockwise.id: {
                        model.rotateClockwise()
                        return true
                    },
                    VideoShortcutActions.toggleFullScreen.id: {
                        guard windowChrome.hasWindow else { return false }
                        if windowChrome.isFullScreen {
                            exitFullScreen()
                            return true
                        }
                        dismissVideoPopupsThen {
                            toggleFullScreen()
                        }
                        return true
                    },
                    VideoShortcutActions.exitFocusMode.id: {
                        guard windowChrome.isFullScreen else {
                            return false
                        }
                        exitFullScreen()
                        return true
                    }
                ]
            ),
            shortcutManager.register(
                scope: .global,
                handlers: [
                    GlobalShortcutActions.open.id: {
                        dismissVideoPopupsThen {
                            presentFileImporter(.video)
                        }
                        return true
                    }
                ]
            )
        ]
    }

    private func unregisterKeyboardShortcuts() {
        shortcutRegistrationIDs.forEach(shortcutManager.unregister)
        shortcutRegistrationIDs.removeAll()
    }

    private func synchronizePlaybackPreferences() {
        model.autoPlayNext = userConfig.videoAutoPlayNext
        model.rememberPlaybackPosition = userConfig.videoRememberPlaybackPosition
        model.setSubtitleGapFastForwardEnabled(userConfig.videoSubtitleGapFastForwardEnabled)
        model.setSubtitleGapFastForwardSpeed(userConfig.videoSubtitleGapFastForwardSpeed)
        model.setHardwareDecodingEnabled(userConfig.videoHardwareDecodingEnabled)
        model.setDeinterlacingEnabled(userConfig.videoDeinterlacingEnabled)
        model.setHDREnhancementEnabled(userConfig.videoHDREnhancementEnabled)
        _ = model.setVideoShaderPreset(userConfig.videoShaderPreset)
        synchronizeVideoEqualizerPreferences()
    }

    private func toggleSubtitleGapFastForward() {
        userConfig.videoSubtitleGapFastForwardEnabled.toggle()
        model.setSubtitleGapFastForwardEnabled(userConfig.videoSubtitleGapFastForwardEnabled)
        updateSubtitleGapPlayback()
    }

    private func updateSubtitleGapPlayback() {
        model.updateSubtitleGapPlayback(
            slice: subtitles.slice(
                time: model.snapshot.currentTime,
                subtitleDelay: model.snapshot.subtitleDelay
            ),
            playbackTime: model.snapshot.currentTime - model.snapshot.subtitleDelay,
            isPlaybackPaused: !model.snapshot.isPlaying
        )
    }

    private func synchronizeVideoEqualizerPreferences() {
        model.setVideoEqualizer(.brightness, value: userConfig.videoBrightness)
        model.setVideoEqualizer(.contrast, value: userConfig.videoContrast)
        model.setVideoEqualizer(.saturation, value: userConfig.videoSaturation)
        model.setVideoEqualizer(.gamma, value: userConfig.videoGamma)
        model.setVideoEqualizer(.hue, value: userConfig.videoHue)
    }

    private var fileImporterPresentation: Binding<Bool> {
        Binding(
            get: { pendingFileImportKind != nil },
            set: { isPresented in
                if !isPresented {
                    pendingFileImportKind = nil
                }
            }
        )
    }

    private func presentFileImporter(_ kind: VideoFileImportKind) {
        activeFileImportKind = kind
        pendingFileImportKind = kind
    }

    private func toggleFullScreen() {
        if windowChrome.isFullScreen {
            exitFullScreen()
            return
        }
        windowChrome.toggleFullScreen()
    }

    private func exitFullScreen() {
        guard windowChrome.isFullScreen else { return }
        windowChrome.exitFullScreen()
    }

    private func toggleFullScreenFromPointer() {
        guard model.currentURL != nil,
              lookup.presentation.popups.isEmpty else {
            return
        }
        revealPlaybackChrome(scheduleHide: true)
        toggleFullScreen()
    }

    private func togglePlaybackFromPointer() {
        guard model.currentURL != nil,
              lookup.presentation.popups.isEmpty else {
            return
        }
        model.togglePlayback()
        revealPlaybackChrome(scheduleHide: true)
    }

    private var shouldShowPlaybackChrome: Bool {
        model.currentURL == nil
            || (
                isPointerInsidePlayerSurface
                    && (
                        isPlaybackChromeVisible
                            || hasActiveVideoPopup
                            || isInspectorVisible
                            || isMiningHistoryVisible
                            || isSpeedPanelVisible
                    )
            )
    }

    private func playbackChromeBasePosition(in size: CGSize) -> CGPoint {
        let chromeSize = playbackChromeSize(in: size)
        let halfHeight = chromeSize.height / 2
        let y = max(
            Self.playbackChromeEdgeInset + halfHeight,
            size.height - playbackChromeBottomEdgeInset - videoControlsMetrics.bottomInset - halfHeight
        )
        return CGPoint(x: size.width / 2, y: y)
    }

    private var playbackChromeBottomEdgeInset: CGFloat {
        switch userConfig.videoControlBarLayout {
        case .floating:
            Self.playbackChromeEdgeInset
        case .compactBottom:
            0
        }
    }

    private func playbackChromeCurrentOffset(in size: CGSize) -> CGSize {
        switch userConfig.videoControlBarLayout {
        case .floating:
            clampedPlaybackChromeOffset(
                CGSize(
                    width: playbackChromeStoredOffset.width + playbackChromeDragOffset.width,
                    height: playbackChromeStoredOffset.height + playbackChromeDragOffset.height
                ),
                in: size
            )
        case .compactBottom:
            .zero
        }
    }

    private func playbackChromeFrame(in size: CGSize) -> CGRect {
        let center = playbackChromeBasePosition(in: size)
        let offset = playbackChromeCurrentOffset(in: size)
        let chromeSize = playbackChromeSize(in: size)
        return CGRect(
            x: center.x + offset.width - chromeSize.width / 2,
            y: center.y + offset.height - chromeSize.height / 2,
            width: chromeSize.width,
            height: chromeSize.height
        )
    }

    private func playbackChromeSize(in size: CGSize) -> CGSize {
        VideoControlsView.chromeSize(
            for: userConfig.videoControlBarLayout,
            availableWidth: size.width
        )
    }

    private func videoSurfaceVolumeScrollExcludedRects(in size: CGSize) -> [CGRect] {
        var rects: [CGRect] = []
        if shouldShowPlaybackChrome {
            rects.append(playbackChromeFrame(in: size))
        }
        if isInspectorVisible {
            let inspectorFrame = inspectorOverlayFrame.isEmpty
                ? inspectorOverlayFallbackFrame(in: size)
                : inspectorOverlayFrame
            let visibleInspectorFrame = inspectorFrame.intersection(
                CGRect(origin: .zero, size: size)
            )
            if !visibleInspectorFrame.isNull,
               visibleInspectorFrame.width > 0,
               visibleInspectorFrame.height > 0 {
                rects.append(visibleInspectorFrame)
            }
        }
        return rects
    }

    private func inspectorOverlayFallbackFrame(in size: CGSize) -> CGRect {
        let width = min(
            size.width,
            VideoInspectorView.maximumWidth + Self.inspectorOverlayTrailingInset
        )
        return CGRect(
            x: max(0, size.width - width),
            y: 0,
            width: width,
            height: size.height
        )
    }

    private func clampedPlaybackChromeOffset(_ offset: CGSize, in size: CGSize) -> CGSize {
        let base = playbackChromeBasePosition(in: size)
        let chromeSize = playbackChromeSize(in: size)
        let halfWidth = chromeSize.width / 2
        let halfHeight = chromeSize.height / 2
        let minX = min(Self.playbackChromeEdgeInset + halfWidth, size.width / 2)
        let maxX = max(size.width - Self.playbackChromeEdgeInset - halfWidth, size.width / 2)
        let minY = min(Self.playbackChromeEdgeInset + halfHeight, size.height / 2)
        let maxY = max(size.height - playbackChromeBottomEdgeInset - halfHeight, size.height / 2)
        let x = min(max(base.x + offset.width, minX), maxX)
        let y = min(max(base.y + offset.height, minY), maxY)
        return CGSize(width: x - base.x, height: y - base.y)
    }

    private func handleVideoPointerMovement(_ phase: HoverPhase) {
        switch phase {
        case .active(_):
            let pointerLocation = NSEvent.mouseLocation
            guard lastPlaybackChromePointerLocation != pointerLocation else {
                return
            }
            lastPlaybackChromePointerLocation = pointerLocation
            isPointerInsidePlayerSurface = true
            revealPlaybackChrome(scheduleHide: true)
        case .ended:
            schedulePlaybackChromeAutoHide()
        }
    }

    private func revealPlaybackChrome(scheduleHide shouldScheduleAutoHide: Bool) {
        windowChrome.restorePlaybackCursor()
        guard model.currentURL != nil else {
            isPlaybackChromeVisible = true
            playbackChromeAutoHideTask?.cancel()
            return
        }
        if !isPlaybackChromeVisible {
            withAnimation(.smooth(duration: 0.18)) {
                isPlaybackChromeVisible = true
            }
        }
        if shouldScheduleAutoHide {
            schedulePlaybackChromeAutoHide()
        } else {
            playbackChromeAutoHideTask?.cancel()
        }
    }

    private func hidePlaybackChromeAndCursor() {
        playbackChromeAutoHideTask?.cancel()
        guard model.currentURL != nil,
              !windowChrome.isWindowGeometryTransitioning,
              !hasActiveVideoPopup,
              timelinePreviewRequestedTime == nil,
              !isInspectorVisible,
              !isMiningHistoryVisible else {
            windowChrome.restorePlaybackCursor()
            return
        }
        lastPlaybackChromePointerLocation = NSEvent.mouseLocation
        withAnimation(.smooth(duration: 0.18)) {
            isPlaybackChromeVisible = false
        }
        windowChrome.hidePlaybackCursorUntilMouseMoves()
    }

    private func playerSurfaceHoverChanged(_ hovering: Bool) {
        guard model.currentURL != nil else { return }
        isPointerInsidePlayerSurface = hovering
        if hovering {
            revealPlaybackChrome(scheduleHide: true)
        } else {
            hidePlaybackChromeForPointerExit()
        }
    }

    private func hidePlaybackChromeForPointerExit() {
        windowChrome.restorePlaybackCursor()
        guard model.currentURL != nil else { return }
        guard !windowChrome.isWindowGeometryTransitioning else { return }
        guard timelinePreviewRequestedTime == nil else { return }
        playbackChromeAutoHideTask?.cancel()
        isPointerInsidePlayerSurface = false
        withAnimation(.smooth(duration: 0.18)) {
            isPlaybackChromeVisible = false
        }
    }

    private func playbackChromeHoverChanged(_ hovering: Bool) {
        guard model.currentURL != nil else { return }
        if hovering {
            revealPlaybackChrome(scheduleHide: true)
        } else {
            schedulePlaybackChromeAutoHide()
        }
    }

    private func schedulePlaybackChromeAutoHide() {
        playbackChromeAutoHideTask?.cancel()
        guard model.currentURL != nil,
              !windowChrome.isWindowGeometryTransitioning,
              isPlaybackChromeVisible,
              !hasActiveVideoPopup,
              timelinePreviewRequestedTime == nil,
              !isInspectorVisible,
              !isMiningHistoryVisible else {
            return
        }
        playbackChromeAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            hidePlaybackChromeAndCursor()
        }
    }

    private func adjustVolume(by delta: Double) {
        setVolumeWithOSD(model.snapshot.volume + delta)
    }

    private func saveCleanScreenshot() {
        guard model.snapshot.isLoaded, !model.snapshot.isSeeking,
              !isSavingScreenshot, let sourceURL = model.currentURL else { return }
        isSavingScreenshot = true
        revealPlaybackChrome(scheduleHide: false)
        let window = NSApp.keyWindow
        let seconds = model.snapshot.currentTime
        let filename = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: ":", with: "-")
        Task { @MainActor in
            defer {
                isSavingScreenshot = false
                revealPlaybackChrome(scheduleHide: true)
            }
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("niratan-screenshot-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            do {
                // Capture before presenting the panel so playback cannot change the chosen frame.
                // PlaybackEngine uses mpv's video-only capture, excluding subtitles and window chrome.
                try await model.engine.captureScreenshot(to: temporaryURL)
                let data = try Data(contentsOf: temporaryURL)
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png]
                panel.nameFieldStringValue = "\(filename)-\(String(format: "%.3f", seconds)).png"
                let response = await withCheckedContinuation { continuation in
                    if let window {
                        panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
                    } else {
                        panel.begin { continuation.resume(returning: $0) }
                    }
                }
                guard response == .OK, let destination = panel.url else { return }
                let scoped = destination.startAccessingSecurityScopedResource()
                defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
                try data.write(to: destination, options: .atomic)
                showVideoOSD(VideoOnScreenDisplayItem(title: "Screenshot Saved", value: ""))
            } catch {
                model.errorMessage = String(localized: "Unable to save the video screenshot.")
            }
        }
    }

    private func setSpeedWithOSD(_ speed: Double) {
        let normalizedSpeed = VideoPlaybackSpeed.normalized(speed)
        model.setSpeed(normalizedSpeed)
        showSpeedOSD(normalizedSpeed)
    }

    private func setVolumeWithOSD(_ volume: Double) {
        let clampedVolume = min(max(volume, 0), 100)
        model.setVolume(clampedVolume)
        showVolumeOSD(clampedVolume)
    }

    private func toggleMuteWithOSD() {
        let isMuted = !model.snapshot.isMuted
        model.toggleMuted()
        showMuteOSD(isMuted: isMuted)
    }

    private func setSubtitleDelayWithOSD(_ delay: TimeInterval) {
        let clampedDelay = VideoSubtitleTiming.clampedDelay(delay)
        model.setSubtitleDelay(clampedDelay)
        showSubtitleDelayOSD(clampedDelay)
    }

    private func adjustSubtitleDelayWithOSD(by delta: TimeInterval) {
        setSubtitleDelayWithOSD(model.snapshot.subtitleDelay + delta)
    }

    private func subtitleAlignmentDelay(
        _ direction: SubtitleOffsetAlignmentDirection
    ) -> TimeInterval? {
        subtitles.delayAligningAdjacentCue(
            atPlaybackTime: model.snapshot.currentTime,
            subtitleDelay: model.snapshot.subtitleDelay,
            direction: direction
        )
    }

    @discardableResult
    private func alignAdjacentSubtitleToCurrentTime(
        _ direction: SubtitleOffsetAlignmentDirection
    ) -> Bool {
        guard let delay = subtitleAlignmentDelay(direction) else { return false }
        dismissVideoPopupsIfNeeded()
        setSubtitleDelayWithOSD(delay)
        return true
    }

    private func setAudioDelayWithOSD(_ delay: TimeInterval) {
        let clampedDelay = min(
            max(delay, Self.audioDelayRange.lowerBound),
            Self.audioDelayRange.upperBound
        )
        model.setAudioDelay(clampedDelay)
        showAudioDelayOSD(clampedDelay)
    }

    private func adjustAudioDelayWithOSD(by delta: TimeInterval) {
        setAudioDelayWithOSD(model.snapshot.audioDelay + delta)
    }

    private func showVideoOSD(_ item: VideoOnScreenDisplayItem) {
        videoOSDTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            videoOSD = item
        }
        videoOSDTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.35))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                videoOSD = nil
            }
            videoOSDTask = nil
        }
    }

    private func showSpeedOSD(_ speed: Double) {
        showVideoOSD(
            VideoOnScreenDisplayItem(
                title: "Speed",
                value: VideoPlaybackSpeed.label(speed)
            )
        )
    }

    private func showVolumeOSD(_ volume: Double) {
        let clampedVolume = min(max(volume, 0), 100)
        showVideoOSD(
            VideoOnScreenDisplayItem(
                title: "Volume",
                value: String(Int(clampedVolume.rounded())),
                meterProgress: clampedVolume / 100
            )
        )
    }

    private func showMuteOSD(isMuted: Bool) {
        showVideoOSD(
            VideoOnScreenDisplayItem(
                title: "Volume",
                value: isMuted ? String(localized: "Muted") : String(localized: "Unmuted"),
                meterProgress: isMuted ? 0 : min(max(model.snapshot.volume, 0), 100) / 100
            )
        )
    }

    private func showSubtitleVisibilityOSD(isVisible: Bool) {
        showVideoOSD(
            VideoOnScreenDisplayItem(
                title: "Subtitles",
                value: isVisible ? String(localized: "On") : String(localized: "Off")
            )
        )
    }

    private func showSubtitleTrackOSD(track: VideoTrack?) {
        showVideoOSD(
            VideoOnScreenDisplayItem(
                title: "Subtitle Track",
                value: track?.displayName ?? String(localized: "Off"),
                detail: track?.externalFilename.map {
                    URL(fileURLWithPath: $0).lastPathComponent
                }
            )
        )
    }

    private func showSubtitleDelayOSD(_ delay: TimeInterval) {
        showVideoOSD(
            VideoOnScreenDisplayItem(
                title: "Subtitle Delay",
                value: Self.delayOSDValue(delay)
            )
        )
    }

    private func showAudioDelayOSD(_ delay: TimeInterval) {
        showVideoOSD(
            VideoOnScreenDisplayItem(
                title: "Audio Delay",
                value: Self.delayOSDValue(delay)
            )
        )
    }

    private static func delayOSDValue(_ delay: TimeInterval) -> String {
        guard abs(delay) >= 0.005 else { return "0.00s" }
        return String(format: "%+.2fs", delay)
    }

    private var canMineCurrentSubtitle: Bool {
        userConfig.videoMiningHistoryLimit > 0
            && model.currentURL != nil
            && subtitles.document != nil
            && !subtitles.currentCues.isEmpty
    }

    private func mineCurrentSubtitle() {
        guard userConfig.videoMiningHistoryLimit > 0 else {
            showMiningHistoryNotice(.disabled)
            return
        }
        guard let videoURL = model.currentURL,
              let document = subtitles.document,
              !subtitles.currentCues.isEmpty else {
            showMiningHistoryNotice(.noSubtitle)
            return
        }

        let embeddedTrackID = document.format == .embedded
            ? model.snapshot.tracks.first {
                $0.type == .subtitle && $0.isSelected
            }?.id
            : nil
        let remoteIdentity: RemoteVideoIdentity? = {
            guard case .remoteStream(let source) = model.currentSource else { return nil }
            return source.identity
        }()
        guard miningHistory.record(
            cues: subtitles.currentCues,
            document: document,
            videoURL: videoURL,
            videoTitle: model.currentTitle ?? videoURL.lastPathComponent,
            mediaIdentity: model.currentMediaIdentity,
            remoteVideoIdentity: remoteIdentity,
            embeddedSubtitleTrackID: embeddedTrackID
        ) != nil else {
            showMiningHistoryNotice(.disabled)
            return
        }
        showMiningHistoryNotice(.saved)
    }

    private func navigateToHistoryItem(_ item: VideoMiningHistoryItem) {
        let resolution = VideoMiningHistoryNavigationResolver.resolve(
            item: item,
            currentVideoURL: model.currentURL,
            subtitleDelay: model.snapshot.subtitleDelay
        )
        switch resolution {
        case .missingVideo:
            model.errorMessage = String(
                localized: "The saved video file is no longer available. Open it again to continue."
            )
        case .missingSubtitle:
            model.errorMessage = String(
                localized: "The saved subtitle file is no longer available. Open it again to continue."
            )
        case .legacySourceUnavailable:
            model.errorMessage = String(
                localized: "Open the matching video before using this older Mining History item."
            )
        case .ready(let destination):
            restoreHistoryDestination(destination)
        }
    }

    private func restoreHistoryDestination(_ destination: VideoMiningHistoryDestination) {
        let wasPlaying = model.snapshot.isPlaying
        dismissVideoPopupsIfNeeded()
        miningHistoryNavigationTask?.cancel()
        miningHistoryNavigationGeneration &+= 1
        let generation = miningHistoryNavigationGeneration
        miningHistoryNavigationTask = Task { @MainActor in
            let destinationIdentity: VideoMediaIdentity
            let playbackSource: VideoPlaybackSource?
            switch destination.media {
            case .localFile(let url):
                destinationIdentity = .localFile(path: url.standardizedFileURL.path)
                playbackSource = .localFile(url)
            case .remote(let identity):
                destinationIdentity = identity.mediaIdentity
                if model.currentMediaIdentity == identity.mediaIdentity {
                    playbackSource = model.currentSource
                } else {
                    do {
                        let resolved = try await RemoteVideoResolverRegistry().resolve(
                            identity: identity
                        )
                        guard !Task.isCancelled,
                              generation == miningHistoryNavigationGeneration else { return }
                        playbackSource = .remoteStream(resolved)
                    } catch {
                        guard !Task.isCancelled,
                              generation == miningHistoryNavigationGeneration else { return }
                        model.errorMessage = error.localizedDescription
                        return
                    }
                }
            }
            let isChangingVideo = model.currentMediaIdentity != destinationIdentity
            if isChangingVideo {
                guard let playbackSource else { return }
                shouldSkipNextAutomaticSubtitleRestore = true
                openVideo(playbackSource, subtitleURL: destination.subtitleURL)
                guard model.errorMessage == nil else {
                    shouldSkipNextAutomaticSubtitleRestore = false
                    return
                }
                for _ in 0..<100 where !model.snapshot.isLoaded {
                    try? await Task.sleep(for: .milliseconds(10))
                    guard !Task.isCancelled,
                          generation == miningHistoryNavigationGeneration else { return }
                }
            }

            if let trackID = destination.embeddedSubtitleTrackID {
                pendingHistoryEmbeddedSubtitleTrackID = trackID
                restorePendingHistorySubtitleTrackIfAvailable()
            }

            if let subtitleURL = destination.subtitleURL,
               subtitles.document?.sourceURL.standardizedFileURL != subtitleURL {
                await loadPrimarySubtitle(
                    from: subtitleURL,
                    loadIntoMpv: true
                ).value
            }

            model.seek(to: destination.seekTime)
            subtitles.update(
                time: destination.seekTime,
                subtitleDelay: model.snapshot.subtitleDelay
            )
            areSubtitlesVisible = true

            if wasPlaying {
                model.engine.play()
            } else {
                model.engine.pause()
            }
        }
    }

    private func copyMiningHistorySubtitle(_ item: VideoMiningHistoryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.subtitleText, forType: .string)
        showMiningHistoryNotice(.copied)
    }

    private func restorePendingHistorySubtitleTrackIfAvailable() {
        guard let trackID = pendingHistoryEmbeddedSubtitleTrackID,
              model.snapshot.tracks.contains(where: {
                  $0.type == .subtitle && $0.id == trackID
              }) else {
            return
        }
        pendingHistoryEmbeddedSubtitleTrackID = nil
        selectSubtitleTrack(trackID, rememberSelection: true, showOSD: false)
    }

    private func showMiningHistoryNotice(_ notice: VideoMiningHistoryNotice) {
        miningHistoryNoticeTask?.cancel()
        withAnimation(.smooth(duration: 0.18)) {
            miningHistoryNotice = notice
        }
        miningHistoryNoticeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.18)) {
                miningHistoryNotice = nil
            }
        }
    }

    private func videoMiningHistoryNotice(
        _ notice: VideoMiningHistoryNotice
    ) -> some View {
        Label(notice.title, systemImage: notice.systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
    }

    private func seekRelativeSubtitleCue(offset: Int) -> Bool {
        guard let targetIndex = subtitles.transcript.relativeRowIndex(
            atPlaybackTime: model.snapshot.currentTime,
            subtitleDelay: model.snapshot.subtitleDelay,
            offset: offset
        ) else {
            return false
        }
        model.seek(
            to: subtitles.transcript.rows[targetIndex].startTime
                + model.snapshot.subtitleDelay
        )
        return true
    }

    private func restoreRememberedSubtitleSelectionOrAutoload() {
        guard model.pendingSubtitleSelection != nil,
              let mediaURL = model.currentURL else {
            return
        }
        restoreRememberedSubtitleSelectionOrAutoload(for: mediaURL)
    }

    private func handleVideoLoadGeneration() {
        if shouldSkipNextAutomaticSubtitleRestore {
            shouldSkipNextAutomaticSubtitleRestore = false
            _ = model.consumePendingSubtitleSelection()
            if model.subtitlePreservingLoadGeneration == model.loadGeneration {
                restorePreservedSubtitleRenderingAfterMediaReload()
            }
            return
        }
        if model.subtitlePreservingLoadGeneration == model.loadGeneration {
            _ = model.consumePendingSubtitleSelection()
            restorePreservedSubtitleRenderingAfterMediaReload()
            return
        }
        lookup.closeAll(player: model)
        cancelSubtitleTrackExtraction()
        invalidatePrimarySubtitleLoad()
        subtitles.clear()
        guard let mediaURL = model.currentURL else { return }
        restoreRememberedSubtitleSelectionOrAutoload(for: mediaURL)
    }

    private func restorePreservedSubtitleRenderingAfterMediaReload() {
        guard let document = subtitles.document else {
            configureSubtitleRendering(.overlayOnly)
            return
        }
        guard document.assRenderPlan != nil else {
            configureSubtitleRendering(.overlayOnly)
            return
        }

        // A source reload removes mpv's external/internal subtitle tracks.
        // Keep ASS hit targets disabled until the original logical track is
        // back, then the next track snapshot reinstalls the filtered effects
        // track through `synchronizeSelectedSubtitleTrack()`.
        configureSubtitleRendering(.nativeOnly)
        if document.format == .ass || document.format == .ssa {
            model.loadExternalSubtitle(document.sourceURL)
        }
    }

    private func restoreRememberedSubtitleSelectionOrAutoload(
        for mediaURL: URL
    ) {
        guard let selection = model.pendingSubtitleSelection else {
            autoloadSubtitleIfAvailable(for: mediaURL)
            return
        }
        let resolution = VideoSubtitleRestoreResolver.resolve(
            selection: selection,
            tracks: model.snapshot.tracks,
            isLoaded: model.snapshot.isLoaded
        )
        switch resolution {
        case .off:
            _ = model.consumePendingSubtitleSelection()
            applySubtitlesOff(clearPrimary: true, rememberSelection: false)
        case .external(let subtitleURL):
            _ = model.consumePendingSubtitleSelection()
            loadPrimarySubtitle(
                from: subtitleURL,
                loadIntoMpv: true,
                rememberSelection: false
            )
        case .embeddedTrack(let trackID):
            _ = model.consumePendingSubtitleSelection()
            selectSubtitleTrack(trackID, rememberSelection: false, showOSD: false)
        case .remoteLanguage(let language):
            _ = model.consumePendingSubtitleSelection()
            guard case .remoteStream(let source) = model.currentSource,
                  let subtitle = source.preferredSubtitle(language: language) else {
                autoloadSubtitleIfAvailable(for: mediaURL)
                return
            }
            loadRemoteSubtitle(subtitle, rememberSelection: false)
        case .remoteOption(let identity):
            _ = model.consumePendingSubtitleSelection()
            guard case .remoteStream(let source) = model.currentSource,
                  let subtitle = source.subtitleOption(matching: identity) else {
                autoloadSubtitleIfAvailable(for: mediaURL)
                return
            }
            loadRemoteSubtitle(subtitle, rememberSelection: false)
        case .waitingForTracks:
            break
        case .unavailable:
            _ = model.consumePendingSubtitleSelection()
            autoloadSubtitleIfAvailable(for: mediaURL)
        }
    }

    private func selectSubtitleTrack(
        _ trackID: Int,
        rememberSelection: Bool,
        showOSD: Bool = true
    ) {
        guard let track = model.snapshot.tracks.first(where: {
            $0.type == .subtitle && $0.id == trackID
        }) else {
            return
        }
        lastSelectedSubtitleTrackID = trackID
        if track.isSelected && areSubtitlesVisible && subtitles.document?.format == .embedded {
            synchronizeSelectedSubtitleTrack()
        } else {
            areSubtitlesVisible = true
            cancelSubtitleTrackExtraction()
            invalidatePrimarySubtitleLoad()
            selectedRemoteSubtitleID = nil
            selectedJimakuSubtitleID = nil
            selectedJimakuSubtitleName = nil
            selectedAJATTSubtitleID = nil
            selectedAJATTSubtitleName = nil
            configureSubtitleRendering(VideoSubtitleRenderingPolicy.initialMode(for: track))
            subtitles.clearPrimary()
            model.selectTrack(type: .subtitle, id: trackID)
        }
        if showOSD {
            showSubtitleTrackOSD(track: track)
        }
        guard rememberSelection else { return }
        if let filename = track.externalFilename, !filename.isEmpty {
            model.rememberSubtitleSelection(
                .external(path: URL(fileURLWithPath: filename).standardizedFileURL.path)
            )
        } else {
            model.rememberSubtitleSelection(
                .embedded(VideoSubtitleTrackIdentity(track: track))
            )
        }
    }

    private func applySubtitlesOff(
        clearPrimary: Bool,
        rememberSelection: Bool
    ) {
        cancelSubtitleTrackExtraction()
        invalidatePrimarySubtitleLoad()
        subtitles.cancelPendingPrimaryLoad()
        configureSubtitleRendering(.overlayOnly)
        if clearPrimary {
            subtitles.clearPrimary()
            selectedRemoteSubtitleID = nil
            selectedJimakuSubtitleID = nil
            selectedJimakuSubtitleName = nil
            selectedAJATTSubtitleID = nil
            selectedAJATTSubtitleName = nil
            lastSelectedSubtitleTrackID = nil
        }
        subtitles.discardTemporaryASSEffects()
        model.selectTrack(type: .subtitle, id: nil)
        areSubtitlesVisible = false
        if rememberSelection {
            model.rememberSubtitleSelection(.off)
        }
    }

    private func toggleSubtitlesVisible() {
        if areSubtitlesVisible {
            lastSelectedSubtitleTrackID = model.snapshot.tracks
                .first { $0.type == .subtitle && $0.isSelected }?
                .id
            applySubtitlesOff(clearPrimary: false, rememberSelection: true)
            showSubtitleVisibilityOSD(isVisible: areSubtitlesVisible)
        } else {
            if let document = subtitles.document,
               document.format != .embedded {
                areSubtitlesVisible = true
                if let trackID = lastSelectedSubtitleTrackID,
                   model.snapshot.tracks.contains(where: {
                       $0.type == .subtitle && $0.id == trackID
                   }) {
                    model.selectTrack(type: .subtitle, id: trackID)
                }
                applyPreparedSubtitleRendering(
                    logicalTrackID: lastSelectedSubtitleTrackID
                )
                if let selectedRemoteSubtitleID,
                   let option = currentRemoteSubtitleOptions.first(where: {
                       $0.id == selectedRemoteSubtitleID
                   }) {
                    model.rememberSubtitleSelection(
                        .remoteOption(option.selectionIdentity)
                    )
                } else {
                    model.rememberSubtitleSelection(
                        .external(path: document.sourceURL.standardizedFileURL.path)
                    )
                }
                showSubtitleVisibilityOSD(isVisible: areSubtitlesVisible)
                return
            }
            let subtitleTracks = model.snapshot.tracks.filter { $0.type == .subtitle }
            let trackID = lastSelectedSubtitleTrackID
                .flatMap { id in subtitleTracks.first { $0.id == id }?.id }
                ?? subtitleTracks.first?.id
            if let trackID {
                selectSubtitleTrack(trackID, rememberSelection: true, showOSD: false)
                showSubtitleVisibilityOSD(isVisible: areSubtitlesVisible)
            }
        }
    }

    private func cycleSubtitleTrack() -> Bool {
        let subtitleTracks = model.snapshot.tracks.filter { $0.type == .subtitle }
        guard !subtitleTracks.isEmpty else { return false }
        guard areSubtitlesVisible else {
            let trackID = lastSelectedSubtitleTrackID
                .flatMap { id in subtitleTracks.first { $0.id == id }?.id }
                ?? subtitleTracks.first?.id
            if let trackID {
                selectSubtitleTrack(trackID, rememberSelection: true)
            }
            return true
        }
        if let selectedIndex = subtitleTracks.firstIndex(where: \.isSelected) {
            let nextIndex = subtitleTracks.index(after: selectedIndex)
            if nextIndex < subtitleTracks.endIndex {
                let id = subtitleTracks[nextIndex].id
                selectSubtitleTrack(id, rememberSelection: true)
            } else {
                lastSelectedSubtitleTrackID = subtitleTracks[selectedIndex].id
                applySubtitlesOff(clearPrimary: false, rememberSelection: true)
                showSubtitleTrackOSD(track: nil)
            }
        } else {
            let id = subtitleTracks[0].id
            selectSubtitleTrack(id, rememberSelection: true)
        }
        return true
    }

    private func toggleMiningHistory() {
        videoScreenLog.info(
            "Toggling video mining history visible=\(self.isMiningHistoryVisible)"
        )
        if isMiningHistoryVisible, selectedStudySidebarTab == .history {
            isMiningHistoryVisible = false
        } else {
            selectedStudySidebarTab = .history
            isMiningHistoryVisible = true
        }
    }

    private func toggleTranscriptSidebar() {
        dismissVideoPopupsThen {
            if isMiningHistoryVisible, selectedStudySidebarTab == .transcript {
                isMiningHistoryVisible = false
            } else {
                selectedStudySidebarTab = .transcript
                isMiningHistoryVisible = true
                isInspectorVisible = false
            }
        }
    }

    private var hasActiveVideoPopup: Bool {
        !lookup.presentation.popups.isEmpty
    }

    private var hasVisibleVideoPopup: Bool {
        lookup.presentation.popups.contains { $0.showPopup }
    }

    private var shouldShowVideoDismissLayer: Bool {
        hasActiveVideoPopup || isInspectorVisible || isSpeedPanelVisible
    }

    private var shouldHandleVideoSurfaceVolumeScroll: Bool {
        model.currentURL != nil
            && !hasActiveVideoPopup
    }

    private func dismissVideoPopupsIfNeeded() {
        guard hasActiveVideoPopup else { return }
        videoScreenLog.info("Dismissing active video lookup popups")
        lookup.closeAll(player: model)
    }

    private func dismissVideoPopupsThen(_ action: @escaping () -> Void) {
        guard hasActiveVideoPopup else {
            action()
            return
        }
        videoScreenLog.info("Deferring video action until lookup popup stack closes")
        lookup.closeAll(player: model) {
            action()
        }
    }

    private func dismissVideoOverlaysFromCanvas() {
        dismissVideoPopupsIfNeeded()
        if isSpeedPanelVisible {
            withAnimation(.smooth(duration: 0.16)) {
                isSpeedPanelVisible = false
            }
        }
        if isInspectorVisible {
            videoScreenLog.info("Closing video inspector from canvas tap")
            isInspectorVisible = false
        }
    }

    private func toggleInspector(tab: VideoInspectorTab? = nil) {
        videoScreenLog.info(
            "Toggling video inspector visible=\(self.isInspectorVisible) requestedTab=\(tab?.rawValue ?? "none")"
        )
        if let tab {
            if isInspectorVisible, selectedInspectorTab == tab {
                isInspectorVisible = false
            } else {
                selectedInspectorTab = tab
                isInspectorVisible = true
            }
            return
        }

        isInspectorVisible.toggle()
    }

    private func installEmbeddedSubtitleHandler() {
        model.engine.onEmbeddedSubtitleCuesChanged = { cues in
            guard let sourceURL = model.currentURL else { return }
            subtitles.loadEmbedded(cues, sourceURL: sourceURL)
            subtitles.update(
                time: model.snapshot.currentTime,
                subtitleDelay: model.snapshot.subtitleDelay
            )
        }
    }

    private func synchronizeSelectedSubtitleTrack() {
        guard !isLoadingPrimarySubtitle else { return }
        guard let videoURL = model.currentURL else {
            cancelSubtitleTrackExtraction()
            return
        }
        guard let track = model.snapshot.tracks.first(where: {
            $0.type == .subtitle && $0.isSelected
        }) else {
            cancelSubtitleTrackExtraction()
            configureSubtitleRendering(
                subtitles.document?.assRenderPlan == nil ? .overlayOnly : .nativeOnly
            )
            if subtitles.document?.format == .embedded,
               model.subtitlePreservingLoadGeneration != model.loadGeneration {
                subtitles.clearPrimary()
            }
            return
        }
        if let format = subtitles.document?.format, format != .embedded {
            if subtitles.document?.assRenderPlan != nil {
                applyPreparedSubtitleRendering(logicalTrackID: track.id)
            } else {
                configureSubtitleRendering(VideoSubtitleRenderingPolicy.initialMode(for: track))
            }
            return
        }

        let key = [
            videoURL.standardizedFileURL.path,
            String(track.id),
            String(track.ffIndex ?? -1),
            track.externalFilename ?? ""
        ].joined(separator: "|")
        guard key != activeSubtitleTrackExtractionKey else {
            if subtitles.document?.assRenderPlan != nil {
                applyPreparedSubtitleRendering(logicalTrackID: track.id)
            } else if VideoSubtitleRenderingPolicy.initialMode(for: track) == .preparingASS,
                      subtitles.transcriptErrorMessage != nil {
                // Keep a failed extraction on its native fallback instead of
                // re-entering the hidden preparation state on track updates.
                configureSubtitleRendering(.nativeOnly)
            } else {
                configureSubtitleRendering(VideoSubtitleRenderingPolicy.initialMode(for: track))
            }
            return
        }

        // Clear a split effects track before `beginEmbeddedTrack` releases
        // its temporary file. A changed extraction key belongs to the new
        // media/track even when mpv reused the same transient track ID.
        configureSubtitleRendering(VideoSubtitleRenderingPolicy.initialMode(for: track))
        subtitleTrackExtractionTask?.cancel()
        activeSubtitleTrackExtractionKey = key
        subtitles.beginEmbeddedTrack(trackID: track.id, sourceURL: videoURL)

        subtitleTrackExtractionTask = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) {
                do {
                    let isCancelled: @Sendable () -> Bool = {
                        withUnsafeCurrentTask { $0?.isCancelled ?? false }
                    }
                    let extractedTrack = try VideoSubtitleTrackExtractor.extract(
                        videoURL: videoURL,
                        track: track,
                        isCancelled: isCancelled
                    )
                    guard !isCancelled() else {
                        return SubtitleTrackExtractionOutcome.cancelled
                    }
                    let load = try VideoSubtitleController.prepareEmbeddedTranscript(
                        extractedTrack,
                        sourceURL: videoURL,
                        isCancelled: isCancelled
                    )
                    guard !isCancelled() else {
                        load.discardTemporaryResources()
                        return SubtitleTrackExtractionOutcome.cancelled
                    }
                    return SubtitleTrackExtractionOutcome.success(load)
                } catch is CancellationError {
                    return SubtitleTrackExtractionOutcome.cancelled
                } catch {
                    return SubtitleTrackExtractionOutcome.failure(
                        error.localizedDescription
                    )
                }
            }
            let outcome = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled,
                  activeSubtitleTrackExtractionKey == key else {
                if case .success(let load) = outcome {
                    load.discardTemporaryResources()
                }
                return
            }
            switch outcome {
            case .success(let load):
                subtitles.replaceEmbeddedTranscript(
                    load,
                    trackID: track.id
                )
                applyPreparedSubtitleRendering(logicalTrackID: track.id)
                subtitles.update(
                    time: model.snapshot.currentTime,
                    subtitleDelay: model.snapshot.subtitleDelay
                )
            case .failure(let message):
                subtitles.failEmbeddedTranscript(message, trackID: track.id)
                if let codec = track.codec?.lowercased(),
                   codec == "ass" || codec == "ssa" {
                    configureSubtitleRendering(.nativeOnly)
                    subtitles.errorMessage = String(
                        localized: "Unable to prepare interactive ASS subtitles. The original subtitle will be shown instead."
                    )
                }
            case .cancelled:
                break
            }
        }
    }

    private func cancelSubtitleTrackExtraction() {
        subtitleTrackExtractionTask?.cancel()
        subtitleTrackExtractionTask = nil
        activeSubtitleTrackExtractionKey = nil
    }

    private func invalidatePrimarySubtitleLoad() {
        primarySubtitleLoadGeneration &+= 1
        isLoadingPrimarySubtitle = false
    }

    private func applyPreparedSubtitleRendering(logicalTrackID: Int?) {
        guard let document = subtitles.document else {
            configureSubtitleRendering(.overlayOnly)
            return
        }
        guard let renderPlan = document.assRenderPlan else {
            let mode: VideoSubtitleRenderingMode
            switch document.format {
            case .ass, .ssa:
                mode = .nativeOnly
            case .srt, .webVTT, .embedded:
                mode = .overlayOnly
            }
            configureSubtitleRendering(mode)
            return
        }
        guard renderPlan.hasPrimaryDialogue else {
            configureSubtitleRendering(.nativeOnly)
            return
        }
        guard renderPlan.effectsOnlyData != nil else {
            configureSubtitleRendering(.overlayOnly)
            return
        }
        guard subtitles.prepareTemporaryASSEffectsIfNeeded(),
              !subtitles.assEffectsPreparationFailed,
              let effectsURL = subtitles.assEffectsURL else {
            subtitles.errorMessage = String(
                localized: "Unable to prepare interactive ASS subtitles. The original subtitle will be shown instead."
            )
            configureSubtitleRendering(.nativeOnly)
            return
        }
        configureSubtitleRendering(
            .splitASS(
                effectsURL: effectsURL,
                logicalTrackID: logicalTrackID
            )
        )
    }

    @discardableResult
    private func configureSubtitleRendering(_ mode: VideoSubtitleRenderingMode) -> Bool {
        guard model.configureSubtitleRendering(mode) else {
            if case .splitASS = mode {
                subtitles.markASSEffectsInstallationFailed()
            }
            subtitleRenderingMode = .nativeOnly
            _ = model.configureSubtitleRendering(.nativeOnly)
            subtitles.errorMessage = String(
                localized: "Unable to prepare interactive ASS subtitles. The original subtitle will be shown instead."
            )
            return false
        }
        subtitleRenderingMode = mode
        return true
    }
}

private struct VideoTitlebarBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .titlebar
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private enum VideoVolumeScrollDelta {
    private static let wheelStep = 5.0
    private static let preciseScale = 0.5
    private static let maximumPreciseStep = 5.0
    private static let minimumPreciseStep = 0.1

    static func adjustment(
        deltaX: Double,
        deltaY: Double,
        hasPreciseScrollingDeltas: Bool
    ) -> Double? {
        guard deltaY.isFinite,
              abs(deltaY) >= 0.01,
              abs(deltaY) >= abs(deltaX) else {
            return nil
        }

        guard hasPreciseScrollingDeltas else {
            return deltaY > 0 ? Self.wheelStep : -Self.wheelStep
        }

        let preciseDelta = deltaY * Self.preciseScale
        guard abs(preciseDelta) >= Self.minimumPreciseStep else { return nil }
        return min(max(preciseDelta, -Self.maximumPreciseStep), Self.maximumPreciseStep)
    }
}

private struct VideoSurfaceScrollBridge: NSViewRepresentable {
    let isEnabled: Bool
    let excludedRects: [CGRect]
    var onScroll: (Double) -> Void

    func makeNSView(context: Context) -> VideoSurfaceScrollMonitorView {
        let view = VideoSurfaceScrollMonitorView()
        view.isEnabled = isEnabled
        view.excludedRects = excludedRects
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: VideoSurfaceScrollMonitorView, context: Context) {
        view.isEnabled = isEnabled
        view.excludedRects = excludedRects
        view.onScroll = onScroll
    }
}

private final class VideoSurfaceScrollMonitorView: NSView {
    var isEnabled = false
    var excludedRects: [CGRect] = []
    var onScroll: ((Double) -> Void)?

    nonisolated(unsafe) private var scrollMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resetScrollMonitor()
    }

    deinit {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
    }

    private func resetScrollMonitor() {
        removeScrollMonitor()
        guard window != nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            guard let delta = self.scrollDelta(for: event) else { return event }
            self.onScroll?(delta)
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    private func scrollDelta(for event: NSEvent) -> Double? {
        guard isEnabled,
              let window,
              event.window === window else {
            return nil
        }
        let localPoint = convert(event.locationInWindow, from: nil)
        guard bounds.contains(localPoint) else { return nil }
        if excludedRects.contains(where: { $0.contains(localPoint) }) {
            return nil
        }
        return VideoVolumeScrollDelta.adjustment(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        )
    }
}

private struct VideoInspectorOverlayFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private enum SubtitleTrackExtractionOutcome: Sendable {
    case success(PreparedSubtitleLoad)
    case failure(String)
    case cancelled
}

private enum VideoFileImportKind {
    case video
    case primarySubtitle

    func allowedContentTypes(
        mediaTypes: [UTType],
        subtitleTypes: [UTType]
    ) -> [UTType] {
        switch self {
        case .video:
            mediaTypes
        case .primarySubtitle:
            subtitleTypes
        }
    }
}

private enum VideoMiningHistoryNotice: String, Identifiable {
    case saved
    case copied
    case noSubtitle
    case disabled

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .saved:
            "Saved to Mining History"
        case .copied:
            "Subtitle Copied"
        case .noSubtitle:
            "No subtitle is active at the current time."
        case .disabled:
            "Mining History is disabled in Video Settings."
        }
    }

    var systemImage: String {
        switch self {
        case .saved, .copied:
            "checkmark.circle.fill"
        case .noSubtitle, .disabled:
            "exclamationmark.triangle.fill"
        }
    }
}
