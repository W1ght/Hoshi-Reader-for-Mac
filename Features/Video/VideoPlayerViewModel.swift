import Foundation
import Observation

@Observable
@MainActor
final class VideoPlayerViewModel {
    private static let audioDelayRange: ClosedRange<TimeInterval> = -30...30
    private static let defaultSubtitleGapFastForwardSpeed = 2.7
    private static let subtitleGapFastForwardEdgeGuard: TimeInterval = 0.6

    let engine: any PlaybackEngine
    var snapshot = VideoPlaybackSnapshot()
    var inspectorState = VideoInspectorState()
    var currentURL: URL?
    private(set) var currentMediaIdentity: VideoMediaIdentity?
    private(set) var currentTitle: String?
    private(set) var currentSource: VideoPlaybackSource?
    var errorMessage: String?
    var playlist = VideoPlaylist(urls: [], currentURL: nil)
    var autoPlayNext: Bool
    var rememberPlaybackPosition: Bool {
        didSet {
            if !rememberPlaybackPosition {
                pendingRestorePosition = nil
                pendingPlaybackState = nil
                pendingSubtitleSelection = nil
            }
        }
    }
    private(set) var loadGeneration = 0
    private(set) var subtitlePreservingLoadGeneration: Int?
    private(set) var pendingABLoopStart: TimeInterval?
    private(set) var pendingSubtitleSelection: VideoSubtitleSelection?

    private var isAccessingSecurityScopedURL = false
    private let historyStore: VideoPlaybackHistoryStore
    private let remoteResolverRegistry: RemoteVideoResolverRegistry
    @ObservationIgnored private var playlistScanTask: Task<Void, Never>?
    @ObservationIgnored private var remoteRecoveryTask: Task<Void, Never>?
    private var remotePlaybackSession: RemotePlaybackSession?
    private var remotePlaybackGeneration: Int?
    private var pendingPlaybackState: VideoPlaybackState?
    private var pendingRestorePosition: TimeInterval?
    private var pendingPlaybackIntent: Bool?
    private var lastLoadedPlaybackWasPlaying: Bool?
    private var subtitleGapFastForwardSpeed = defaultSubtitleGapFastForwardSpeed
    private var subtitleGapFastForwardBaseSpeed: Double?
    private(set) var isSubtitleGapFastForwardEnabled = false
    private var lastSavedSecond = -1
    private var requestedRotation = 0

    init(
        engine: any PlaybackEngine,
        historyStore: VideoPlaybackHistoryStore = VideoPlaybackHistoryStore(),
        remoteResolverRegistry: RemoteVideoResolverRegistry = RemoteVideoResolverRegistry(),
        autoPlayNext: Bool = true,
        rememberPlaybackPosition: Bool = true
    ) {
        self.engine = engine
        self.historyStore = historyStore
        self.remoteResolverRegistry = remoteResolverRegistry
        self.autoPlayNext = autoPlayNext
        self.rememberPlaybackPosition = rememberPlaybackPosition
        engine.onSnapshotChanged = { [weak self] snapshot in
            self?.handleSnapshot(snapshot)
        }
        engine.onError = { [weak self] message in
            self?.errorMessage = message
        }
        engine.onRemotePlaybackFailure = { [weak self] failure in
            self?.recoverRemotePlayback(from: failure)
        }
        engine.onPlaybackEnded = { [weak self] in
            guard self?.autoPlayNext == true else { return }
            self?.playNext()
        }
    }

    isolated deinit {
        playlistScanTask?.cancel()
        remoteRecoveryTask?.cancel()
        if isAccessingSecurityScopedURL {
            currentURL?.stopAccessingSecurityScopedResource()
        }
    }

    func open(_ url: URL, startsFromBeginning: Bool = false) {
        open(.localFile(url), startsFromBeginning: startsFromBeginning)
    }

    func open(
        _ source: VideoPlaybackSource,
        startsFromBeginning: Bool = false
    ) {
        let url = source.displayURL
        playlistScanTask?.cancel()
        playlist = VideoPlaylist(urls: [url], currentURL: url)
        openPlaylistItem(
            url,
            source: source,
            startsFromBeginning: startsFromBeginning
        )
        if case .localFile = source {
            configurePlaylistInBackground(around: url)
        }
    }

