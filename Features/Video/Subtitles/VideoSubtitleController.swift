import Foundation
import Observation

nonisolated struct PreparedSubtitleLoad: Sendable {
    let document: SubtitleDocument
    let store: SubtitleCueStore
    let transcript: SubtitleTranscript
    let assRenderPlan: ASSRenderPlan?
    let assEffectsURL: URL?
    let assEffectsPreparationFailed: Bool

    nonisolated init(
        document: SubtitleDocument,
        store: SubtitleCueStore,
        transcript: SubtitleTranscript,
        assRenderPlan: ASSRenderPlan? = nil,
        assEffectsURL: URL? = nil,
        assEffectsPreparationFailed: Bool = false
    ) {
        self.document = document
        self.store = store
        self.transcript = transcript
        self.assRenderPlan = assRenderPlan ?? document.assRenderPlan
        self.assEffectsURL = assEffectsURL
        self.assEffectsPreparationFailed = assEffectsPreparationFailed
    }

    nonisolated func discardTemporaryResources() {
        guard let assEffectsURL else { return }
        try? FileManager.default.removeItem(at: assEffectsURL)
    }
}

@Observable
@MainActor
final class VideoSubtitleController {
    private(set) var document: SubtitleDocument?
    private(set) var currentCues: [SubtitleCue] = []
    private(set) var transcript = SubtitleTranscript(primary: nil, secondary: nil)
    private(set) var isTranscriptLoading = false
    private(set) var transcriptErrorMessage: String?
    private(set) var assEffectsURL: URL?
    private(set) var assEffectsPreparationFailed = false
    var errorMessage: String?

    private var store: SubtitleCueStore?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var transcriptGeneration = 0
    @ObservationIgnored private var activeEmbeddedTrackID: Int?
    @ObservationIgnored private var hasCompleteEmbeddedTimeline = false
    @ObservationIgnored private var externalLoadWorker: Task<Result<PreparedSubtitleLoad, Error>, Never>?

    @discardableResult
    func load(_ url: URL) -> Task<Void, Never> {
        invalidateExternalLoad()
        let generation = loadGeneration
        let worker = Task.detached(priority: .userInitiated) {
            Self.prepareExternalSubtitle(
                url,
                generation: generation,
                isCancelled: {
                    withUnsafeCurrentTask { $0?.isCancelled ?? false }
                }
            )
        }
        externalLoadWorker = worker
        return Task { @MainActor [weak self] in
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self else {
                if case .success(let load) = result {
                    load.discardTemporaryResources()
                }
                return
            }
            guard !Task.isCancelled else {
                if case .success(let load) = result {
                    load.discardTemporaryResources()
                }
                if generation == self.loadGeneration {
                    self.externalLoadWorker = nil
                }
                return
            }
            if generation == self.loadGeneration {
                self.externalLoadWorker = nil
            }
            self.applyPrimarySubtitleLoad(result, generation: generation)
        }
    }

