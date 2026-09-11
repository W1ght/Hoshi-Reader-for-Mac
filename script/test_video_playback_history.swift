import Foundation

// PlaybackEngine references the Video-only shader preset, but this focused
// persistence harness intentionally does not compile the Anime4K UI/store.
nonisolated enum VideoShaderPreset {
    case off
}

private func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("FAIL: \(message): expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

@main
private enum VideoPlaybackHistoryTests {
    static func main() {
        let suiteName = "moe.shishamo.hoshi.tests.video-history-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let historyFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-video-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: historyFileURL) }
        let url = URL(fileURLWithPath: "/tmp/Show 01.mkv")
        let legacyURL = URL(fileURLWithPath: "/tmp/Legacy.mkv")
        defaults.set(
            [legacyURL.standardizedFileURL.path: 37],
            forKey: "videoPlaybackPositions"
        )
        let store = VideoPlaybackHistoryStore(
            defaults: defaults,
            fileURL: historyFileURL
        )

        store.save(position: 42.5, duration: 100, for: url)
        expect(store.position(for: url), 42.5, "saved position should be restored")

        store.save(position: 98, duration: 100, for: url)
        expect(store.position(for: url), nil, "near-end position should be cleared")
        expect(store.playbackState(for: url)?.isFinished, true, "near-end state should be retained as watched")

        store.save(position: 1, duration: 0, for: url)
        expect(store.position(for: url), nil, "unknown duration should not be persisted")

        let stateURL = URL(fileURLWithPath: "/tmp/Hoshi Movie.mkv")
        let completedURL = URL(fileURLWithPath: "/tmp/Completed.mkv")
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        store.savePlaybackState(position: 45, duration: 100, updatedAt: date, for: stateURL)
        let state = store.playbackState(for: stateURL)
        expect(state?.position, 45, "new playback state should preserve position")
        expect(state?.duration, 100, "new playback state should preserve duration")
        expect(state?.updatedAt, date, "new playback state should preserve updatedAt")
        expect(
            state?.resumeOptions,
            .empty,
            "playback states without custom options should expose empty resume options"
        )
        expect(
            store.position(for: stateURL),
            45,
            "legacy position API should read the new state"
        )

        let audioTrack = VideoTrack(
            id: 2,
            type: .audio,
            title: "Japanese Audio",
            language: "jpn",
            codec: "aac",
            ffIndex: 1,
            externalFilename: nil,
            isImage: false,
            isSelected: true
        )
        let resumeOptions = VideoPlaybackResumeOptions(
            speed: 1.5,
            subtitleDelay: 0.35,
            audioDelay: -0.25,
            audioSelection: .embedded(VideoAudioTrackIdentity(track: audioTrack))
        )
        store.savePlaybackState(
            position: 55,
            duration: 100,
            updatedAt: date,
            resumeOptions: resumeOptions,
            for: stateURL
        )
        expect(
            store.playbackState(for: stateURL)?.resumeOptions,
            resumeOptions,
            "playback state should round-trip per-video resume options"
        )
        expect(
            VideoPlaybackResumeOptions(subtitleDelay: 45).subtitleDelay,
            45,
            "subtitle timing beyond the slider range should remain restorable"
        )
        expect(
            VideoPlaybackResumeOptions(subtitleDelay: 90).subtitleDelay,
            60,
            "subtitle timing persistence should clamp to the 60-second limit"
        )
        expect(
            VideoPlaybackResumeOptions(subtitleDelay: -90).subtitleDelay,
            -60,
            "negative subtitle timing persistence should clamp to the 60-second limit"
        )
        expect(
            try! JSONDecoder().decode(
                VideoPlaybackState.self,
                from: Data(
                    """
                    {"position":12,"duration":100,"updatedAt":\(date.timeIntervalSinceReferenceDate),"isFinished":false}
                    """.utf8
                )
            ).resumeOptions,
            .empty,
            "legacy encoded playback states should decode with empty resume options"
        )

        store.savePlaybackState(position: 99, duration: 100, updatedAt: date, for: completedURL)
        expect(
            store.position(for: completedURL),
            nil,
            "finished playback state should not restore from the end"
        )
        expect(
            store.playbackState(for: completedURL)?.isFinished,
            true,
            "near-complete playback state should be retained as watched"
        )

        store.clearProgress(for: completedURL)
        expect(store.playbackState(for: completedURL), nil, "clearing progress should remove playback state")

        let manuallyWatchedURL = URL(fileURLWithPath: "/tmp/Watched.mkv")
        store.markWatched(duration: 100, updatedAt: date, for: manuallyWatchedURL)
        let watchedState = store.playbackState(for: manuallyWatchedURL)
        expect(watchedState?.isFinished, true, "mark watched should save a finished state")
        expect(watchedState?.progress, 1, "mark watched should report complete progress")
        expect(store.position(for: manuallyWatchedURL), nil, "mark watched should not create a restore position")

        let legacyState = store.playbackState(for: legacyURL)
        expect(
            legacyState?.position,
            37,
            "new playback state API should read legacy position values"
        )
        expect(
            legacyState?.duration,
            nil,
            "legacy position values should not invent a duration"
        )
        let stateSnapshot = store.playbackStates(for: [stateURL, legacyURL, url])
        expect(
            stateSnapshot[stateURL.standardizedFileURL.path],
            store.playbackState(for: stateURL),
            "batch playback state API should match single state lookup"
        )
        expect(
            stateSnapshot[legacyURL.standardizedFileURL.path],
            legacyState,
            "batch playback state API should preserve legacy position compatibility"
        )

        let originalTrack = VideoTrack(
            id: 4,
            type: .subtitle,
            title: "Japanese",
            language: "jpn",
            codec: "ass",
            ffIndex: 7,
            externalFilename: nil,
            isImage: false,
            isSelected: true
        )
        let embedded = VideoSubtitleSelection.embedded(
            VideoSubtitleTrackIdentity(track: originalTrack)
        )
        store.save(subtitleSelection: embedded, for: url)
        expect(
            store.subtitleSelection(for: url),
            embedded,
            "embedded subtitle selection should round-trip"
        )

        let renumberedTrack = VideoTrack(
            id: 9,
            type: .subtitle,
            title: "Japanese",
            language: "jpn",
            codec: "ass",
            ffIndex: 7,
            externalFilename: nil,
            isImage: false,
            isSelected: false
        )
        expect(
            embedded.matchingTrackID(in: [renumberedTrack]),
            9,
            "embedded subtitle selection should survive mpv track ID changes"
        )
        let reusedTransientID = VideoTrack(
            id: originalTrack.id,
            type: .subtitle,
            title: "English",
            language: "eng",
            codec: "ass",
            ffIndex: 8,
            externalFilename: nil,
            isImage: false,
            isSelected: false
        )
        expect(
            embedded.matchingTrackID(in: [reusedTransientID]),
            nil,
            "a stable FFmpeg identity must not fall back to a reused transient mpv track ID"
        )

        let subtitleURL = URL(fileURLWithPath: "/tmp/Show 01.ja.srt")
        let external = VideoSubtitleSelection.external(
            path: subtitleURL.standardizedFileURL.path
        )
        store.save(subtitleSelection: external, for: url)
        expect(
            store.subtitleSelection(for: url),
            external,
            "external subtitle selection should round-trip"
        )

        store.save(subtitleSelection: .off, for: url)
        expect(
            store.subtitleSelection(for: url),
            .off,
            "disabled subtitles should be remembered explicitly"
        )
        expect(
            store.externalSubtitlePath(for: .localFile(path: url.standardizedFileURL.path)),
            subtitleURL.standardizedFileURL.path,
            "disabling subtitles should keep the external file available"
        )
        store.save(
            subtitleSelection: .externalDisabled(path: subtitleURL.path),
            for: url
        )
        expect(
            store.subtitleSelection(for: url),
            .externalDisabled(path: subtitleURL.standardizedFileURL.path),
            "a disabled external subtitle should retain its archived selection"
        )
        let reloadedStore = VideoPlaybackHistoryStore(
            defaults: defaults,
            fileURL: historyFileURL
        )
        expect(
            reloadedStore.playbackState(for: stateURL),
            store.playbackState(for: stateURL),
            "playback states should round-trip through the dedicated history file"
        )
        expect(
            reloadedStore.subtitleSelection(for: url),
            .externalDisabled(path: subtitleURL.standardizedFileURL.path),
            "subtitle selections should round-trip through the dedicated history file"
        )
        expect(
            reloadedStore.externalSubtitlePath(for: .localFile(path: url.standardizedFileURL.path)),
            subtitleURL.standardizedFileURL.path,
            "external subtitle availability should round-trip through the dedicated history file"
        )
        expect(
            defaults.object(forKey: "videoPlaybackStates") == nil,
            true,
            "new playback state writes should not touch the shared UserDefaults domain"
        )

        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: .off,
                tracks: [],
                isLoaded: false
            ),
            .off,
            "off selection should restore without waiting for tracks"
        )

        let existingSubtitleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoshi-video-subtitle-\(UUID().uuidString).srt")
        FileManager.default.createFile(
            atPath: existingSubtitleURL.path,
            contents: Data()
        )
        defer { try? FileManager.default.removeItem(at: existingSubtitleURL) }
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: .external(path: existingSubtitleURL.path),
                tracks: [],
                isLoaded: false
            ),
            .external(existingSubtitleURL.standardizedFileURL),
            "existing external subtitle should restore before tracks load"
        )
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: .externalDisabled(path: existingSubtitleURL.path),
                tracks: [],
                isLoaded: false
            ),
            .externalDisabled(existingSubtitleURL.standardizedFileURL),
            "a disabled external subtitle should remain available without activating a track"
        )
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: .external(path: existingSubtitleURL.path + ".missing"),
                tracks: [],
                isLoaded: false
            ),
            .unavailable,
            "missing external subtitle should fall back safely"
        )
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: embedded,
                tracks: [],
                isLoaded: false
            ),
            .waitingForTracks,
            "embedded subtitle should wait for mpv track metadata"
        )
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: embedded,
                tracks: [renumberedTrack],
                isLoaded: false
            ),
            .waitingForTracks,
            "embedded subtitle must ignore stale track callbacks until the selected episode is loaded"
        )
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: embedded,
                tracks: [renumberedTrack],
                isLoaded: true
            ),
            .embeddedTrack(9),
            "embedded subtitle should resolve to the current mpv track ID"
        )
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: embedded,
                tracks: [VideoTrack(
                    id: 1,
                    type: .video,
                    title: "Video",
                    language: nil,
                    codec: "h264",
                    ffIndex: 0,
                    externalFilename: nil,
                    isImage: false,
                    isSelected: true
                )],
                isLoaded: true
            ),
            .unavailable,
            "missing embedded subtitle should fall back after tracks finish loading"
        )

        let remoteIdentity = VideoMediaIdentity.remote(
            providerID: "youtube",
            remoteID: "abc123"
        )
        expect(
            remoteIdentity.persistenceKey,
            "remote://youtube/abc123",
            "remote playback identity should have a stable persistence key"
        )
        expect(
            remoteIdentity.localURL,
            nil,
            "remote playback identity must not expose a synthetic local file URL"
        )
        store.savePlaybackState(
            position: 25,
            duration: 100,
            updatedAt: date,
            for: remoteIdentity
        )
        expect(
            store.playbackState(for: remoteIdentity)?.position,
            25,
            "remote playback state should round-trip through its durable identity"
        )
        let remoteSubtitle = VideoSubtitleSelection.remote(language: "zh-Hans")
        let legacyRemoteSubtitle = try! JSONDecoder().decode(
            VideoSubtitleSelection.self,
            from: Data(#"{"remote":{"language":"zh-Hans"}}"#.utf8)
        )
        expect(
            legacyRemoteSubtitle,
            remoteSubtitle,
            "legacy language-only remote subtitle JSON should remain decodable"
        )
        store.save(subtitleSelection: remoteSubtitle, for: remoteIdentity)
        expect(
            store.subtitleSelection(for: remoteIdentity),
            remoteSubtitle,
            "publisher-provided remote subtitle language should round-trip"
        )
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: remoteSubtitle,
                tracks: [],
                isLoaded: true
            ),
            .remoteLanguage("zh-Hans"),
            "remote subtitle language should restore without a local file URL"
        )

        let manualRemoteOption = RemoteVideoSubtitleOption(
            id: ".ja",
            language: "ja",
            name: "Japanese",
            url: URL(string: "https://example.com/ja.vtt")!,
            format: .webVTT,
            isAutomatic: false,
            httpHeaders: [:]
        )
        let automaticRemoteOption = RemoteVideoSubtitleOption(
            id: "a.ja",
            language: "ja",
            name: "Japanese (auto-generated)",
            url: URL(string: "https://example.com/ja-auto.vtt")!,
            format: .webVTT,
            isAutomatic: true,
            httpHeaders: [:]
        )
        let remoteOptionSelection = VideoSubtitleSelection.remoteOption(
            automaticRemoteOption.selectionIdentity
        )
        store.save(subtitleSelection: remoteOptionSelection, for: remoteIdentity)
        expect(
            VideoPlaybackHistoryStore(defaults: defaults, fileURL: historyFileURL)
                .subtitleSelection(for: remoteIdentity),
            remoteOptionSelection,
            "a remote subtitle option identity should round-trip through playback history"
        )
        expect(
            VideoSubtitleRestoreResolver.resolve(
                selection: remoteOptionSelection,
                tracks: [],
                isLoaded: true
            ),
            .remoteOption(automaticRemoteOption.selectionIdentity),
            "remote subtitle option identity should remain available during restore"
        )

        let remoteSource = ResolvedRemoteVideoSource(
            identity: RemoteVideoIdentity(
                providerID: "youtube",
                remoteID: "abc123",
                originalURL: URL(string: "https://www.youtube.com/watch?v=abc123")!,
                canonicalURL: nil,
                title: "Remote",
                thumbnailURL: nil
            ),
            playbackStream: RemoteVideoStream(
                url: URL(string: "https://example.com/video.mp4")!,
                hasVideo: true,
                hasAudio: true
            ),
            audioStream: nil,
            miningStream: nil,
            subtitleOptions: [manualRemoteOption, automaticRemoteOption],
            selectedSubtitleLanguage: nil,
            resolvedAt: date,
            expiresAt: nil
        )
        expect(
            remoteSource.subtitleOption(matching: automaticRemoteOption.selectionIdentity),
            automaticRemoteOption,
            "same-language automatic subtitles should restore by their exact ID"
        )
        let replacementAutomaticOption = RemoteVideoSubtitleOption(
            id: "a.ja.updated",
            language: "ja",
            name: "Japanese (auto-generated)",
            url: URL(string: "https://example.com/ja-auto-updated.vtt")!,
            format: .webVTT,
            isAutomatic: true,
            httpHeaders: [:]
        )
        let changedIDSource = ResolvedRemoteVideoSource(
            identity: remoteSource.identity,
            playbackStream: remoteSource.playbackStream,
            audioStream: nil,
            miningStream: nil,
            subtitleOptions: [manualRemoteOption, replacementAutomaticOption],
            selectedSubtitleLanguage: nil,
            resolvedAt: date,
            expiresAt: nil
        )
        expect(
            changedIDSource.subtitleOption(matching: automaticRemoteOption.selectionIdentity),
            replacementAutomaticOption,
            "changed remote track IDs should fall back to language and automatic-track identity"
        )
        expect(
            remoteSource.preferredSubtitle(language: "ja"),
            manualRemoteOption,
            "legacy language-only selections should continue preferring publisher captions"
        )
        store.clearProgress(for: remoteIdentity)
        expect(
            store.playbackState(for: remoteIdentity),
            nil,
            "remote playback progress should clear without a file URL"
        )

        print("Video playback history tests passed")
    }
}