    @discardableResult
    func switchRemoteQuality(to source: ResolvedRemoteVideoSource) -> Bool {
        guard case .remoteStream(let currentSource) = currentSource,
              currentSource.identity.mediaIdentity == source.identity.mediaIdentity else {
            return false
        }
        let playbackSource = VideoPlaybackSource.remoteStream(source)
        openPlaylistItem(
            playbackSource.displayURL,
            source: playbackSource,
            restorePositionOverride: snapshot.currentTime,
            playbackIntentOverride: snapshot.isPlaying,
            preserveSubtitleOverlay: true
        )
        return true
    }

    func playPrevious() {
        guard let url = playlist.previousURL else { return }
        openPlaylistItem(url)
    }

    func playNext() {
        guard let url = playlist.nextURL else { return }
        openPlaylistItem(url)
    }

    func selectPlaylistItem(_ url: URL) {
        guard playlist.items.contains(where: {
            $0.standardizedFileURL == url.standardizedFileURL
        }) else {
            return
        }
        openPlaylistItem(url)
    }

    private func openPlaylistItem(
        _ url: URL,
        source: VideoPlaybackSource? = nil,
        restorePositionOverride: TimeInterval? = nil,
        playbackIntentOverride: Bool? = nil,
        preserveSubtitleOverlay: Bool = false,
        startsFromBeginning: Bool = false
    ) {
        saveCurrentPosition(deferred: false)
        restoreSubtitleGapFastForwardSpeedIfNeeded()
        remoteRecoveryTask?.cancel()
        remoteRecoveryTask = nil
        remotePlaybackSession = nil
        remotePlaybackGeneration = nil
        stopAccessingCurrentURL()
        let playbackSource = source ?? .localFile(url)
        if startsFromBeginning {
            historyStore.clearProgress(for: playbackSource.mediaIdentity)
        }
        currentURL = playbackSource.displayURL
        currentMediaIdentity = playbackSource.mediaIdentity
        currentTitle = playbackSource.title
        currentSource = playbackSource
        playlist.select(url)
        let playbackState = rememberPlaybackPosition
            ? historyStore.playbackState(for: playbackSource.mediaIdentity)
            : nil
        pendingPlaybackState = playbackState?.resumeOptions.isEmpty == false
            ? playbackState
            : nil
        pendingRestorePosition = if startsFromBeginning {
            0
        } else {
            restorePositionOverride.map { max(0, $0) }
                ?? (playbackState?.isResumable == true ? playbackState?.position : nil)
        }
        pendingPlaybackIntent = playbackIntentOverride
        lastLoadedPlaybackWasPlaying = playbackIntentOverride
        pendingSubtitleSelection = rememberPlaybackPosition
            ? historyStore.subtitleSelection(for: playbackSource.mediaIdentity)
            : nil
        lastSavedSecond = -1
        requestedRotation = 0
        if case .localFile = playbackSource {
            isAccessingSecurityScopedURL = url.startAccessingSecurityScopedResource()
        } else {
            isAccessingSecurityScopedURL = false
        }
        if case .remoteStream(let remoteSource) = playbackSource {
            let resolverRegistry = remoteResolverRegistry
            remotePlaybackSession = RemotePlaybackSession(
                source: remoteSource,
                preferredSubtitleLanguages: [remoteSource.selectedSubtitleLanguage].compactMap { $0 }
            ) { identity, preferredLanguages, forceRefresh in
                try await resolverRegistry.resolve(
                    identity: identity,
                    preferredSubtitleLanguages: preferredLanguages,
                    forceRefresh: forceRefresh
                )
            }
            remotePlaybackGeneration = 1
        }
        do {
            try engine.load(source: playbackSource)
            publishLoadGeneration(
                preserveSubtitleOverlay: preserveSubtitleOverlay
            )
            snapshot = engine.snapshot
            inspectorState = VideoInspectorState(snapshot: snapshot)
            errorMessage = nil
        } catch {
            if case .remoteStream = playbackSource {
                recoverRemotePlayback(from: .remoteLoadFailed)
            } else {
                errorMessage = error.localizedDescription
                pendingPlaybackState = nil
                pendingRestorePosition = nil
                pendingPlaybackIntent = nil
                pendingSubtitleSelection = nil
                stopAccessingCurrentURL()
            }
        }
    }

