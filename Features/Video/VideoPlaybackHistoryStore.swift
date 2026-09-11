import Foundation

nonisolated struct VideoSubtitleTrackIdentity: Codable, Equatable, Hashable, Sendable {
    let trackID: Int
    let ffIndex: Int?
    let title: String
    let language: String?
    let codec: String?

    init(track: VideoTrack) {
        trackID = track.id
        ffIndex = track.ffIndex
        title = track.title
        language = track.language
        codec = track.codec
    }

    func matchingTrackID(in tracks: [VideoTrack]) -> Int? {
        let subtitleTracks = tracks.filter { $0.type == .subtitle }
        if let ffIndex {
            if let match = subtitleTracks.first(where: { $0.ffIndex == ffIndex }) {
                return match.id
            }
        } else if let match = subtitleTracks.first(where: { $0.id == trackID }) {
            return match.id
        }
        let metadataMatches = subtitleTracks.filter {
            $0.title == title
                && $0.language == language
                && $0.codec == codec
        }
        return metadataMatches.count == 1 ? metadataMatches[0].id : nil
    }
}

nonisolated enum VideoSubtitleSelection: Codable, Equatable, Hashable, Sendable {
    case off
    case embedded(VideoSubtitleTrackIdentity)
    case external(path: String)
    case externalDisabled(path: String)
    case remoteOption(RemoteVideoSubtitleSelectionIdentity)
    case remote(language: String)

    func matchingTrackID(in tracks: [VideoTrack]) -> Int? {
        guard case .embedded(let identity) = self else { return nil }
        return identity.matchingTrackID(in: tracks)
    }
}

nonisolated struct VideoAudioTrackIdentity: Codable, Equatable, Hashable, Sendable {
    let trackID: Int
    let ffIndex: Int?
    let title: String
    let language: String?
    let codec: String?

    init(track: VideoTrack) {
        trackID = track.id
        ffIndex = track.ffIndex
        title = track.title
        language = track.language
        codec = track.codec
    }

    func matchingTrackID(in tracks: [VideoTrack]) -> Int? {
        let audioTracks = tracks.filter { $0.type == .audio }
        if let ffIndex {
            if let match = audioTracks.first(where: { $0.ffIndex == ffIndex }) {
                return match.id
            }
        } else if let match = audioTracks.first(where: { $0.id == trackID }) {
            return match.id
        }
        let metadataMatches = audioTracks.filter {
            $0.title == title
                && $0.language == language
                && $0.codec == codec
        }
        return metadataMatches.count == 1 ? metadataMatches[0].id : nil
    }
}

nonisolated enum VideoAudioSelection: Codable, Equatable, Hashable, Sendable {
    case off
    case embedded(VideoAudioTrackIdentity)

    func matchingTrackID(in tracks: [VideoTrack]) -> Int? {
        guard case .embedded(let identity) = self else { return nil }
        return identity.matchingTrackID(in: tracks)
    }
}

