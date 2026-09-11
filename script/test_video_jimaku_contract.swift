import Foundation

private func read(_ path: String) -> String {
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
        fputs("FAIL: could not read \(path)\n", stderr)
        exit(1)
    }
    return source
}

private func require(_ source: String, contains value: String, _ message: String) {
    guard source.contains(value) else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let client = read("Features/Video/Subtitles/JimakuAPIClient.swift")
let credentials = read("Features/Video/Subtitles/JimakuCredentialStore.swift")
let browser = read("Features/Video/Subtitles/JimakuSubtitleBrowserView.swift")
let settings = read("Features/Settings/VideoSettingsView.swift")
let inspector = read("Features/Video/VideoInspectorView.swift")
let player = read("Features/Video/VideoPlayerScreen.swift")
let loader = read("Features/Video/Remote/RemoteSubtitleLoader.swift")
let project = read("Niratan.xcodeproj/project.pbxproj")
let localization = read("Localizable.xcstrings")

require(client, contains: "request.setValue(apiKey, forHTTPHeaderField: \"Authorization\")", "Jimaku API requests should authenticate with the documented header")
require(client, contains: "case \"srt\": .srt", "Jimaku should map SRT into the existing parser")
require(client, contains: "case \"ass\": .ass", "Jimaku should map ASS into the existing parser")
require(client, contains: "case \"ssa\": .ssa", "Jimaku should map SSA into the existing parser")
require(credentials, contains: "kSecClassGenericPassword", "Jimaku API keys should use Keychain generic-password storage")
require(credentials, contains: "moe.shishamo.hoshi.jimaku", "Jimaku should use an isolated Keychain service")
require(settings, contains: "SecureField(\"Enter a new API key\"", "Video Settings should expose Jimaku API-key configuration")
require(browser, contains: "SecureField(", "the Jimaku subtitle sheet should configure its API key in context")
require(browser, contains: "credentialStore.save", "the Jimaku subtitle sheet should persist its API key through Keychain storage")
require(browser, contains: "configurationPanelWidth: CGFloat = 430", "the Jimaku sheet should keep a wider configuration column")
require(browser, contains: "minimumPanelWidth: CGFloat = 1_120", "the Jimaku sheet should present at a larger minimum width")
require(browser, contains: "idealPanelWidth: CGFloat = 1_240", "the Jimaku sheet should prefer a wide desktop layout")
require(browser, contains: "client.searchEntries", "the subtitle inspector should search Jimaku entries")
require(browser, contains: "client.files", "the subtitle inspector should list Jimaku entry files")
require(inspector, contains: "JimakuSubtitleBrowserView(", "the Video subtitle inspector should include Jimaku")
require(inspector, contains: "Get Subtitles (Jimaku)", "the subtitle inspector should expose the Jimaku sheet as an explicit action")
require(player, contains: "private func loadJimakuSubtitle", "Jimaku downloads should enter the player subtitle path")
require(player, contains: "loadPrimarySubtitle(", "Jimaku subtitles should reuse Niratan's primary subtitle parser")
require(player, contains: "CatalogSubtitleStore.archive", "Jimaku downloads should be archived for reuse after the session")
require(player, contains: ".external(path: archivedURL.standardizedFileURL.path)", "Jimaku subtitle selections should be remembered as external files")
require(player, contains: ".externalDisabled(path: catalogSubtitlePath)", "disabling a Jimaku subtitle should preserve its archived file")
require(player, contains: "if case .external(let path) = rememberedSelection", "remembered Jimaku subtitles should be restored when a remote video reopens")
require(loader, contains: "case .ass:", "remote subtitle loading should preserve ASS files")
for path in [
    "Video/Subtitles/JimakuAPIClient.swift",
    "Video/Subtitles/JimakuCredentialStore.swift",
    "Video/Subtitles/JimakuSubtitleBrowserView.swift",
    "Video/Subtitles/CatalogSubtitleStore.swift",
] {
    require(project, contains: path, "Jimaku source should belong to the full Niratan target: \(path)")
}
for key in [
    "Jimaku Subtitles",
    "Add a Jimaku API key in Video Settings to search.",
    "Unable to load the Jimaku subtitle.",
] {
    require(localization, contains: "\"\(key)\"", "Jimaku user-facing copy should be localized: \(key)")
}

print("Video Jimaku contract tests passed")