    func togglePlayback() {
        snapshot.isPlaying ? engine.pause() : engine.play()
    }

    func seek(to time: TimeInterval) {
        restoreSubtitleGapFastForwardSpeedIfNeeded()
        engine.seek(to: min(max(time, 0), snapshot.duration))
    }

    func skip(by interval: TimeInterval) {
        seek(to: snapshot.currentTime + interval)
    }

    func setSpeed(_ speed: Double) {
        let normalizedSpeed = VideoPlaybackSpeed.normalized(speed)
        if subtitleGapFastForwardBaseSpeed != nil {
            subtitleGapFastForwardBaseSpeed = normalizedSpeed
            return
        }
        engine.setSpeed(normalizedSpeed)
    }

    func adjustSpeed(by delta: Double) {
        setSpeed(currentUserSpeed + delta)
    }

    func setSubtitleGapFastForwardEnabled(_ enabled: Bool) {
        guard isSubtitleGapFastForwardEnabled != enabled else { return }
        isSubtitleGapFastForwardEnabled = enabled
        if !enabled {
            restoreSubtitleGapFastForwardSpeedIfNeeded()
        }
    }

    func setSubtitleGapFastForwardSpeed(_ speed: Double) {
        subtitleGapFastForwardSpeed = Self.normalizedSubtitleGapFastForwardSpeed(speed)
        if subtitleGapFastForwardBaseSpeed != nil
            && abs(snapshot.speed - subtitleGapFastForwardSpeed) >= 0.001 {
            engine.setSpeed(subtitleGapFastForwardSpeed)
        }
    }

    func updateSubtitleGapPlayback(
        slice: SubtitleCueSlice,
        playbackTime: TimeInterval,
        isPlaybackPaused: Bool
    ) {
        guard isSubtitleGapFastForwardEnabled, !isPlaybackPaused else {
            restoreSubtitleGapFastForwardSpeedIfNeeded()
            return
        }
        guard shouldFastForwardSubtitleGap(slice: slice, playbackTime: playbackTime) else {
            restoreSubtitleGapFastForwardSpeedIfNeeded()
            return
        }
        if subtitleGapFastForwardBaseSpeed == nil {
            subtitleGapFastForwardBaseSpeed = snapshot.speed
        }
        if abs(snapshot.speed - subtitleGapFastForwardSpeed) >= 0.001 {
            engine.setSpeed(subtitleGapFastForwardSpeed)
        }
    }

    func setVolume(_ volume: Double) {
        engine.setVolume(min(max(volume, 0), 100))
    }

    func toggleMuted() {
        engine.setMuted(!snapshot.isMuted)
    }

    func setSubtitleDelay(_ delay: TimeInterval) {
        engine.setSubtitleDelay(VideoSubtitleTiming.clampedDelay(delay))
    }

    func adjustSubtitleDelay(by delta: TimeInterval) {
        setSubtitleDelay(snapshot.subtitleDelay + delta)
    }

    func setAudioDelay(_ delay: TimeInterval) {
        engine.setAudioDelay(
            min(max(delay, Self.audioDelayRange.lowerBound), Self.audioDelayRange.upperBound)
        )
    }

    func adjustAudioDelay(by delta: TimeInterval) {
        setAudioDelay(snapshot.audioDelay + delta)
    }

    func setLoopMode(_ mode: VideoLoopMode) {
        engine.setLoopMode(mode)
    }

    func setABLoopStart() {
        setABLoopStart(at: snapshot.currentTime)
    }

    func setABLoopStart(at time: TimeInterval) {
        pendingABLoopStart = clampedPlaybackTime(time)
        if snapshot.abLoop != nil {
            engine.setABLoop(nil)
        }
    }

    func setABLoopEnd() {
        setABLoopEnd(at: snapshot.currentTime)
    }

