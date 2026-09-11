import Foundation

nonisolated enum VideoShaderPreset {
    case off
}

@MainActor
private final class FakePlaybackEngine: PlaybackEngine {
    var snapshot = VideoPlaybackSnapshot()
    var onSnapshotChanged: ((VideoPlaybackSnapshot) -> Void)?
    var loadedURL: URL?
    var seekTarget: TimeInterval?
    var speedTarget: Double?
    var volumeTarget: Double?
    var mutedTarget: Bool?
    var subtitleDelayTarget: TimeInterval?
    var audioDelayTarget: TimeInterval?
    var externalSubtitleURL: URL?
    var selectedTrack: (VideoTrackType, Int?)?
    var shutdownCount = 0
    var onPlaybackEnded: (() -> Void)?
    var onRemotePlaybackFailure: ((RemotePlaybackFailure) -> Void)?
    var loadedSources: [VideoPlaybackSource] = []
    var completesLoadImmediately = true
    var publishesSeekImmediately = true

    func load(source: VideoPlaybackSource) throws {
        loadedSources.append(source)
        loadedURL = source.displayURL
        guard completesLoadImmediately else {
            snapshot = VideoPlaybackSnapshot()
            onSnapshotChanged?(snapshot)
            return
        }
        snapshot = VideoPlaybackSnapshot(duration: 120, isLoaded: true)
        onSnapshotChanged?(snapshot)
    }

    func finishLoading(duration: TimeInterval = 120, tracks: [VideoTrack] = []) {
        snapshot = VideoPlaybackSnapshot(duration: duration, isLoaded: true)
        snapshot.tracks = tracks
        onSnapshotChanged?(snapshot)
    }

    func publishDuration(_ duration: TimeInterval) {
        snapshot.duration = duration
        onSnapshotChanged?(snapshot)
    }

    func publishTime(_ time: TimeInterval) {
        snapshot.currentTime = time
        onSnapshotChanged?(snapshot)
    }

    func play() {
        snapshot.isPlaying = true
        onSnapshotChanged?(snapshot)
    }

    func pause() {
        snapshot.isPlaying = false
        onSnapshotChanged?(snapshot)
    }

    func seek(to time: TimeInterval) {
        seekTarget = time
        guard publishesSeekImmediately else { return }
        snapshot.currentTime = time
        onSnapshotChanged?(snapshot)
    }

    func setSpeed(_ speed: Double) {
        speedTarget = speed
    }

    func setVolume(_ volume: Double) {
        volumeTarget = volume
    }

    func setMuted(_ muted: Bool) {
        mutedTarget = muted
    }

    func setSubtitleDelay(_ delay: TimeInterval) {
        subtitleDelayTarget = delay
    }

    func setAudioDelay(_ delay: TimeInterval) {
        audioDelayTarget = delay
    }

    func loadExternalSubtitle(url: URL) {
        externalSubtitleURL = url
    }

    func selectTrack(type: VideoTrackType, id: Int?) {
        selectedTrack = (type, id)
    }

    func shutdown() {
        shutdownCount += 1
    }
}

private actor RemoteFixtureStore {
    private var sources: [ResolvedRemoteVideoSource]

    init(sources: [ResolvedRemoteVideoSource]) {
        self.sources = sources
    }

    func next() throws -> ResolvedRemoteVideoSource {
        guard !sources.isEmpty else {
            throw RemoteVideoResolverError.noPlayableStream
        }
        return sources.removeFirst()
    }
}

private struct RemoteFixtureResolver: RemoteVideoResolving {
    let provider: RemoteVideoProvider = .youtube
    let store: RemoteFixtureStore

    func canResolve(url: URL) -> Bool { true }

    func resolve(
        url: URL,
        preferredSubtitleLanguages: [String]
    ) async throws -> ResolvedRemoteVideoSource {
        try await store.next()
    }
}