nonisolated struct VideoPlaybackResumeOptions: Codable, Equatable, Sendable {
    static let empty = VideoPlaybackResumeOptions()

    let speed: Double?
    let subtitleDelay: TimeInterval?
    let audioDelay: TimeInterval?
    let audioSelection: VideoAudioSelection?

    var isEmpty: Bool {
        speed == nil
            && subtitleDelay == nil
            && audioDelay == nil
            && audioSelection == nil
    }

    init(
        speed: Double? = nil,
        subtitleDelay: TimeInterval? = nil,
        audioDelay: TimeInterval? = nil,
        audioSelection: VideoAudioSelection? = nil
    ) {
        self.speed = speed.map(Self.normalizedSpeed)
        self.subtitleDelay = subtitleDelay.map(Self.normalizedSubtitleDelay)
        self.audioDelay = audioDelay.map(Self.normalizedAudioDelay)
        self.audioSelection = audioSelection
    }

    init(snapshot: VideoPlaybackSnapshot) {
        let normalizedSpeed = Self.normalizedSpeed(snapshot.speed)
        speed = abs(normalizedSpeed - Self.normalSpeed) >= 0.001
            ? normalizedSpeed
            : nil

        let normalizedSubtitleDelay = Self.normalizedSubtitleDelay(snapshot.subtitleDelay)
        subtitleDelay = abs(normalizedSubtitleDelay) >= 0.005
            ? normalizedSubtitleDelay
            : nil

        let normalizedAudioDelay = Self.normalizedAudioDelay(snapshot.audioDelay)
        audioDelay = abs(normalizedAudioDelay) >= 0.005
            ? normalizedAudioDelay
            : nil

        audioSelection = Self.audioSelection(from: snapshot.tracks)
    }

    private static func audioSelection(from tracks: [VideoTrack]) -> VideoAudioSelection? {
        let audioTracks = tracks.filter { $0.type == .audio }
        guard !audioTracks.isEmpty else { return nil }
        guard let selectedTrack = audioTracks.first(where: \.isSelected) else {
            return .off
        }
        return .embedded(VideoAudioTrackIdentity(track: selectedTrack))
    }

    private static func normalizedSubtitleDelay(_ delay: TimeInterval) -> TimeInterval {
        VideoSubtitleTiming.clampedDelay(delay)
    }

    private static func normalizedAudioDelay(_ delay: TimeInterval) -> TimeInterval {
        min(max(delay, -30), 30)
    }

    private static let minimumSpeed = 0.25
    private static let maximumSpeed = 5.0
    private static let normalSpeed = 1.0
    private static let customInputLowerBound = 0.3
    private static let customStep = 0.1

    private static func normalizedSpeed(_ speed: Double) -> Double {
        guard speed.isFinite else { return normalSpeed }
        guard speed > minimumSpeed else { return minimumSpeed }
        let rounded = (speed / customStep).rounded() * customStep
        return min(max(rounded, customInputLowerBound), maximumSpeed)
    }
}

nonisolated enum VideoSubtitleRestoreResolution: Equatable, Sendable {
    case off
    case external(URL)
    case externalDisabled(URL)
    case embeddedTrack(Int)
    case remoteOption(RemoteVideoSubtitleSelectionIdentity)
    case remoteLanguage(String)
    case waitingForTracks
    case unavailable
}

nonisolated enum VideoSubtitleRestoreResolver {
    static func resolve(
        selection: VideoSubtitleSelection,
        tracks: [VideoTrack],
        isLoaded: Bool,
        fileManager: FileManager = .default
    ) -> VideoSubtitleRestoreResolution {
        switch selection {
        case .off:
            return .off
        case .external(let path):
            let url = URL(fileURLWithPath: path).standardizedFileURL
            return fileManager.fileExists(atPath: url.path)
                ? .external(url)
                : .unavailable
        case .externalDisabled(let path):
            let url = URL(fileURLWithPath: path).standardizedFileURL
            return fileManager.fileExists(atPath: url.path)
                ? .externalDisabled(url)
                : .unavailable
        case .remote(let language):
            return .remoteLanguage(language)
        case .remoteOption(let identity):
            return .remoteOption(identity)
        case .embedded:
            guard isLoaded else { return .waitingForTracks }
            if let trackID = selection.matchingTrackID(in: tracks) {
                return .embeddedTrack(trackID)
            }
            return isLoaded && !tracks.isEmpty
                ? .unavailable
                : .waitingForTracks
        }
    }
}

nonisolated struct VideoPlaybackState: Codable, Equatable, Sendable {
    let position: TimeInterval
    let duration: TimeInterval?
    let updatedAt: Date
    let isFinished: Bool
    let resumeOptions: VideoPlaybackResumeOptions

    var progress: Double? {
        if isFinished {
            return 1
        }
        guard let duration, duration > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }

    var isResumable: Bool {
        guard !isFinished, position >= 2 else { return false }
        return progress.map { $0 < 0.98 } ?? true
    }

    var remainingTime: TimeInterval? {
        guard !isFinished, let duration, duration > position else { return nil }
        return duration - position
    }

    init(
        position: TimeInterval,
        duration: TimeInterval?,
        updatedAt: Date,
        isFinished: Bool = false,
        resumeOptions: VideoPlaybackResumeOptions = .empty
    ) {
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
        self.isFinished = isFinished
        self.resumeOptions = resumeOptions
    }

    private enum CodingKeys: String, CodingKey {
        case position
        case duration
        case updatedAt
        case isFinished
        case resumeOptions
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decode(TimeInterval.self, forKey: .position)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isFinished = try container.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
        resumeOptions = try container.decodeIfPresent(
            VideoPlaybackResumeOptions.self,
            forKey: .resumeOptions
        ) ?? .empty
    }
}