    func setABLoopEnd(at time: TimeInterval) {
        guard let start = pendingABLoopStart ?? snapshot.abLoop?.start else {
            return
        }
        let end = clampedPlaybackTime(time)
        guard end > start else { return }
        engine.setABLoop(VideoABLoop(start: start, end: end))
        pendingABLoopStart = nil
    }

    func clearABLoop() {
        pendingABLoopStart = nil
        engine.setABLoop(nil)
    }

    func setAspectRatio(_ aspectRatio: VideoAspectRatio) {
        engine.setAspectRatio(aspectRatio)
    }

    func rotateClockwise() {
        requestedRotation = (requestedRotation + 90) % 360
        engine.setRotation(requestedRotation)
    }

    func setHardwareDecodingEnabled(_ enabled: Bool) {
        engine.setHardwareDecodingEnabled(enabled)
    }

    func setDeinterlacingEnabled(_ enabled: Bool) {
        engine.setDeinterlacingEnabled(enabled)
    }

    func setHDREnhancementEnabled(_ enabled: Bool) {
        engine.setHDREnhancementEnabled(enabled)
    }

    @discardableResult
    func setVideoShaderPreset(_ preset: VideoShaderPreset) -> Bool {
        do {
            try engine.setVideoShaderPreset(preset)
            return true
        } catch {
            if preset != .off {
                try? engine.setVideoShaderPreset(.off)
            }
            return false
        }
    }

    func setVideoEqualizer(_ adjustment: VideoEqualizerAdjustment, value: Double) {
        engine.setVideoEqualizer(
            adjustment,
            value: VideoEqualizerAdjustment.normalized(value)
        )
    }

    private func clampedPlaybackTime(_ time: TimeInterval) -> TimeInterval {
        guard snapshot.duration > 0 else {
            return max(time, 0)
        }
        return min(max(time, 0), snapshot.duration)
    }

    func seekToChapter(_ index: Int) {
        engine.seekToChapter(index)
    }

    func selectTrack(type: VideoTrackType, id: Int?) {
        engine.selectTrack(type: type, id: id)
    }

    func loadExternalSubtitle(_ url: URL) {
        if let existing = snapshot.tracks.first(where: {
            $0.type == .subtitle && $0.externalFilename.map {
                URL(fileURLWithPath: $0).standardizedFileURL == url.standardizedFileURL
            } == true
        }) {
            engine.selectTrack(type: .subtitle, id: existing.id)
            return
        }
        engine.loadExternalSubtitle(url: url)
    }

    @discardableResult
    func configureSubtitleRendering(_ mode: VideoSubtitleRenderingMode) -> Bool {
        engine.configureSubtitleRendering(mode)
    }

    func rememberSubtitleSelection(_ selection: VideoSubtitleSelection) {
        guard rememberPlaybackPosition, let currentMediaIdentity else { return }
        historyStore.save(subtitleSelection: selection, for: currentMediaIdentity)
    }

    func rememberExternalSubtitlePath(_ url: URL) {
        guard rememberPlaybackPosition, let currentMediaIdentity else { return }
        historyStore.saveExternalSubtitlePath(
            url.standardizedFileURL.path,
            for: currentMediaIdentity
        )
    }

