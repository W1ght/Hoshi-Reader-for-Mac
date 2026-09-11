import Foundation

private func read(_ path: String) -> String {
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
        fputs("FAIL: could not read \(path)\n", stderr)
        exit(1)
    }
    return source
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func require(_ source: String, contains value: String, _ message: String) {
    require(source.contains(value), message)
}

let client = read("Features/Video/Subtitles/AJATTSubtitleCatalogClient.swift")
let browser = read("Features/Video/Subtitles/AJATTSubtitleBrowserView.swift")
let inspector = read("Features/Video/VideoInspectorView.swift")
let player = read("Features/Video/VideoPlayerScreen.swift")
let loader = read("Features/Video/Remote/RemoteSubtitleLoader.swift")
let boundedLoader = read("Features/Video/Remote/BoundedURLSessionData.swift")
let project = read("Niratan.xcodeproj/project.pbxproj")

require(inspector, contains: "AJATTSubtitleBrowserView(", "the Video subtitle inspector should present a native AJATT sheet")
require(inspector, contains: "Get Subtitles (AJATT)", "the subtitle inspector should expose AJATT as an explicit action")
require(!inspector.contains("https://subtitles.ajatt.top/index.html"), "the AJATT action should not fall back to a website link")
require(browser, contains: "client.searchEntries", "the AJATT sheet should search the native catalog client")
require(browser, contains: "client.files", "the AJATT sheet should list files inside the App")
require(browser, contains: ".buttonStyle(.glassProminent)", "AJATT search should use the native Liquid Glass action style")
require(player, contains: "private func loadAJATTSubtitle", "AJATT downloads should enter the player subtitle path")
require(player, contains: "loadPrimarySubtitle(", "AJATT subtitles should reuse Niratan's primary subtitle parser")
require(player, contains: "allowedDownloadHosts: source.allowedDownloadHosts", "AJATT downloads should retain their host policy through loading")
require(player, contains: "maximumResponseSize: source.maximumResponseSize", "AJATT downloads should retain their byte limit through loading")
require(player, contains: "CatalogSubtitleStore.archive", "AJATT downloads should be archived for reuse after the session")
require(player, contains: ".external(path: archivedURL.standardizedFileURL.path)", "AJATT subtitle selections should be remembered as external files")
require(player, contains: ".externalDisabled(path: catalogSubtitlePath)", "disabling an AJATT subtitle should preserve its archived file")
require(player, contains: "if case .external(let path) = rememberedSelection", "remembered AJATT subtitles should be restored when a remote video reopens")
require(client, contains: "https://subtitles.ajatt.top/", "AJATT should use the public HTTPS catalog")
require(client, contains: "raw.githubusercontent.com", "AJATT should accept only the official GitHub mirror host")
require(client, contains: "maximumCatalogResponseSize", "AJATT catalog responses should be bounded")
require(client, contains: "maximumSubtitleFileSize", "AJATT subtitle file metadata should be bounded")
require(client, contains: "nodeLoadExternalEntitiesNever", "AJATT HTML parsing should disable external entities")
require(client, contains: "uniquingKeysWith", "AJATT file parsing should deduplicate repeated format-section rows")
require(loader, contains: "allowedDownloadHosts", "the remote subtitle loader should enforce provider download hosts")
require(loader, contains: "maximumResponseSize", "remote subtitle payloads should be bounded")
require(boundedLoader, contains: "session.bytes(for: request)", "bounded downloads should stream instead of buffering the full response")
require(boundedLoader, contains: "task.cancel()", "bounded downloads should cancel the network task as soon as their limit is exceeded")
require(client, contains: "BoundedURLSessionData.load", "AJATT catalog downloads should use the streaming byte limit")

for path in [
    "Video/Remote/BoundedURLSessionData.swift",
    "Video/Subtitles/AJATTSubtitleCatalogClient.swift",
    "Video/Subtitles/AJATTSubtitleBrowserView.swift",
    "Video/Subtitles/CatalogSubtitleStore.swift",
] {
    require(project, contains: path, "AJATT source should belong to the full Niratan target: \(path)")
}

let localizationData = try Data(contentsOf: URL(fileURLWithPath: "Localizable.xcstrings"))
let localization = try JSONSerialization.jsonObject(with: localizationData) as? [String: Any]
let strings = localization?["strings"] as? [String: Any]
for key in [
    "Get Subtitles (AJATT)",
    "AJATT Japanese Subtitles",
    "Enter a title to search AJATT.",
    "Unable to load the AJATT subtitle.",
] {
    let entry = strings?[key] as? [String: Any]
    let localizations = entry?["localizations"] as? [String: Any]
    require(localizations?["en"] != nil, "AJATT copy should include English: \(key)")
    require(localizations?["zh-Hans"] != nil, "AJATT copy should include Simplified Chinese: \(key)")
}

print("Video AJATT contract tests passed")
