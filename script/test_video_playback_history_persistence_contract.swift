import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let store = try source("Features/Video/VideoPlaybackHistoryStore.swift")
let viewModel = try source("Features/Video/VideoPlayerViewModel.swift")

require(
    store.contains("moe.shishamo.hoshi.video.playback-history")
        && store.contains("savePlaybackStateDeferred(")
        && store.contains("VideoPlaybackHistoryStore.persistenceQueue.async")
        && store.contains("video_playback_history.json")
        && store.contains("legacySnapshot(defaults:")
        && !store.contains("defaults.set("),
    "playback progress should migrate once into a dedicated file and persist deferred writes off the main thread"
)

require(
    viewModel.contains("saveCurrentPosition(deferred: true)")
        && viewModel.contains("saveCurrentPosition(deferred: false)")
        && viewModel.contains("historyStore.savePlaybackStateDeferred("),
    "playback tick saves should be deferred while media-switch saves remain synchronous"
)

require(
    store.contains("externalSubtitlePaths")
        && store.contains("externalDisabled")
        && viewModel.contains("rememberedExternalSubtitleURL"),
    "subtitle visibility should be persisted separately from the last external subtitle file"
)

print("Video playback history persistence contract tests passed")