    var rememberedExternalSubtitleURL: URL? {
        guard rememberPlaybackPosition, let currentMediaIdentity else { return nil }
        let path = historyStore.externalSubtitlePath(for: currentMediaIdentity)
        return path.map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    func rememberedExternalSubtitlePaths() -> Set<String> {
        Set(historyStore.allExternalSubtitlePaths().map { path in
            URL(fileURLWithPath: path).standardizedFileURL.path
        })
    }

    func consumePendingSubtitleSelection() -> VideoSubtitleSelection? {
        defer { pendingSubtitleSelection = nil }
        return pendingSubtitleSelection
    }

    func shutdown() {
        saveCurrentPosition(deferred: false)
        restoreSubtitleGapFastForwardSpeedIfNeeded()
        engine.shutdown()
        stopAccessingCurrentURL()
    }

    private func stopAccessingCurrentURL() {
        if isAccessingSecurityScopedURL {
            currentURL?.stopAccessingSecurityScopedResource()
        }
        isAccessingSecurityScopedURL = false
    }

    private func recoverRemotePlayback(from failure: RemotePlaybackFailure) {
        guard remoteRecoveryTask == nil,
              let session = remotePlaybackSession,
              let failedGeneration = remotePlaybackGeneration else {
            if remotePlaybackSession == nil {
                errorMessage = failure.localizedDescription
            }
            return
        }
        let resumeTime = pendingRestorePosition ?? snapshot.currentTime
        let shouldResumePlaying = pendingPlaybackIntent
            ?? lastLoadedPlaybackWasPlaying
            ?? snapshot.isPlaying
        engine.pause()
        remoteRecoveryTask = Task { [weak self] in
            let recovery = await session.recover(
                from: failure,
                generation: failedGeneration,
                resumeTime: resumeTime
            )
            guard !Task.isCancelled,
                  let self,
                  remotePlaybackSession === session else {
                return
            }
            remoteRecoveryTask = nil
            switch recovery {
            case .retry(let attempt):
                reloadRemotePlayback(
                    attempt,
                    playbackIntent: shouldResumePlaying
                )
            case .terminal(let terminalFailure):
                pendingPlaybackState = nil
                pendingRestorePosition = nil
                pendingPlaybackIntent = nil
                errorMessage = terminalFailure.localizedDescription
                engine.pause()
            case .ignored:
                break
            }
        }
    }

    private func reloadRemotePlayback(
        _ attempt: RemotePlaybackAttempt,
        playbackIntent: Bool
    ) {
        let playbackSource = VideoPlaybackSource.remoteStream(attempt.source)
        currentSource = playbackSource
        currentURL = playbackSource.displayURL
        currentTitle = playbackSource.title
        remotePlaybackGeneration = attempt.generation
        pendingPlaybackState = nil
        pendingRestorePosition = attempt.resumeTime > 0 ? attempt.resumeTime : nil
        pendingPlaybackIntent = playbackIntent
        lastLoadedPlaybackWasPlaying = playbackIntent
        do {
            try engine.load(source: playbackSource)
            publishLoadGeneration(preserveSubtitleOverlay: true)
            snapshot = engine.snapshot
            inspectorState = VideoInspectorState(snapshot: snapshot)
            errorMessage = nil
        } catch {
            recoverRemotePlayback(from: .remoteLoadFailed)
        }
    }

    private func configurePlaylistInBackground(around url: URL) {
        let requestedURL = url.standardizedFileURL
        playlistScanTask = Task { [weak self] in
            let urls = await Self.playlistURLs(around: url)
            guard !Task.isCancelled,
                  let self,
                  self.currentURL?.standardizedFileURL == requestedURL else {
                return
            }
            playlist = VideoPlaylist(urls: urls, currentURL: url)
        }
    }

    private func publishLoadGeneration(
        preserveSubtitleOverlay: Bool
    ) {
        let nextGeneration = loadGeneration &+ 1
        subtitlePreservingLoadGeneration = preserveSubtitleOverlay
            ? nextGeneration
            : nil
        loadGeneration = nextGeneration
    }

    private nonisolated static func playlistURLs(around url: URL) async -> [URL] {
        await Task.detached(priority: .utility) {
            let directory = url.deletingLastPathComponent()
            return (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? [url]
        }.value
    }

    private func handleSnapshot(_ snapshot: VideoPlaybackSnapshot) {
        self.snapshot = snapshot
        let nextInspectorState = VideoInspectorState(snapshot: snapshot)
        if nextInspectorState != inspectorState {
            inspectorState = nextInspectorState
        }
        requestedRotation = snapshot.rotation
        if snapshot.isLoaded, pendingPlaybackIntent == nil {
            lastLoadedPlaybackWasPlaying = snapshot.isPlaying
        }
        if pendingPlaybackState != nil
            || pendingRestorePosition != nil
            || pendingPlaybackIntent != nil {
            guard snapshot.isLoaded, snapshot.duration > 0 else { return }
            let playbackState = pendingPlaybackState
            let position = pendingRestorePosition
            let playbackIntent = pendingPlaybackIntent
            pendingPlaybackState = nil
            pendingRestorePosition = nil
            pendingPlaybackIntent = nil
            lastSavedSecond = 0
            if let playbackState {
                restoreResumeOptions(playbackState.resumeOptions, tracks: snapshot.tracks)
            }
            if let position {
                engine.seek(to: min(position, snapshot.duration))
            }
            if let playbackIntent {
                playbackIntent ? engine.play() : engine.pause()
            }
            return
        }
        let second = Int(snapshot.currentTime)
        if second != lastSavedSecond, second.isMultiple(of: 5) {
            lastSavedSecond = second
            saveCurrentPosition(deferred: true)
        }
    }

    private func restoreResumeOptions(
        _ options: VideoPlaybackResumeOptions,
        tracks: [VideoTrack]
    ) {
        if let speed = options.speed {
            engine.setSpeed(VideoPlaybackSpeed.normalized(speed))
        }
        if let subtitleDelay = options.subtitleDelay {
            engine.setSubtitleDelay(VideoSubtitleTiming.clampedDelay(subtitleDelay))
        }
        if let audioDelay = options.audioDelay {
            engine.setAudioDelay(
                min(
                    max(audioDelay, Self.audioDelayRange.lowerBound),
                    Self.audioDelayRange.upperBound
                )
            )
        }
        if let audioSelection = options.audioSelection {
            switch audioSelection {
            case .off:
                engine.selectTrack(type: .audio, id: nil)
            case .embedded:
                if let trackID = audioSelection.matchingTrackID(in: tracks) {
                    engine.selectTrack(type: .audio, id: trackID)
                }
            }
        }
    }

    private func saveCurrentPosition(deferred: Bool) {
        guard rememberPlaybackPosition, let currentMediaIdentity else { return }
        let resumeOptions = VideoPlaybackResumeOptions(snapshot: snapshotForPersistence)
        if deferred {
            historyStore.savePlaybackStateDeferred(
                position: snapshot.currentTime,
                duration: snapshot.duration,
                resumeOptions: resumeOptions,
                for: currentMediaIdentity
            )
            return
        }
        historyStore.save(
            position: snapshot.currentTime,
            duration: snapshot.duration,
            resumeOptions: resumeOptions,
            for: currentMediaIdentity
        )
    }

    private var currentUserSpeed: Double {
        subtitleGapFastForwardBaseSpeed ?? snapshot.speed
    }

    private static func normalizedSubtitleGapFastForwardSpeed(_ speed: Double) -> Double {
        guard speed.isFinite else {
            return VideoPlaybackSpeed.normalized(defaultSubtitleGapFastForwardSpeed)
        }
        return VideoPlaybackSpeed.normalized(min(max(speed, 1.1), 5.0))
    }

    private var snapshotForPersistence: VideoPlaybackSnapshot {
        guard let baseSpeed = subtitleGapFastForwardBaseSpeed else {
            return snapshot
        }
        var persistentSnapshot = snapshot
        persistentSnapshot.speed = baseSpeed
        return persistentSnapshot
    }

    private func shouldFastForwardSubtitleGap(
        slice: SubtitleCueSlice,
        playbackTime: TimeInterval
    ) -> Bool {
        guard slice.showing.isEmpty,
              let previousEnd = slice.lastShown.map(\.endTime).max(),
              let nextStart = slice.nextToShow.map(\.startTime).min() else {
            return false
        }
        return playbackTime - previousEnd > Self.subtitleGapFastForwardEdgeGuard
            && nextStart - playbackTime > Self.subtitleGapFastForwardEdgeGuard
    }

    private func restoreSubtitleGapFastForwardSpeedIfNeeded() {
        guard let baseSpeed = subtitleGapFastForwardBaseSpeed else { return }
        subtitleGapFastForwardBaseSpeed = nil
        let normalizedBaseSpeed = VideoPlaybackSpeed.normalized(baseSpeed)
        if abs(snapshot.speed - normalizedBaseSpeed) >= 0.001 {
            engine.setSpeed(normalizedBaseSpeed)
        }
    }
}