private func remoteSource(
    suffix: String,
    includesFallback: Bool = true
) -> ResolvedRemoteVideoSource {
    let headers = ["User-Agent": "HoshiTests"]
    return ResolvedRemoteVideoSource(
        identity: RemoteVideoIdentity(
            providerID: "youtube",
            remoteID: "playback-model",
            originalURL: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!,
            canonicalURL: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!,
            title: "Remote Fixture",
            thumbnailURL: nil
        ),
        playbackStream: RemoteVideoStream(
            url: URL(string: "https://cdn.example/video-\(suffix).mp4")!,
            formatID: "video-\(suffix)",
            height: 1080,
            hasVideo: true,
            hasAudio: false,
            httpHeaders: headers
        ),
        audioStream: RemoteVideoStream(
            url: URL(string: "https://cdn.example/audio-\(suffix).m4a")!,
            formatID: "audio-\(suffix)",
            hasVideo: false,
            hasAudio: true,
            httpHeaders: headers
        ),
        muxedFallbackStream: includesFallback ? RemoteVideoStream(
            url: URL(string: "https://cdn.example/muxed-\(suffix).mp4")!,
            formatID: "muxed-\(suffix)",
            height: 720,
            hasVideo: true,
            hasAudio: true,
            httpHeaders: headers
        ) : nil,
        miningStream: nil,
        subtitleOptions: [],
        selectedSubtitleLanguage: nil,
        resolvedAt: Date(),
        expiresAt: Date().addingTimeInterval(600)
    )
}