nonisolated final class VideoPlaybackHistoryStore: @unchecked Sendable {
    private static let persistenceQueue = DispatchQueue(
        label: "moe.shishamo.hoshi.video.playback-history",
        qos: .utility
    )
    static let didChangeNotification = Notification.Name(
        "moe.shishamo.hoshi.video.playback-history.did-change"
    )

    private static let changedIdentityPersistenceKey = "identityPersistenceKey"
    private static let positionKey = "videoPlaybackPositions"
    private static let playbackStateKey = "videoPlaybackStates"
    private static let subtitleSelectionKey = "videoSubtitleSelections"
    private static let sharedStorage = Storage(
        defaults: .standard,
        fileURL: defaultFileURL(fileManager: .default),
        fileManager: .default
    )

    private let storage: Storage

    init(
        defaults: UserDefaults = .standard,
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if defaults === UserDefaults.standard, fileURL == nil {
            storage = Self.sharedStorage
        } else {
            storage = Storage(
                defaults: defaults,
                fileURL: fileURL,
                fileManager: fileManager
            )
        }
    }

    static func changedIdentityPersistenceKey(from notification: Notification) -> String? {
        notification.userInfo?[changedIdentityPersistenceKey] as? String
    }

    func position(for url: URL) -> TimeInterval? {
        position(for: Self.localIdentity(for: url))
    }

    func position(for identity: VideoMediaIdentity) -> TimeInterval? {
        if let state = playbackState(for: identity) {
            return state.isResumable ? state.position : nil
        }
        return storage.snapshot().positions[identity.persistenceKey]
    }

    func save(
        position: TimeInterval,
        duration: TimeInterval,
        resumeOptions: VideoPlaybackResumeOptions = .empty,
        for url: URL
    ) {
        savePlaybackState(
            position: position,
            duration: duration,
            updatedAt: Date(),
            resumeOptions: resumeOptions,
            for: Self.localIdentity(for: url)
        )
    }

    func save(
        position: TimeInterval,
        duration: TimeInterval,
        resumeOptions: VideoPlaybackResumeOptions = .empty,
        for identity: VideoMediaIdentity
    ) {
        savePlaybackState(
            position: position,
            duration: duration,
            updatedAt: Date(),
            resumeOptions: resumeOptions,
            for: identity
        )
    }

    func playbackState(for url: URL) -> VideoPlaybackState? {
        playbackState(for: Self.localIdentity(for: url))
    }

    func playbackState(for identity: VideoMediaIdentity) -> VideoPlaybackState? {
        let key = identity.persistenceKey
        let snapshot = storage.snapshot()
        if let state = snapshot.playbackStates[key] {
            return state
        }
        guard let position = snapshot.positions[key] else { return nil }
        return VideoPlaybackState(
            position: position,
            duration: nil,
            updatedAt: .distantPast
        )
    }

    func playbackStates(for urls: [URL]) -> [String: VideoPlaybackState] {
        playbackStates(for: urls.map(Self.localIdentity(for:)))
    }

    func playbackStates(
        for identities: [VideoMediaIdentity]
    ) -> [String: VideoPlaybackState] {
        let snapshot = storage.snapshot()
        var result: [String: VideoPlaybackState] = [:]
        result.reserveCapacity(identities.count)

        for identity in identities {
            let key = identity.persistenceKey
            if let state = snapshot.playbackStates[key] {
                result[key] = state
            } else if let position = snapshot.positions[key] {
                result[key] = VideoPlaybackState(
                    position: position,
                    duration: nil,
                    updatedAt: .distantPast
                )
            }
        }

        return result
    }

    func savePlaybackState(
        position: TimeInterval,
        duration: TimeInterval,
        updatedAt: Date = Date(),
        resumeOptions: VideoPlaybackResumeOptions = .empty,
        for url: URL
    ) {
        savePlaybackState(
            position: position,
            duration: duration,
            updatedAt: updatedAt,
            resumeOptions: resumeOptions,
            for: Self.localIdentity(for: url)
        )
    }

    func savePlaybackState(
        position: TimeInterval,
        duration: TimeInterval,
        updatedAt: Date = Date(),
        resumeOptions: VideoPlaybackResumeOptions = .empty,
        for identity: VideoMediaIdentity
    ) {
        updatePlaybackState(
            position: position,
            duration: duration,
            updatedAt: updatedAt,
            resumeOptions: resumeOptions,
            for: identity,
            deferred: false
        )
    }

    private func updatePlaybackState(
        position: TimeInterval,
        duration: TimeInterval,
        updatedAt: Date,
        resumeOptions: VideoPlaybackResumeOptions,
        for identity: VideoMediaIdentity,
        deferred: Bool
    ) {
        let key = identity.persistenceKey
        let changed = storage.mutate(deferred: deferred) { snapshot in
            if duration <= 0 || position < 2 {
                let removedPosition = snapshot.positions.removeValue(forKey: key) != nil
                let removedState = snapshot.playbackStates.removeValue(forKey: key) != nil
                return removedPosition || removedState
            } else if position >= duration - 5 {
                let state = VideoPlaybackState(
                    position: duration,
                    duration: duration,
                    updatedAt: updatedAt,
                    isFinished: true
                )
                guard snapshot.positions[key] != nil || snapshot.playbackStates[key] != state else {
                    return false
                }
                snapshot.positions.removeValue(forKey: key)
                snapshot.playbackStates[key] = state
                return true
            } else {
                let state = VideoPlaybackState(
                    position: position,
                    duration: duration,
                    updatedAt: updatedAt,
                    resumeOptions: resumeOptions
                )
                guard snapshot.positions[key] != position || snapshot.playbackStates[key] != state else {
                    return false
                }
                snapshot.positions[key] = position
                snapshot.playbackStates[key] = state
                return true
            }
        }
        if changed {
            postChange(for: key)
        }
    }

    func savePlaybackStateDeferred(
        position: TimeInterval,
        duration: TimeInterval,
        updatedAt: Date = Date(),
        resumeOptions: VideoPlaybackResumeOptions = .empty,
        for url: URL
    ) {
        savePlaybackStateDeferred(
            position: position,
            duration: duration,
            updatedAt: updatedAt,
            resumeOptions: resumeOptions,
            for: Self.localIdentity(for: url)
        )
    }

    func savePlaybackStateDeferred(
        position: TimeInterval,
        duration: TimeInterval,
        updatedAt: Date = Date(),
        resumeOptions: VideoPlaybackResumeOptions = .empty,
        for identity: VideoMediaIdentity
    ) {
        updatePlaybackState(
            position: position,
            duration: duration,
            updatedAt: updatedAt,
            resumeOptions: resumeOptions,
            for: identity,
            deferred: true
        )
    }

    func markWatched(
        duration: TimeInterval?,
        updatedAt: Date = Date(),
        for url: URL
    ) {
        markWatched(
            duration: duration,
            updatedAt: updatedAt,
            for: Self.localIdentity(for: url)
        )
    }

    func markWatched(
        duration: TimeInterval?,
        updatedAt: Date = Date(),
        for identity: VideoMediaIdentity
    ) {
        let key = identity.persistenceKey
        let state = VideoPlaybackState(
            position: max(duration ?? 0, 0),
            duration: duration,
            updatedAt: updatedAt,
            isFinished: true
        )
        let changed = storage.mutate(deferred: false) { snapshot in
            guard snapshot.positions[key] != nil || snapshot.playbackStates[key] != state else {
                return false
            }
            snapshot.positions.removeValue(forKey: key)
            snapshot.playbackStates[key] = state
            return true
        }
        if changed {
            postChange(for: key)
        }
    }

    func clearProgress(for url: URL) {
        clearProgress(for: Self.localIdentity(for: url))
    }

    func clearProgress(for identity: VideoMediaIdentity) {
        let key = identity.persistenceKey
        let changed = storage.mutate(deferred: false) { snapshot in
            let removedPosition = snapshot.positions.removeValue(forKey: key) != nil
            let removedState = snapshot.playbackStates.removeValue(forKey: key) != nil
            return removedPosition || removedState
        }
        if changed {
            postChange(for: key)
        }
    }

    func subtitleSelection(for url: URL) -> VideoSubtitleSelection? {
        subtitleSelection(for: Self.localIdentity(for: url))
    }

    func subtitleSelection(for identity: VideoMediaIdentity) -> VideoSubtitleSelection? {
        storage.snapshot().subtitleSelections[identity.persistenceKey]
    }

    func externalSubtitlePath(for identity: VideoMediaIdentity) -> String? {
        let snapshot = storage.snapshot()
        if let path = snapshot.externalSubtitlePaths[identity.persistenceKey] {
            return path
        }
        switch snapshot.subtitleSelections[identity.persistenceKey] {
        case .external(let path), .externalDisabled(let path):
            return path
        default:
            return nil
        }
    }

    func allExternalSubtitlePaths() -> [String] {
        let snapshot = storage.snapshot()
        var paths = Set(snapshot.externalSubtitlePaths.values)
        paths.formUnion(snapshot.subtitleSelections.values.compactMap { selection in
            switch selection {
            case .external(let path), .externalDisabled(let path):
                return path
            default:
                return nil
            }
        })
        return Array(paths)
    }

    func save(subtitleSelection: VideoSubtitleSelection, for url: URL) {
        save(
            subtitleSelection: subtitleSelection,
            for: Self.localIdentity(for: url)
        )
    }

    func save(
        subtitleSelection: VideoSubtitleSelection,
        for identity: VideoMediaIdentity
    ) {
        let key = identity.persistenceKey
        let changed = storage.mutate(deferred: false) { snapshot in
            var changed = false
            if snapshot.subtitleSelections[key] != subtitleSelection {
                snapshot.subtitleSelections[key] = subtitleSelection
                changed = true
            }
            switch subtitleSelection {
            case .external(let path), .externalDisabled(let path):
                if snapshot.externalSubtitlePaths[key] != path {
                    snapshot.externalSubtitlePaths[key] = path
                    changed = true
                }
            default:
                break
            }
            return changed
        }
        if changed {
            postChange(for: key)
        }
    }

    func saveExternalSubtitlePath(
        _ path: String,
        for identity: VideoMediaIdentity
    ) {
        let key = identity.persistenceKey
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let changed = storage.mutate(deferred: false) { snapshot in
            guard snapshot.externalSubtitlePaths[key] != normalizedPath else {
                return false
            }
            snapshot.externalSubtitlePaths[key] = normalizedPath
            return true
        }
        if changed {
            postChange(for: key)
        }
    }

    private static func localIdentity(for url: URL) -> VideoMediaIdentity {
        .localFile(path: url.standardizedFileURL.path)
    }

    private func postChange(for identityPersistenceKey: String) {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [Self.changedIdentityPersistenceKey: identityPersistenceKey]
        )
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        if let override = ProcessInfo.processInfo.environment[
            "HOSHI_VIDEO_PLAYBACK_HISTORY_URL"
        ], !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: false)
                .standardizedFileURL
        }
        let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return directory.appendingPathComponent("video_playback_history.json")
    }

    private struct Snapshot: Codable, Equatable, Sendable {
        var positions: [String: TimeInterval] = [:]
        var playbackStates: [String: VideoPlaybackState] = [:]
        var subtitleSelections: [String: VideoSubtitleSelection] = [:]
        var externalSubtitlePaths: [String: String] = [:]

        var isEmpty: Bool {
            positions.isEmpty
                && playbackStates.isEmpty
                && subtitleSelections.isEmpty
                && externalSubtitlePaths.isEmpty
        }

        private enum CodingKeys: String, CodingKey {
            case positions
            case playbackStates
            case subtitleSelections
            case externalSubtitlePaths
        }

        init(
            positions: [String: TimeInterval] = [:],
            playbackStates: [String: VideoPlaybackState] = [:],
            subtitleSelections: [String: VideoSubtitleSelection] = [:],
            externalSubtitlePaths: [String: String] = [:]
        ) {
            self.positions = positions
            self.playbackStates = playbackStates
            self.subtitleSelections = subtitleSelections
            self.externalSubtitlePaths = externalSubtitlePaths
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            positions = try container.decodeIfPresent(
                [String: TimeInterval].self,
                forKey: .positions
            ) ?? [:]
            playbackStates = try container.decodeIfPresent(
                [String: VideoPlaybackState].self,
                forKey: .playbackStates
            ) ?? [:]
            subtitleSelections = try container.decodeIfPresent(
                [String: VideoSubtitleSelection].self,
                forKey: .subtitleSelections
            ) ?? [:]
            externalSubtitlePaths = try container.decodeIfPresent(
                [String: String].self,
                forKey: .externalSubtitlePaths
            ) ?? [:]
        }
    }

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private let fileURL: URL?
        private let fileManager: FileManager
        private var value: Snapshot
        private var pendingPersistence: Snapshot?
        private var isPersistenceScheduled = false

        init(
            defaults: UserDefaults,
            fileURL: URL?,
            fileManager: FileManager
        ) {
            self.fileURL = fileURL
            self.fileManager = fileManager
            if let fileURL,
               let data = try? Data(contentsOf: fileURL),
               let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                value = snapshot
            } else {
                value = Self.legacySnapshot(defaults: defaults)
                if let fileURL, !value.isEmpty {
                    Self.persist(value, to: fileURL, fileManager: fileManager)
                }
            }
        }

        func snapshot() -> Snapshot {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func mutate(
            deferred: Bool,
            _ mutation: (inout Snapshot) -> Bool
        ) -> Bool {
            lock.lock()
            guard mutation(&value) else {
                lock.unlock()
                return false
            }
            guard fileURL != nil else {
                lock.unlock()
                return true
            }

            pendingPersistence = value
            let shouldSchedule = !isPersistenceScheduled
            if shouldSchedule {
                isPersistenceScheduled = true
            }
            lock.unlock()

            if shouldSchedule {
                VideoPlaybackHistoryStore.persistenceQueue.async { [self] in
                    flushPendingPersistence()
                }
            }
            if !deferred {
                VideoPlaybackHistoryStore.persistenceQueue.sync { [self] in
                    flushPendingPersistence()
                }
            }
            return true
        }

        private func flushPendingPersistence() {
            while true {
                lock.lock()
                guard let snapshot = pendingPersistence, let fileURL else {
                    isPersistenceScheduled = false
                    lock.unlock()
                    return
                }
                pendingPersistence = nil
                lock.unlock()

                Self.persist(snapshot, to: fileURL, fileManager: fileManager)
            }
        }

        private static func legacySnapshot(defaults: UserDefaults) -> Snapshot {
            let positions = defaults.dictionary(
                forKey: VideoPlaybackHistoryStore.positionKey
            )?.compactMapValues { ($0 as? NSNumber)?.doubleValue } ?? [:]
            let decoder = JSONDecoder()
            let playbackStates = defaults.dictionary(
                forKey: VideoPlaybackHistoryStore.playbackStateKey
            )?.compactMapValues { value -> VideoPlaybackState? in
                guard let data = value as? Data else { return nil }
                return try? decoder.decode(VideoPlaybackState.self, from: data)
            } ?? [:]
            let subtitleSelections = defaults.dictionary(
                forKey: VideoPlaybackHistoryStore.subtitleSelectionKey
            )?.compactMapValues { value -> VideoSubtitleSelection? in
                guard let data = value as? Data else { return nil }
                return try? decoder.decode(VideoSubtitleSelection.self, from: data)
            } ?? [:]
            return Snapshot(
                positions: positions,
                playbackStates: playbackStates,
                subtitleSelections: subtitleSelections,
                externalSubtitlePaths: subtitleSelections.reduce(into: [:]) { result, entry in
                    switch entry.value {
                    case .external(let path), .externalDisabled(let path):
                        result[entry.key] = path
                    default:
                        break
                    }
                }
            )
        }

        private static func persist(
            _ snapshot: Snapshot,
            to fileURL: URL,
            fileManager: FileManager
        ) {
            do {
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
            } catch {
                // Playback must continue even when optional history persistence fails.
            }
        }
    }
}