    nonisolated private static func prepareExternalSubtitle(
        _ url: URL,
        generation: Int,
        isCancelled: @escaping @Sendable () -> Bool
    ) -> Result<PreparedSubtitleLoad, Error> {
        do {
            let document = try parseExternalSubtitle(
                url,
                isCancelled: isCancelled
            )
            return .success(try makePreparedLoad(
                document: document,
                transcript: SubtitleTranscript(
                    primary: document,
                    secondary: nil,
                    generation: generation
                ),
                isCancelled: isCancelled
            ))
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func parseExternalSubtitle(
        _ url: URL,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> SubtitleDocument {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        if isCancelled() {
            throw CancellationError()
        }
        let data = try Data(contentsOf: url)
        if isCancelled() {
            throw CancellationError()
        }
        return try SubtitleParser.parse(
            data: data,
            sourceURL: url,
            isCancelled: isCancelled
        )
    }

    private func applyPrimarySubtitleLoad(
        _ result: Result<PreparedSubtitleLoad, Error>,
        generation: Int
    ) {
        guard generation == loadGeneration else {
            if case .success(let load) = result {
                load.discardTemporaryResources()
            }
            return
        }
        switch result {
        case .success(let load):
            replaceTemporaryEffectsFile(with: load.assEffectsURL)
            activeEmbeddedTrackID = nil
            hasCompleteEmbeddedTimeline = false
            self.document = load.document
            store = load.store
            currentCues = []
            transcriptGeneration = generation
            transcript = load.transcript
            isTranscriptLoading = false
            transcriptErrorMessage = nil
            assEffectsPreparationFailed = load.assEffectsPreparationFailed
            errorMessage = nil
        case .failure(let error):
            replaceTemporaryEffectsFile(with: nil)
            assEffectsPreparationFailed = false
            document = nil
            store = nil
            currentCues = []
            rebuildTranscript()
            errorMessage = error.localizedDescription
        }
    }

    func loadEmbedded(
        _ cues: [VideoEmbeddedSubtitleCue],
        sourceURL: URL
    ) {
        if let format = document?.format, format != .embedded {
            return
        }
        guard !hasCompleteEmbeddedTimeline else { return }
        guard !cues.isEmpty else {
            currentCues = []
            return
        }
        let existingCues = document?.format == .embedded ? document?.cues ?? [] : []
        let incomingCues = cues.map(Self.makeSubtitleCue)
        let document = SubtitleDocument(
            sourceURL: sourceURL,
            format: .embedded,
            cues: Self.deduplicatedSortedCues(existingCues + incomingCues),
            warnings: []
        )
        self.document = document
        store = SubtitleCueStore(document: document)
        currentCues = []
        rebuildTranscript()
        errorMessage = nil
    }

    func beginEmbeddedTrack(trackID: Int, sourceURL: URL) {
        invalidateExternalLoad()
        replaceTemporaryEffectsFile(with: nil)
        assEffectsPreparationFailed = false
        activeEmbeddedTrackID = trackID
        hasCompleteEmbeddedTimeline = false
        let document = SubtitleDocument(
            sourceURL: sourceURL,
            format: .embedded,
            cues: [],
            warnings: []
        )
        self.document = document
        store = SubtitleCueStore(document: document)
        currentCues = []
        rebuildTranscript()
        isTranscriptLoading = true
        transcriptErrorMessage = nil
        errorMessage = nil
    }

    func failEmbeddedTranscript(
        _ message: String,
        trackID: Int
    ) {
        guard activeEmbeddedTrackID == trackID else { return }
        hasCompleteEmbeddedTimeline = false
        isTranscriptLoading = false
        transcriptErrorMessage = message
    }

    nonisolated static func prepareEmbeddedTranscript(
        _ cues: [VideoEmbeddedSubtitleCue],
        sourceURL: URL
    ) -> PreparedSubtitleLoad {
        try! prepareEmbeddedTranscript(
            cues,
            sourceURL: sourceURL,
            isCancelled: { false }
        )
    }

    nonisolated static func prepareEmbeddedTranscript(
        _ cues: [VideoEmbeddedSubtitleCue],
        sourceURL: URL,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> PreparedSubtitleLoad {
        try throwIfCancelled(isCancelled)
        var subtitleCues: [SubtitleCue] = []
        subtitleCues.reserveCapacity(cues.count)
        for cue in cues {
            try throwIfCancelled(isCancelled)
            subtitleCues.append(makeSubtitleCue(cue))
        }
        let document = SubtitleDocument(
            sourceURL: sourceURL,
            format: .embedded,
            cues: try Self.deduplicatedSortedCues(
                subtitleCues,
                isCancelled: isCancelled
            ),
            warnings: []
        )
        return try makePreparedLoad(
            document: document,
            transcript: SubtitleTranscript(primary: document, secondary: nil),
            isCancelled: isCancelled
        )
    }

    nonisolated static func prepareEmbeddedTranscript(
        _ extractedTrack: ExtractedSubtitleTrack,
        sourceURL: URL,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) throws -> PreparedSubtitleLoad {
        try throwIfCancelled(isCancelled)
        let codec = extractedTrack.codec?.lowercased()
        guard codec == "ass" || codec == "ssa" else {
            return try prepareEmbeddedTranscript(
                extractedTrack.cues,
                sourceURL: sourceURL,
                isCancelled: isCancelled
            )
        }
        guard let reconstructedASSData = try extractedTrack.reconstructedASSData(
            isCancelled: isCancelled
        ) else {
            throw SubtitleParserError.noValidCues
        }
        try throwIfCancelled(isCancelled)
        let parsed = try SubtitleParser.parse(
            data: reconstructedASSData,
            sourceURL: sourceURL,
            formatHint: codec == "ssa" ? .ssa : .ass,
            isCancelled: isCancelled
        )
        let document = SubtitleDocument(
            sourceURL: sourceURL,
            format: .embedded,
            cues: parsed.cues,
            warnings: parsed.warnings,
            assRenderPlan: parsed.assRenderPlan
        )
        return try makePreparedLoad(
            document: document,
            transcript: SubtitleTranscript(primary: document, secondary: nil),
            isCancelled: isCancelled
        )
    }

    func replaceEmbeddedTranscript(
        _ load: PreparedSubtitleLoad,
        trackID: Int
    ) {
        guard activeEmbeddedTrackID == trackID else {
            load.discardTemporaryResources()
            return
        }
        replaceTemporaryEffectsFile(with: load.assEffectsURL)
        let document = load.document
        self.document = document
        store = load.store
        currentCues = []
        transcriptGeneration += 1
        transcript = load.transcript.replacingGeneration(transcriptGeneration)
        hasCompleteEmbeddedTimeline = true
        isTranscriptLoading = false
        transcriptErrorMessage = nil
        assEffectsPreparationFailed = load.assEffectsPreparationFailed
        errorMessage = nil
    }

    func update(time: TimeInterval, subtitleDelay: TimeInterval = 0) {
        let nextCurrentCues = store?.cues(
            atPlaybackTime: time,
            subtitleDelay: subtitleDelay
        ) ?? []
        if nextCurrentCues != currentCues {
            currentCues = nextCurrentCues
        }
    }

    func slice(time: TimeInterval, subtitleDelay: TimeInterval = 0) -> SubtitleCueSlice {
        store?.slice(atPlaybackTime: time, subtitleDelay: subtitleDelay)
            ?? SubtitleCueSlice(showing: [], lastShown: [], nextToShow: [])
    }

    func delayAligningAdjacentCue(
        atPlaybackTime playbackTime: TimeInterval,
        subtitleDelay: TimeInterval,
        direction: SubtitleOffsetAlignmentDirection
    ) -> TimeInterval? {
        store?.delayAligningAdjacentCue(
            atPlaybackTime: playbackTime,
            subtitleDelay: subtitleDelay,
            direction: direction
        )
    }

    func clear() {
        clearPrimary()
        errorMessage = nil
    }

    func cancelPendingPrimaryLoad() {
        invalidateExternalLoad()
    }

    func clearPrimary() {
        invalidateExternalLoad()
        replaceTemporaryEffectsFile(with: nil)
        assEffectsPreparationFailed = false
        activeEmbeddedTrackID = nil
        hasCompleteEmbeddedTimeline = false
        document = nil
        store = nil
        currentCues = []
        rebuildTranscript()
        isTranscriptLoading = false
        transcriptErrorMessage = nil
        errorMessage = nil
    }

    private func invalidateExternalLoad() {
        externalLoadWorker?.cancel()
        externalLoadWorker = nil
        loadGeneration &+= 1
    }

    func discardTemporaryASSEffects() {
        replaceTemporaryEffectsFile(with: nil)
        assEffectsPreparationFailed = false
    }

    func markASSEffectsInstallationFailed() {
        replaceTemporaryEffectsFile(with: nil)
        assEffectsPreparationFailed = true
    }

    @discardableResult
    func prepareTemporaryASSEffectsIfNeeded() -> Bool {
        guard !assEffectsPreparationFailed else { return false }
        if assEffectsURL != nil { return true }
        guard let data = document?.assRenderPlan?.interactiveEffectsOnlyData else { return true }
        let result = Self.prepareTemporaryEffectsFile(from: data)
        replaceTemporaryEffectsFile(with: result.url)
        assEffectsPreparationFailed = result.failed
        return !result.failed
    }

    nonisolated private static func makePreparedLoad(
        document: SubtitleDocument,
        transcript: SubtitleTranscript,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> PreparedSubtitleLoad {
        try throwIfCancelled(isCancelled)
        let effectsResult = try prepareTemporaryEffectsFile(
            from: document.assRenderPlan?.interactiveEffectsOnlyData,
            isCancelled: isCancelled
        )
        if isCancelled() {
            removeTemporaryEffectsFile(effectsResult.url)
            throw CancellationError()
        }
        let store = SubtitleCueStore(document: document)
        if isCancelled() {
            removeTemporaryEffectsFile(effectsResult.url)
            throw CancellationError()
        }
        return PreparedSubtitleLoad(
            document: document,
            store: store,
            transcript: transcript,
            assRenderPlan: document.assRenderPlan,
            assEffectsURL: effectsResult.url,
            assEffectsPreparationFailed: effectsResult.failed
        )
    }

    nonisolated private static func prepareTemporaryEffectsFile(
        from data: Data?,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> (url: URL?, failed: Bool) {
        try throwIfCancelled(isCancelled)
        guard let data else { return (nil, false) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("niratan-ass-effects-\(UUID().uuidString)")
            .appendingPathExtension("ass")
        do {
            try data.write(to: url, options: .atomic)
            if isCancelled() {
                removeTemporaryEffectsFile(url)
                throw CancellationError()
            }
            return (url, false)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (nil, true)
        }
    }

    nonisolated private static func prepareTemporaryEffectsFile(
        from data: Data?
    ) -> (url: URL?, failed: Bool) {
        (try? prepareTemporaryEffectsFile(
            from: data,
            isCancelled: { false }
        )) ?? (nil, true)
    }

    private func replaceTemporaryEffectsFile(with nextURL: URL?) {
        guard assEffectsURL != nextURL else { return }
        Self.removeTemporaryEffectsFile(assEffectsURL)
        assEffectsURL = nextURL
    }

    nonisolated private static func removeTemporaryEffectsFile(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func rebuildTranscript() {
        transcriptGeneration += 1
        transcript = SubtitleTranscript(
            primary: document,
            secondary: nil,
            generation: transcriptGeneration
        )
    }

    nonisolated private static func makeSubtitleCue(
        _ cue: VideoEmbeddedSubtitleCue
    ) -> SubtitleCue {
        SubtitleCue(
            id: cue.id,
            startTime: cue.startTime,
            endTime: cue.endTime,
            text: cue.text
        )
    }

    nonisolated private static func deduplicatedSortedCues(
        _ cues: [SubtitleCue]
    ) -> [SubtitleCue] {
        try! deduplicatedSortedCues(cues, isCancelled: { false })
    }

    nonisolated private static func deduplicatedSortedCues(
        _ cues: [SubtitleCue],
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> [SubtitleCue] {
        var preparedCues: [PreparedCue] = []
        preparedCues.reserveCapacity(cues.count)
        for cue in cues {
            try throwIfCancelled(isCancelled)
            if let preparedCue = PreparedCue(cue) {
                preparedCues.append(preparedCue)
            }
        }
        try throwIfCancelled(isCancelled)
        preparedCues.sort(by: compareCueOrder)
        try throwIfCancelled(isCancelled)
        var seenIDs = Set<String>()
        var seenContent = Set<CueContentKey>()
        var acceptedWholeTextsByTiming: [CueTimingKey: Set<String>] = [:]
        var uniqueCues: [SubtitleCue] = []
        seenIDs.reserveCapacity(preparedCues.count)
        seenContent.reserveCapacity(preparedCues.count)
        acceptedWholeTextsByTiming.reserveCapacity(preparedCues.count)
        uniqueCues.reserveCapacity(preparedCues.count)

        for preparedCue in preparedCues {
            try throwIfCancelled(isCancelled)
            let contentKey = CueContentKey(
                timing: preparedCue.timing,
                text: preparedCue.normalizedText
            )
            if (!preparedCue.trimmedID.isEmpty
                && seenIDs.contains(preparedCue.trimmedID))
                || seenContent.contains(contentKey) {
                continue
            }

            let acceptedWholeTexts = acceptedWholeTextsByTiming[preparedCue.timing] ?? []
            let isMergedDuplicate = !preparedCue.normalizedText.isEmpty
                && preparedCue.normalizedLines.contains { line in
                    line != preparedCue.normalizedText
                        && acceptedWholeTexts.contains(line)
                }
            if isMergedDuplicate {
                continue
            }

            if !preparedCue.trimmedID.isEmpty {
                seenIDs.insert(preparedCue.trimmedID)
            }
            seenContent.insert(contentKey)
            acceptedWholeTextsByTiming[preparedCue.timing, default: []]
                .insert(preparedCue.normalizedText)
            uniqueCues.append(preparedCue.cue)
        }
        try throwIfCancelled(isCancelled)
        return uniqueCues
    }

    nonisolated private static func compareCueOrder(
        _ left: PreparedCue,
        _ right: PreparedCue
    ) -> Bool {
        if left.cue.startTime != right.cue.startTime {
            return left.cue.startTime < right.cue.startTime
        }
        if left.cue.endTime != right.cue.endTime {
            return left.cue.endTime < right.cue.endTime
        }
        if left.normalizedText.count != right.normalizedText.count {
            return left.normalizedText.count < right.normalizedText.count
        }
        return left.cue.text < right.cue.text
    }

    nonisolated private struct CueTimingKey: Hashable {
        let startMilliseconds: Int64
        let endMilliseconds: Int64

        nonisolated init?(_ cue: SubtitleCue) {
            guard let startMilliseconds = VideoSubtitleController.timestampMilliseconds(
                cue.startTime
            ), let endMilliseconds = VideoSubtitleController.timestampMilliseconds(
                cue.endTime
            ) else {
                return nil
            }
            self.startMilliseconds = startMilliseconds
            self.endMilliseconds = endMilliseconds
        }
    }

    nonisolated private struct CueContentKey: Hashable {
        let timing: CueTimingKey
        let text: String
    }

    nonisolated private struct PreparedCue {
        let cue: SubtitleCue
        let trimmedID: String
        let normalizedText: String
        let normalizedLines: Set<String>
        let timing: CueTimingKey

        nonisolated init?(_ cue: SubtitleCue) {
            guard let timing = CueTimingKey(cue) else { return nil }
            self.cue = cue
            trimmedID = cue.id.trimmingCharacters(in: .whitespacesAndNewlines)
            normalizedText = VideoSubtitleController.normalizedText(cue.text)
            normalizedLines = VideoSubtitleController.normalizedLines(cue.text)
            self.timing = timing
        }
    }

    nonisolated private static func normalizedText(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    nonisolated private static func normalizedLines(_ text: String) -> Set<String> {
        Set(
            text
                .split(whereSeparator: \.isNewline)
                .map { normalizedText(String($0)) }
                .filter { !$0.isEmpty }
        )
    }

    nonisolated private static func timestampMilliseconds(
        _ time: TimeInterval
    ) -> Int64? {
        guard time.isFinite, time >= 0 else { return nil }
        let milliseconds = (time * 1_000).rounded()
        guard milliseconds.isFinite,
              milliseconds >= 0,
              milliseconds < Double(Int64.max) else {
            return nil
        }
        return Int64(milliseconds)
    }

    nonisolated private static func throwIfCancelled(
        _ isCancelled: @Sendable () -> Bool
    ) throws {
        if isCancelled() {
            throw CancellationError()
        }
    }

}