private func remoteQualitySource(
    suffix: String,
    selectedHeight: Int
) -> ResolvedRemoteVideoSource {
    let base = remoteSource(suffix: suffix)
    let audio = base.audioStream!
    let qualityOptions = [
        RemoteVideoQualityOption(
            id: "1080-\(suffix)",
            height: 1080,
            playbackStream: RemoteVideoStream(
                url: URL(string: "https://cdn.example/video-1080-\(suffix).mp4")!,
                formatID: "video-1080-\(suffix)",
                height: 1080,
                hasVideo: true,
                hasAudio: false,
                httpHeaders: base.httpHeaders
            ),
            audioStream: audio
        ),
        RemoteVideoQualityOption(
            id: "720-\(suffix)",
            height: 720,
            playbackStream: RemoteVideoStream(
                url: URL(string: "https://cdn.example/video-720-\(suffix).mp4")!,
                formatID: "video-720-\(suffix)",
                height: 720,
                hasVideo: true,
                hasAudio: false,
                httpHeaders: base.httpHeaders
            ),
            audioStream: audio
        ),
    ]
    let resolved = ResolvedRemoteVideoSource(
        identity: base.identity,
        playbackStream: qualityOptions[0].playbackStream,
        audioStream: qualityOptions[0].audioStream,
        muxedFallbackStream: base.muxedFallbackStream,
        miningStream: base.miningStream,
        subtitleOptions: base.subtitleOptions,
        selectedSubtitleLanguage: base.selectedSubtitleLanguage,
        resolvedAt: base.resolvedAt,
        expiresAt: base.expiresAt,
        qualityOptions: qualityOptions
    )
    return resolved.selectingQuality(height: selectedHeight)!
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func expectNearlyEqual(_ actual: Double?, _ expected: Double, _ message: String) {
    guard let actual, abs(actual - expected) < 0.0001 else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@MainActor
private func waitForPlaylistNextURL(
    _ model: VideoPlayerViewModel,
    timeout: TimeInterval = 2
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while model.playlist.nextURL == nil, Date() < deadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

@MainActor
private func waitForLoadedSourceCount(
    _ engine: FakePlaybackEngine,
    _ count: Int,
    timeout: TimeInterval = 2
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while engine.loadedSources.count < count, Date() < deadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

@main
private enum VideoPlaybackModelTests {
    @MainActor
    static func main() async throws {
        let engine = FakePlaybackEngine()
        let suiteName = "moe.shishamo.hoshi.tests.video-model-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let historyStore = VideoPlaybackHistoryStore(defaults: defaults)
        let model = VideoPlayerViewModel(
            engine: engine,
            historyStore: historyStore,
            autoPlayNext: false,
            rememberPlaybackPosition: false
        )

        let remoteInitial = remoteSource(suffix: "initial")
        let remoteRefreshed = remoteSource(suffix: "refreshed")
        let remoteEngine = FakePlaybackEngine()
        let remoteRegistry = RemoteVideoResolverRegistry(
            resolvers: [RemoteFixtureResolver(
                store: RemoteFixtureStore(sources: [remoteRefreshed])
            )],
            cache: RemoteVideoResolutionCache()
        )
        let remoteModel = VideoPlayerViewModel(
            engine: remoteEngine,
            historyStore: historyStore,
            remoteResolverRegistry: remoteRegistry,
            autoPlayNext: false,
            rememberPlaybackPosition: true
        )
        remoteModel.open(.remoteStream(remoteInitial))
        expect(
            remoteModel.currentURL == remoteInitial.identity.canonicalURL,
            "remote playback should retain its HTTPS page URL instead of creating a fake file URL"
        )
        expect(
            remoteModel.currentMediaIdentity == remoteInitial.identity.mediaIdentity,
            "remote playback should retain its durable media identity"
        )
        expect(remoteModel.currentTitle == "Remote Fixture", "remote playback should retain its title")
        remoteEngine.play()
        remoteEngine.publishTime(33)
        remoteEngine.onRemotePlaybackFailure?(.externalAudioUnavailable)
        await waitForLoadedSourceCount(remoteEngine, 2)
        guard case .remoteStream(let refreshedPlayback) = remoteEngine.loadedSources.last else {
            expect(false, "remote audio failure should reload a refreshed source")
            return
        }
        expect(
            refreshedPlayback.playbackStream.formatID == "video-refreshed",
            "first remote audio failure should force fresh stream URLs"
        )
        expect(
            remoteEngine.seekTarget == 33,
            "remote recovery should restore the captured playback position"
        )
        expect(
            remoteEngine.snapshot.isPlaying,
            "remote recovery should restore a playing source to playback"
        )
        remoteEngine.pause()
        remoteEngine.publishTime(34)
        remoteEngine.onRemotePlaybackFailure?(.externalAudioUnavailable)
        await waitForLoadedSourceCount(remoteEngine, 3)
        guard case .remoteStream(let fallbackPlayback) = remoteEngine.loadedSources.last else {
            expect(false, "a second remote audio failure should load the muxed fallback")
            return
        }
        expect(fallbackPlayback.audioStream == nil, "muxed recovery should remove external audio")
        expect(
            fallbackPlayback.playbackStream.formatID == "muxed-refreshed",
            "muxed recovery should use the refreshed fallback stream"
        )
        expect(
            !remoteEngine.snapshot.isPlaying,
            "remote recovery should leave a paused source paused"
        )
        remoteEngine.onRemotePlaybackFailure?(.audioUnavailable)
        for _ in 0..<100 where remoteModel.errorMessage == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        expect(
            remoteModel.errorMessage == RemotePlaybackFailure.audioUnavailable.localizedDescription,
            "failure after the muxed fallback should surface one terminal audio error"
        )

        let qualityEngine = FakePlaybackEngine()
        let qualityModel = VideoPlayerViewModel(
            engine: qualityEngine,
            historyStore: historyStore,
            autoPlayNext: false,
            rememberPlaybackPosition: false
        )
        let quality1080 = remoteQualitySource(suffix: "quality", selectedHeight: 1080)
        let quality720 = remoteQualitySource(suffix: "quality", selectedHeight: 720)
        qualityModel.open(.remoteStream(quality1080))
        qualityEngine.play()
        qualityEngine.publishTime(47)
        qualityEngine.completesLoadImmediately = false
        qualityEngine.seekTarget = nil
        expect(
            qualityModel.switchRemoteQuality(to: quality720),
            "a quality from the current remote identity should be accepted"
        )
        expect(
            qualityModel.subtitlePreservingLoadGeneration == qualityModel.loadGeneration,
            "a same-media quality replacement should mark its load as subtitle preserving"
        )
        qualityEngine.finishLoading(duration: 0)
        expect(
            qualityEngine.seekTarget == nil,
            "a slow quality switch should not seek while duration is still unavailable"
        )
        qualityEngine.finishLoading(duration: 120)
        expect(
            qualityEngine.seekTarget == 47,
            "a slow quality switch should restore time only after the replacement stream loads"
        )
        expect(
            qualityEngine.snapshot.isPlaying,
            "a quality switch should restore a playing source to playback"
        )

        qualityEngine.pause()
        qualityEngine.publishTime(58)
        qualityEngine.seekTarget = nil
        expect(
            qualityModel.switchRemoteQuality(to: quality1080),
            "switching back to another quality should be accepted"
        )
        qualityEngine.finishLoading(duration: 120)
        expect(
            qualityEngine.seekTarget == 58,
            "switching quality while paused should still restore the current time"
        )
        expect(
            !qualityEngine.snapshot.isPlaying,
            "switching quality while paused should remain paused"
        )

        let qualityRecoveryEngine = FakePlaybackEngine()
        let qualityRecoveryRegistry = RemoteVideoResolverRegistry(
            resolvers: [RemoteFixtureResolver(
                store: RemoteFixtureStore(sources: [
                    remoteQualitySource(
                        suffix: "quality-refreshed",
                        selectedHeight: 720
                    ),
                ])
            )],
            cache: RemoteVideoResolutionCache()
        )
        let qualityRecoveryModel = VideoPlayerViewModel(
            engine: qualityRecoveryEngine,
            historyStore: historyStore,
            remoteResolverRegistry: qualityRecoveryRegistry,
            autoPlayNext: false,
            rememberPlaybackPosition: false
        )
        qualityRecoveryModel.open(.remoteStream(quality1080))
        qualityRecoveryEngine.play()
        qualityRecoveryEngine.publishTime(61)
        qualityRecoveryEngine.completesLoadImmediately = false
        expect(
            qualityRecoveryModel.switchRemoteQuality(to: quality720),
            "the quality recovery fixture should start switching"
        )
        qualityRecoveryEngine.onRemotePlaybackFailure?(.remoteLoadFailed)
        await waitForLoadedSourceCount(qualityRecoveryEngine, 3)
        expect(
            qualityRecoveryModel.subtitlePreservingLoadGeneration
                == qualityRecoveryModel.loadGeneration,
            "automatic signed-URL recovery should mark its replacement load as subtitle preserving"
        )
        qualityRecoveryEngine.finishLoading(duration: 120)
        expect(
            qualityRecoveryEngine.seekTarget == 61,
            "quality refresh after a failed replacement stream should retain the pre-switch time"
        )
        expect(
            qualityRecoveryEngine.snapshot.isPlaying,
            "quality refresh after a failed replacement stream should retain playback state"
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-video-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("Episode 1.mkv")
        let nextURL = directory.appendingPathComponent("Episode 2.mkv")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        FileManager.default.createFile(atPath: nextURL.path, contents: Data())

        historyStore.save(position: 42, duration: 120, for: url)
        let rememberedSubtitle = VideoSubtitleSelection.external(
            path: directory.appendingPathComponent("Episode 1.ja.srt").path
        )
        historyStore.save(subtitleSelection: rememberedSubtitle, for: url)

        model.open(url)
        expect(engine.loadedURL == url, "opening a video should load it in the engine")
        expect(model.snapshot.duration == 120, "engine snapshots should update the model")
        expect(engine.seekTarget == nil, "disabled history should not restore a saved position")
        expect(
            model.pendingSubtitleSelection == nil,
            "disabled history should not restore a saved subtitle selection"
        )

        engine.onPlaybackEnded?()
        expect(
            engine.loadedURL == url,
            "disabled auto-play should not advance after playback ends"
        )
        await waitForPlaylistNextURL(model)
        model.autoPlayNext = true
        engine.onPlaybackEnded?()
        expect(
            engine.loadedURL?.lastPathComponent == nextURL.lastPathComponent,
            "enabled auto-play should advance after playback ends"
        )

        model.togglePlayback()
        expect(engine.snapshot.isPlaying, "toggle should start paused playback")
        model.togglePlayback()
        expect(!engine.snapshot.isPlaying, "toggle should pause active playback")

        model.seek(to: 500)
        expect(engine.seekTarget == 120, "seek should clamp to duration")
        model.seek(to: -5)
        expect(engine.seekTarget == 0, "seek should clamp to zero")

        model.setSpeed(9)
        expect(engine.speedTarget == 5, "speed should clamp to 5x")
        model.setSpeed(4.56)
        expectNearlyEqual(
            engine.speedTarget,
            4.6,
            "custom speed should round to one decimal place"
        )
        model.adjustSpeed(by: -10)
        expect(engine.speedTarget == 0.25, "speed adjustment should clamp to 0.25x")

        model.setVolume(120)
        expect(engine.volumeTarget == 100, "volume should clamp to 100")
        model.toggleMuted()
        expect(engine.mutedTarget == true, "mute toggle should invert snapshot state")

        model.setSubtitleDelay(99)
        expect(engine.subtitleDelayTarget == 60, "subtitle delay should clamp to 60 seconds")
        model.adjustSubtitleDelay(by: -130)
        expect(engine.subtitleDelayTarget == -60, "subtitle delay adjustment should clamp")

        let subtitleURL = directory.appendingPathComponent("Episode 1.srt")
        FileManager.default.createFile(atPath: subtitleURL.path, contents: Data())
        model.loadExternalSubtitle(subtitleURL)
        expect(
            engine.externalSubtitleURL == subtitleURL,
            "external subtitle imports should be loaded into mpv instead of only parsed by Hoshi"
        )

        model.selectTrack(type: .audio, id: 3)
        expect(
            engine.selectedTrack?.0 == .audio && engine.selectedTrack?.1 == 3,
            "track selection should reach the engine"
        )

        engine.snapshot.tracks = [VideoTrack(
            id: 7, type: .subtitle, title: "External", language: nil,
            codec: "subrip", ffIndex: nil, externalFilename: subtitleURL.path,
            isImage: false, isSelected: false
        )]
        engine.onSnapshotChanged?(engine.snapshot)
        engine.externalSubtitleURL = nil
        model.loadExternalSubtitle(subtitleURL)
        expect(engine.externalSubtitleURL == nil,
               "reenabling an imported subtitle must not add a duplicate track")
        expect(engine.selectedTrack?.0 == .subtitle && engine.selectedTrack?.1 == 7,
               "reenabling an imported subtitle should select its existing track")

        expect(VideoTimeFormatter.string(from: 65) == "1:05", "short times should use m:ss")
        expect(VideoTimeFormatter.string(from: 3661) == "1:01:01", "long times should use h:mm:ss")

        model.shutdown()
        expect(engine.shutdownCount == 1, "shutdown should release the engine")
        expect(
            historyStore.position(for: nextURL) == nil,
            "disabled history should not persist playback position"
        )
        model.rememberSubtitleSelection(.off)
        expect(
            historyStore.subtitleSelection(for: nextURL) == nil,
            "disabled history should not persist subtitle selection"
        )

        let restoreEngine = FakePlaybackEngine()
        let restoreModel = VideoPlayerViewModel(
            engine: restoreEngine,
            historyStore: historyStore,
            autoPlayNext: false,
            rememberPlaybackPosition: true
        )
        restoreModel.open(url)
        expect(
            restoreEngine.seekTarget == 42,
            "enabled history should restore the saved playback position"
        )
        expect(
            restoreModel.pendingSubtitleSelection == rememberedSubtitle,
            "enabled history should expose the saved subtitle selection"
        )
        await waitForPlaylistNextURL(restoreModel)
        historyStore.save(position: 37, duration: 120, for: nextURL)
        historyStore.save(subtitleSelection: .off, for: nextURL)
        restoreEngine.seekTarget = nil
        restoreModel.selectPlaylistItem(nextURL)
        expect(
            restoreEngine.seekTarget == 37,
            "selecting an episode from the playlist should restore its saved position"
        )
        expect(
            restoreModel.pendingSubtitleSelection == .off,
            "selecting an episode from the playlist should expose its saved subtitle selection"
        )
        _ = restoreModel.consumePendingSubtitleSelection()
        restoreEngine.seekTarget = nil
        restoreModel.selectPlaylistItem(url)
        expect(
            restoreEngine.seekTarget == 42,
            "switching back through the playlist should restore the first episode position"
        )
        expect(
            restoreModel.pendingSubtitleSelection == rememberedSubtitle,
            "switching back through the playlist should restore the first episode subtitle"
        )
        let generationBeforeReopen = restoreModel.loadGeneration
        restoreModel.open(url)
        expect(
            restoreModel.loadGeneration == generationBeforeReopen + 1,
            "reopening the same video should publish a new load generation"
        )
        expect(
            restoreModel.consumePendingSubtitleSelection() == rememberedSubtitle
                && restoreModel.pendingSubtitleSelection == nil,
            "subtitle restoration should consume the pending selection once"
        )
        restoreModel.rememberSubtitleSelection(.off)
        expect(
            historyStore.subtitleSelection(for: url) == .off,
            "enabled history should persist subtitle selection changes"
        )
        restoreEngine.publishTime(73)
        restoreEngine.seekTarget = nil
        restoreModel.open(url, startsFromBeginning: true)
        expect(
            restoreEngine.seekTarget == 0,
            "reopening the current video from the beginning should seek to zero"
        )
        expect(
            historyStore.position(for: url) == nil,
            "from-beginning reopen should clear progress after saving the current media"
        )
        expect(
            restoreModel.consumePendingSubtitleSelection() == .off,
            "from-beginning reopen should preserve the remembered subtitle selection"
        )

        historyStore.save(position: 42, duration: 120, for: url)
        let stagedLoadEngine = FakePlaybackEngine()
        stagedLoadEngine.completesLoadImmediately = false
        stagedLoadEngine.publishesSeekImmediately = false
        let stagedLoadModel = VideoPlayerViewModel(
            engine: stagedLoadEngine,
            historyStore: historyStore,
            autoPlayNext: false,
            rememberPlaybackPosition: true
        )
        stagedLoadModel.open(url)
        stagedLoadEngine.finishLoading(duration: 0)
        expect(
            stagedLoadEngine.seekTarget == nil,
            "FILE_LOADED should wait for a valid duration before restoring playback position"
        )
        expect(
            historyStore.position(for: url) == 42,
            "the zero-time loading snapshot must not delete the remembered position"
        )
        stagedLoadEngine.publishDuration(120)
        expect(
            stagedLoadEngine.seekTarget == 42,
            "duration becoming available should restore the remembered position"
        )
        expect(
            historyStore.position(for: url) == 42,
            "an asynchronous restore seek must not erase the remembered position at time zero"
        )

        let delayedEngine = FakePlaybackEngine()
        delayedEngine.completesLoadImmediately = false
        let delayedModel = VideoPlayerViewModel(
            engine: delayedEngine,
            historyStore: historyStore,
            autoPlayNext: false,
            rememberPlaybackPosition: true
        )
        historyStore.save(position: 42, duration: 120, for: url)
        delayedModel.open(url)
        delayedModel.rememberPlaybackPosition = false
        delayedEngine.finishLoading()
        expect(
            delayedEngine.seekTarget == nil,
            "disabling playback-state history before load finishes should cancel the pending seek"
        )

        let optionsURL = directory.appendingPathComponent("Episode Options.mkv")
        FileManager.default.createFile(atPath: optionsURL.path, contents: Data())
        let savedAudioTrack = VideoTrack(
            id: 2,
            type: .audio,
            title: "Japanese Audio",
            language: "jpn",
            codec: "aac",
            ffIndex: 8,
            externalFilename: nil,
            isImage: false,
            isSelected: true
        )
        let currentAudioTrack = VideoTrack(
            id: 9,
            type: .audio,
            title: "Japanese Audio",
            language: "jpn",
            codec: "aac",
            ffIndex: 8,
            externalFilename: nil,
            isImage: false,
            isSelected: false
        )
        historyStore.savePlaybackState(
            position: 64,
            duration: 120,
            resumeOptions: VideoPlaybackResumeOptions(
                speed: 1.6,
                subtitleDelay: 0.45,
                audioDelay: -0.35,
                audioSelection: .embedded(VideoAudioTrackIdentity(track: savedAudioTrack))
            ),
            for: optionsURL
        )
        let optionsEngine = FakePlaybackEngine()
        optionsEngine.completesLoadImmediately = false
        let optionsModel = VideoPlayerViewModel(
            engine: optionsEngine,
            historyStore: historyStore,
            autoPlayNext: false,
            rememberPlaybackPosition: true
        )
        optionsModel.open(optionsURL)
        optionsEngine.finishLoading(duration: 0, tracks: [currentAudioTrack])
        expect(
            optionsEngine.speedTarget == nil && optionsEngine.audioDelayTarget == nil,
            "per-video options should wait for a valid loaded duration"
        )
        optionsEngine.finishLoading(duration: 120, tracks: [currentAudioTrack])
        expect(
            optionsEngine.seekTarget == 64,
            "per-video option restore should keep restoring the saved playback position"
        )
        expect(
            optionsEngine.speedTarget == 1.6,
            "per-video option restore should apply the saved playback speed"
        )
        expect(
            optionsEngine.subtitleDelayTarget == 0.45,
            "per-video option restore should apply the saved subtitle delay"
        )
        expect(
            optionsEngine.audioDelayTarget == -0.35,
            "per-video option restore should apply the saved audio delay"
        )
        expect(
            optionsEngine.selectedTrack?.0 == .audio && optionsEngine.selectedTrack?.1 == 9,
            "per-video option restore should match saved audio tracks by stable identity"
        )
        print("Video playback model tests passed")
    }
}
