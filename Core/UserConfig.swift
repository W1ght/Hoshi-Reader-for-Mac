//
//  UserConfig.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI
import AppKit

enum DictionaryUpdateInterval: String, CaseIterable, Codable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"

    var timeInterval: TimeInterval {
        switch self {
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        case .monthly: 30 * 24 * 60 * 60
        }
    }
}

enum SyncMode: String, CaseIterable, Codable {
    case auto = "Auto"
    case manual = "Manual"
}

enum AudioPlaybackMode: String, CaseIterable, Codable {
    case interrupt = "interrupt"
    case duck = "duck"
    case mix = "mix"
}

enum CollapseMode: String, CaseIterable, Codable {
    case expandAll = "Expand All"
    case collapseAll = "Collapse All"
    case custom = "Custom"
}

enum Themes: String, CaseIterable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    case sepia = "Sepia"
    case custom = "Custom"

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .sepia: .light
        default: nil
        }
    }
}

enum VideoSubtitleMaskMode: String, CaseIterable, Codable {
    case blur = "Blur"
    case transparent = "Transparent"
}

enum VideoControlBarLayout: String, CaseIterable, Codable {
    case floating
    case compactBottom
}

struct XboxControllerBinding: Codable, Equatable, Identifiable {
    var input: String

    var id: String { input }

    var label: String {
        switch input {
        case "buttonA": "A / Cross / B"
        case "buttonB": "B / Circle / A"
        case "buttonX": "X / Square / Y"
        case "buttonY": "Y / Triangle / X"
        case "dpadUp": "D-Pad ↑"
        case "dpadDown": "D-Pad ↓"
        case "dpadLeft": "D-Pad ←"
        case "dpadRight": "D-Pad →"
        case "leftShoulder": "LB / L1 / L"
        case "rightShoulder": "RB / R1 / R"
        case "leftTrigger": "LT / L2 / ZL"
        case "rightTrigger": "RT / R2 / ZR"
        case "leftThumbstickButton": "L3"
        case "rightThumbstickButton": "R3"
        case "buttonMenu": "Menu / Options / +"
        case "buttonOptions": "View / Share / -"
        case "buttonHome": "Home / PS"
        case "buttonShare": "Share / Create / Capture"
        case "playStationTouchpad": "Touchpad"
        case "xboxPaddle1": "Paddle 1"
        case "xboxPaddle2": "Paddle 2"
        case "xboxPaddle3": "Paddle 3"
        case "xboxPaddle4": "Paddle 4"
        case "leftThumbstickUp": "Left Stick ↑"
        case "leftThumbstickDown": "Left Stick ↓"
        case "leftThumbstickLeft": "Left Stick ←"
        case "leftThumbstickRight": "Left Stick →"
        case "rightThumbstickUp": "Right Stick ↑"
        case "rightThumbstickDown": "Right Stick ↓"
        case "rightThumbstickLeft": "Right Stick ←"
        case "rightThumbstickRight": "Right Stick →"
        default: input
        }
    }

    static let buttonA = XboxControllerBinding(input: "buttonA")
    static let buttonB = XboxControllerBinding(input: "buttonB")
    static let buttonX = XboxControllerBinding(input: "buttonX")
    static let buttonY = XboxControllerBinding(input: "buttonY")
    static let dpadLeft = XboxControllerBinding(input: "dpadLeft")
    static let dpadRight = XboxControllerBinding(input: "dpadRight")
    static let leftShoulder = XboxControllerBinding(input: "leftShoulder")
    static let rightShoulder = XboxControllerBinding(input: "rightShoulder")
}

struct ControllerConfiguration: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var bindings: [String: XboxControllerBinding]

    init(
        version: Int = ControllerConfiguration.currentVersion,
        bindings: [String: XboxControllerBinding] = [:]
    ) {
        self.version = version
        self.bindings = bindings
    }

    static func migrating(
        storedData: Data?,
        legacyBindings: [String: XboxControllerBinding]
    ) -> ControllerConfiguration {
        let decoder = JSONDecoder()
        if var configuration = storedData.flatMap({
            try? decoder.decode(ControllerConfiguration.self, from: $0)
        }) {
            configuration.version = currentVersion
            return configuration
        }

        return ControllerConfiguration(bindings: legacyBindings)
    }
}

@Observable
class UserConfig {
    private static let defaults = UserDefaults.standard

    private static func clampedVideoEqualizerValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -100), 100)
    }

    private static func clampedVideoSubtitleGapFastForwardSpeed(_ value: Double) -> Double {
        guard value.isFinite else { return 2.7 }
        return min(max(value, 1.1), 5.0)
    }

    var bookshelfSortOption: SortOption {
        didSet { Self.defaults.set(bookshelfSortOption.rawValue, forKey: "bookshelfSortOption") }
    }

    var bookshelfShowReading: Bool {
        didSet { Self.defaults.set(bookshelfShowReading, forKey: "bookshelfShowReading") }
    }

    var autoUpdateDictionaries: Bool {
        didSet { Self.defaults.set(autoUpdateDictionaries, forKey: "autoUpdateDictionaries") }
    }

    var dictionaryUpdateInterval: DictionaryUpdateInterval {
        didSet { Self.defaults.set(dictionaryUpdateInterval.rawValue, forKey: "dictionaryUpdateInterval") }
    }

    var dictionaryTabDefault: Bool {
        didSet { Self.defaults.set(dictionaryTabDefault, forKey: "dictionaryTabDefault") }
    }

    var scanNonJapaneseText: Bool {
        didSet { Self.defaults.set(scanNonJapaneseText, forKey: "scanNonJapaneseText") }
    }

    var maxResults: Int {
        didSet { Self.defaults.set(maxResults, forKey: "maxResults") }
    }

    var scanLength: Int {
        didSet { Self.defaults.set(scanLength, forKey: "scanLength") }
    }

    var collapseMode: CollapseMode {
        didSet { Self.defaults.set(collapseMode.rawValue, forKey: "collapseMode") }
    }

    var expandFirstDictionary: Bool {
        didSet { Self.defaults.set(expandFirstDictionary, forKey: "expandFirstDictionary") }
    }

    var twoColumnLayout: Bool {
        didSet { Self.defaults.set(twoColumnLayout, forKey: "twoColumnLayout") }
    }

    var compactGlossaries: Bool {
        didSet { Self.defaults.set(compactGlossaries, forKey: "compactGlossaries") }
    }

    var showExpressionTags: Bool {
        didSet { Self.defaults.set(showExpressionTags, forKey: "showExpressionTags") }
    }

    var harmonicFrequency: Bool {
        didSet { Self.defaults.set(harmonicFrequency, forKey: "harmonicFrequency") }
    }

    var deduplicatePitchAccents: Bool {
        didSet { Self.defaults.set(deduplicatePitchAccents, forKey: "deduplicatePitchAccents") }
    }

    var desktopLookupHoverDelayMs: Int {
        didSet { Self.defaults.set(desktopLookupHoverDelayMs, forKey: "desktopLookupHoverDelayMs") }
    }

    var compactPitchAccents: Bool {
        didSet { Self.defaults.set(compactPitchAccents, forKey: "compactPitchAccents") }
    }

    var enableSync: Bool {
        didSet { Self.defaults.set(enableSync, forKey: "enableSync") }
    }

    var syncMode: SyncMode {
        didSet { Self.defaults.set(syncMode.rawValue, forKey: "syncMode") }
    }

    var enableAutoSync: Bool {
        didSet { Self.defaults.set(enableAutoSync, forKey: "enableAutoSync") }
    }

    var googleClientId: String {
        didSet { Self.defaults.set(googleClientId, forKey: "googleClientId") }
    }

    var syncUploadBooks: Bool {
        didSet { Self.defaults.set(syncUploadBooks, forKey: "syncUploadBooks") }
    }

    var theme: Themes {
        didSet { Self.defaults.set(theme.rawValue, forKey: "theme") }
    }

    var uiTheme: Themes {
        didSet { Self.defaults.set(uiTheme.rawValue, forKey: "uiTheme") }
    }

    var systemLightSepia: Bool {
        didSet { Self.defaults.set(systemLightSepia, forKey: "systemLightSepia") }
    }

    var sepiaInvertInDark: Bool {
        didSet { Self.defaults.set(sepiaInvertInDark, forKey: "sepiaInvertInDark") }
    }

    var customBackgroundColor: Color {
        didSet { Self.saveColor(customBackgroundColor, key: "customBackgroundColor") }
    }

    var customTextColor: Color {
        didSet { Self.saveColor(customTextColor, key: "customTextColor") }
    }

    var customInfoColor: Color {
        didSet { Self.saveColor(customInfoColor, key: "customInfoColor") }
    }

    var verticalWriting: Bool {
        didSet { Self.defaults.set(verticalWriting, forKey: "verticalWriting") }
    }

    var selectedFont: String {
        didSet { Self.defaults.set(selectedFont, forKey: "selectedFont") }
    }

    var fontSize: Int {
        didSet { Self.defaults.set(fontSize, forKey: "fontSize") }
    }

    var readerHideFurigana: Bool {
        didSet { Self.defaults.set(readerHideFurigana, forKey: "readerHideFurigana") }
    }

    var continuousMode: Bool {
        didSet { Self.defaults.set(continuousMode, forKey: "continuousMode") }
    }

    var readerTwoColumnHorizontalPages: Bool {
        didSet { Self.defaults.set(readerTwoColumnHorizontalPages, forKey: "readerTwoColumnHorizontalPages") }
    }

    var readerWheelPageTurnEnabled: Bool {
        didSet { Self.defaults.set(readerWheelPageTurnEnabled, forKey: "readerWheelPageTurnEnabled") }
    }

    var videoAutoPlayNext: Bool {
        didSet { Self.defaults.set(videoAutoPlayNext, forKey: "videoAutoPlayNext") }
    }

    var videoRememberPlaybackPosition: Bool {
        didSet {
            Self.defaults.set(
                videoRememberPlaybackPosition,
                forKey: "videoRememberPlaybackPosition"
            )
        }
    }

    var videoAutoPauseOnLookup: Bool {
        didSet {
            Self.defaults.set(videoAutoPauseOnLookup, forKey: "videoAutoPauseOnLookup")
        }
    }

    var videoSubtitleGapFastForwardEnabled: Bool {
        didSet {
            Self.defaults.set(
                videoSubtitleGapFastForwardEnabled,
                forKey: "videoSubtitleGapFastForwardEnabled"
            )
        }
    }

    var videoSubtitleGapFastForwardSpeed: Double {
        willSet {
            Self.defaults.set(
                Self.clampedVideoSubtitleGapFastForwardSpeed(newValue),
                forKey: "videoSubtitleGapFastForwardSpeed"
            )
        }
    }

    var videoControlBarLayout: VideoControlBarLayout {
        didSet {
            Self.defaults.set(videoControlBarLayout.rawValue, forKey: "videoControlBarLayout")
        }
    }

    var videoSeekInterval: Double {
        willSet {
            let clampedVideoSeekInterval = min(max(newValue, 1), 60)
            Self.defaults.set(clampedVideoSeekInterval, forKey: "videoSeekInterval")
        }
    }

    var videoMiningHistoryLimit: Int {
        willSet {
            Self.defaults.set(
                max(0, newValue),
                forKey: "videoMiningHistoryLimit"
            )
        }
    }

    var videoHardwareDecodingEnabled: Bool {
        didSet {
            Self.defaults.set(
                videoHardwareDecodingEnabled,
                forKey: "videoHardwareDecodingEnabled"
            )
        }
    }

    var videoDeinterlacingEnabled: Bool {
        didSet {
            Self.defaults.set(
                videoDeinterlacingEnabled,
                forKey: "videoDeinterlacingEnabled"
            )
        }
    }

    var videoHDREnhancementEnabled: Bool {
        didSet {
            Self.defaults.set(
                videoHDREnhancementEnabled,
                forKey: "videoHDREnhancementEnabled"
            )
        }
    }

    var videoShaderPreset: VideoShaderPreset {
        didSet {
            Self.defaults.set(videoShaderPreset.rawValue, forKey: "videoShaderPreset")
        }
    }

    var videoBrightness: Double {
        willSet {
            Self.defaults.set(
                Self.clampedVideoEqualizerValue(newValue),
                forKey: "videoBrightness"
            )
        }
    }

    var videoContrast: Double {
        willSet {
            Self.defaults.set(
                Self.clampedVideoEqualizerValue(newValue),
                forKey: "videoContrast"
            )
        }
    }

    var videoSaturation: Double {
        willSet {
            Self.defaults.set(
                Self.clampedVideoEqualizerValue(newValue),
                forKey: "videoSaturation"
            )
        }
    }

    var videoGamma: Double {
        willSet {
            Self.defaults.set(
                Self.clampedVideoEqualizerValue(newValue),
                forKey: "videoGamma"
            )
        }
    }

    var videoHue: Double {
        willSet {
            Self.defaults.set(
                Self.clampedVideoEqualizerValue(newValue),
                forKey: "videoHue"
            )
        }
    }

    var videoSubtitleFontFamily: String {
        willSet {
            let trimmedVideoSubtitleFontFamily = newValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Self.defaults.set(trimmedVideoSubtitleFontFamily, forKey: "videoSubtitleFontFamily")
        }
    }

    var videoRespectASSStyle: Bool {
        willSet { Self.defaults.set(newValue, forKey: "videoRespectASSStyle") }
    }

    var videoSubtitleFontSize: Double {
        willSet {
            let clampedVideoSubtitleFontSize = min(max(newValue, 12), 72)
            Self.defaults.set(clampedVideoSubtitleFontSize, forKey: "videoSubtitleFontSize")
        }
    }

    var videoSubtitleFontWeight: Int {
        willSet {
            let clampedVideoSubtitleFontWeight = min(max(newValue, 100), 900)
            Self.defaults.set(clampedVideoSubtitleFontWeight, forKey: "videoSubtitleFontWeight")
        }
    }

    var videoSubtitleEdgeStyle: VideoSubtitleEdgeStyle {
        didSet {
            Self.defaults.set(videoSubtitleEdgeStyle.rawValue, forKey: "videoSubtitleEdgeStyle")
        }
    }

    var videoSubtitleEdgeStrength: Double {
        didSet {
            let normalized = VideoSubtitleEdgePreferenceResolver.normalizedStrength(
                videoSubtitleEdgeStrength
            )
            guard videoSubtitleEdgeStrength == normalized else {
                videoSubtitleEdgeStrength = normalized
                return
            }
            Self.defaults.set(normalized, forKey: "videoSubtitleEdgeStrength")
            Self.defaults.set(normalized * 10, forKey: "videoSubtitleShadowRadius")
        }
    }

    var videoSubtitleShadowRadius: Double {
        get { videoSubtitleEdgeStrength * 10 }
        set {
            videoSubtitleEdgeStyle = .softShadow
            videoSubtitleEdgeStrength = newValue / 10
        }
    }

    var videoSubtitleBackgroundOpacity: Double {
        willSet {
            let clampedVideoSubtitleBackgroundOpacity = min(max(newValue, 0), 1)
            Self.defaults.set(clampedVideoSubtitleBackgroundOpacity, forKey: "videoSubtitleBackgroundOpacity")
        }
    }

    var videoSubtitleBackgroundDisabled: Bool {
        didSet {
            Self.defaults.set(
                videoSubtitleBackgroundDisabled,
                forKey: "videoSubtitleBackgroundDisabled"
            )
        }
    }

    var videoSubtitleVerticalPosition: Double {
        didSet {
            let normalized = VideoSubtitlePositionPolicy.normalized(videoSubtitleVerticalPosition)
            guard normalized == videoSubtitleVerticalPosition else {
                videoSubtitleVerticalPosition = normalized
                return
            }
            Self.defaults.set(
                normalized,
                forKey: "videoSubtitleVerticalPositionFraction"
            )
        }
    }

    var videoSubtitleColor: Color {
        didSet { Self.saveColor(videoSubtitleColor, key: "videoSubtitleColor") }
    }

    var videoSubtitleLookupHighlightColor: Color {
        didSet { Self.saveColor(videoSubtitleLookupHighlightColor, key: "videoSubtitleLookupHighlightColor") }
    }

    var videoSubtitleLookupHighlightTextColor: Color {
        didSet { Self.saveColor(videoSubtitleLookupHighlightTextColor, key: "videoSubtitleLookupHighlightTextColor") }
    }

    var videoSubtitleMaskEnabled: Bool {
        didSet { Self.defaults.set(videoSubtitleMaskEnabled, forKey: "videoSubtitleMaskEnabled") }
    }

    var videoSubtitleMaskMode: VideoSubtitleMaskMode {
        didSet { Self.defaults.set(videoSubtitleMaskMode.rawValue, forKey: "videoSubtitleMaskMode") }
    }

    var videoSubtitleMaskBlurRadius: Double {
        willSet {
            let clampedVideoSubtitleMaskBlurRadius = min(max(newValue, 0), 20)
            Self.defaults.set(clampedVideoSubtitleMaskBlurRadius, forKey: "videoSubtitleMaskBlurRadius")
        }
    }

    var videoSubtitleMaskHiddenOpacity: Double {
        willSet {
            let clampedVideoSubtitleMaskHiddenOpacity = min(max(newValue, 0), 1)
            Self.defaults.set(clampedVideoSubtitleMaskHiddenOpacity, forKey: "videoSubtitleMaskHiddenOpacity")
        }
    }

    var chapterSwipeDistance: Int {
        didSet { Self.defaults.set(chapterSwipeDistance, forKey: "chapterSwipeDistance") }
    }

    var horizontalPadding: Int {
        didSet { Self.defaults.set(horizontalPadding, forKey: "layoutHorizontalPadding") }
    }

    var verticalPadding: Int {
        didSet { Self.defaults.set(verticalPadding, forKey: "layoutVerticalPadding") }
    }

    var avoidPageBreak: Bool {
        didSet { Self.defaults.set(avoidPageBreak, forKey: "avoidPageBreak") }
    }

    var justifyText: Bool {
        didSet { Self.defaults.set(justifyText, forKey: "justifyText") }
    }

    var blurImages: Bool {
        didSet { Self.defaults.set(blurImages, forKey: "blurImages") }
    }

    var layoutAdvanced: Bool {
        didSet { Self.defaults.set(layoutAdvanced, forKey: "layoutAdvanced") }
    }

    var lineHeight: Double {
        didSet { Self.defaults.set(lineHeight, forKey: "lineHeight") }
    }

    var characterSpacing: Double {
        didSet { Self.defaults.set(characterSpacing, forKey: "characterSpacing") }
    }

    var paragraphSpacing: Double {
        didSet { Self.defaults.set(paragraphSpacing, forKey: "paragraphSpacing") }
    }

    var readerShowTitle: Bool {
        didSet { Self.defaults.set(readerShowTitle, forKey: "readerShowTitle") }
    }

    var readerShowCharacters: Bool {
        didSet { Self.defaults.set(readerShowCharacters, forKey: "readerShowCharacters") }
    }

    var readerShowPercentage: Bool {
        didSet { Self.defaults.set(readerShowPercentage, forKey: "readerShowPercentage") }
    }

    var readerShowProgressTop: Bool {
        didSet { Self.defaults.set(readerShowProgressTop, forKey: "readerShowProgressTop") }
    }

    var readerShowStatisticsToggle: Bool {
        didSet { Self.defaults.set(readerShowStatisticsToggle, forKey: "readerShowStatisticsToggle") }
    }

    var readerShowReadingSpeed: Bool {
        didSet { Self.defaults.set(readerShowReadingSpeed, forKey: "readerShowReadingSpeed") }
    }

    var readerShowReadingTime: Bool {
        didSet { Self.defaults.set(readerShowReadingTime, forKey: "readerShowReadingTime") }
    }

    var readerShowSasayakiToggle: Bool {
        didSet { Self.defaults.set(readerShowSasayakiToggle, forKey: "readerShowSasayakiToggle") }
    }

    private var shortcutConfiguration: ShortcutConfiguration {
        didSet { Self.saveShortcutConfiguration(shortcutConfiguration) }
    }

    private var controllerConfiguration: ControllerConfiguration {
        didSet { Self.saveControllerConfiguration(controllerConfiguration) }
    }

    var crossAppSelectionLookupEnabled: Bool {
        didSet { Self.defaults.set(crossAppSelectionLookupEnabled, forKey: "crossAppSelectionLookupEnabled") }
    }

    var readerPreviousPageShortcut: ReaderKeyboardShortcut {
        get { shortcutBinding(for: ReaderShortcutActions.previousPage) }
        set { setShortcutBinding(newValue, for: ReaderShortcutActions.previousPage) }
    }

    var readerNextPageShortcut: ReaderKeyboardShortcut {
        get { shortcutBinding(for: ReaderShortcutActions.nextPage) }
        set { setShortcutBinding(newValue, for: ReaderShortcutActions.nextPage) }
    }

    var sasayakiPreviousCueShortcut: ReaderKeyboardShortcut {
        get { shortcutBinding(for: SasayakiShortcutActions.previousCue) }
        set { setShortcutBinding(newValue, for: SasayakiShortcutActions.previousCue) }
    }

    var sasayakiPlayPauseShortcut: ReaderKeyboardShortcut {
        get { shortcutBinding(for: SasayakiShortcutActions.playPause) }
        set { setShortcutBinding(newValue, for: SasayakiShortcutActions.playPause) }
    }

    var sasayakiNextCueShortcut: ReaderKeyboardShortcut {
        get { shortcutBinding(for: SasayakiShortcutActions.nextCue) }
        set { setShortcutBinding(newValue, for: SasayakiShortcutActions.nextCue) }
    }

    var sasayakiReplayCueShortcut: ReaderKeyboardShortcut {
        get { shortcutBinding(for: SasayakiShortcutActions.replayCue) }
        set { setShortcutBinding(newValue, for: SasayakiShortcutActions.replayCue) }
    }

    var sasayakiJumpCueShortcut: ReaderKeyboardShortcut {
        get { shortcutBinding(for: SasayakiShortcutActions.jumpCue) }
        set { setShortcutBinding(newValue, for: SasayakiShortcutActions.jumpCue) }
    }

    var dictionaryPreviousEntryShortcut: ReaderKeyboardShortcut {
        get { shortcutBinding(for: DictionaryShortcutActions.previousEntry) }
        set { setShortcutBinding(newValue, for: DictionaryShortcutActions.previousEntry) }
    }

    var dictionaryNextEntryShortcut: ReaderKeyboardShortcut {
        get { shortcutBinding(for: DictionaryShortcutActions.nextEntry) }
        set { setShortcutBinding(newValue, for: DictionaryShortcutActions.nextEntry) }
    }

    var dictionaryEntryJumpCount: Int {
        didSet { Self.defaults.set(dictionaryEntryJumpCount, forKey: "dictionaryEntryJumpCount") }
    }

    var readerPreviousPageControllerBinding: XboxControllerBinding {
        get { controllerBinding(for: ReaderShortcutActions.previousPage) ?? .dpadLeft }
        set { setControllerBinding(newValue, for: ReaderShortcutActions.previousPage) }
    }

    var readerNextPageControllerBinding: XboxControllerBinding {
        get { controllerBinding(for: ReaderShortcutActions.nextPage) ?? .dpadRight }
        set { setControllerBinding(newValue, for: ReaderShortcutActions.nextPage) }
    }

    var sasayakiPreviousCueControllerBinding: XboxControllerBinding {
        get { controllerBinding(for: SasayakiShortcutActions.previousCue) ?? .leftShoulder }
        set { setControllerBinding(newValue, for: SasayakiShortcutActions.previousCue) }
    }

    var sasayakiPlayPauseControllerBinding: XboxControllerBinding {
        get { controllerBinding(for: SasayakiShortcutActions.playPause) ?? .buttonA }
        set { setControllerBinding(newValue, for: SasayakiShortcutActions.playPause) }
    }

    var sasayakiNextCueControllerBinding: XboxControllerBinding {
        get { controllerBinding(for: SasayakiShortcutActions.nextCue) ?? .rightShoulder }
        set { setControllerBinding(newValue, for: SasayakiShortcutActions.nextCue) }
    }

    var sasayakiReplayCueControllerBinding: XboxControllerBinding {
        get { controllerBinding(for: SasayakiShortcutActions.replayCue) ?? .buttonX }
        set { setControllerBinding(newValue, for: SasayakiShortcutActions.replayCue) }
    }

    var sasayakiJumpCueControllerBinding: XboxControllerBinding {
        get { controllerBinding(for: SasayakiShortcutActions.jumpCue) ?? .buttonB }
        set { setControllerBinding(newValue, for: SasayakiShortcutActions.jumpCue) }
    }

    var statisticsToggleControllerBinding: XboxControllerBinding {
        get { controllerBinding(for: ReaderShortcutActions.toggleStatistics) ?? .buttonY }
        set { setControllerBinding(newValue, for: ReaderShortcutActions.toggleStatistics) }
    }

    var popupWidth: Int {
        didSet { Self.defaults.set(popupWidth, forKey: "popupWidth") }
    }

    var popupHeight: Int {
        didSet { Self.defaults.set(popupHeight, forKey: "popupHeight") }
    }
    var popupScale: Double {
        didSet { Self.defaults.set(popupScale, forKey: "popupScale") }
    }

    var popupActionBar: Bool {
        didSet { Self.defaults.set(popupActionBar, forKey: "popupActionBar") }
    }

    var popupDisableTransparency: Bool {
        didSet { Self.defaults.set(popupDisableTransparency, forKey: "popupDisableTransparency") }
    }

    var popupFullWidth: Bool {
        didSet { Self.defaults.set(popupFullWidth, forKey: "popupFullWidth") }
    }

    var popupSwipeToDismiss: Bool {
        didSet { Self.defaults.set(popupSwipeToDismiss, forKey: "popupSwipeToDismiss") }
    }

    var popupSwipeThreshold: Int {
        didSet { Self.defaults.set(popupSwipeThreshold, forKey: "popupSwipeThreshold") }
    }

    var audioSources: [AudioSource] {
        didSet {
            if let data = try? JSONEncoder().encode(audioSources) {
                Self.defaults.set(data, forKey: "audioSources")
            }
        }
    }

    var enableLocalAudio: Bool {
        didSet {
            Self.defaults.set(enableLocalAudio, forKey: "enableLocalAudio")
            syncLocalAudioSource()
        }
    }

    var audioEnableAutoplay: Bool {
        didSet { Self.defaults.set(audioEnableAutoplay, forKey: "audioEnableAutoplay") }
    }

    var audioPlaybackMode: AudioPlaybackMode {
        didSet { Self.defaults.set(audioPlaybackMode.rawValue, forKey: "audioPlaybackMode") }
    }

    var enabledAudioSources: [String] {
        audioSources.filter { $0.isEnabled }.map { $0.url }
    }

    static let localAudioSource = AudioSource(
        name: "Local",
        url: LocalAudioEndpoint.url,
        isEnabled: true
    )

    private static let legacyLocalAudioURLs = [
        "http://localhost:8765/localaudio/get/?term={term}&reading={reading}"
    ]

    static let defaultAudioSource = AudioSource(
        name: "Default",
        url: "https://hoshi-reader.manhhaoo-do.workers.dev/?term={term}&reading={reading}",
        isEnabled: true,
        isDefault: true
    )

    var customCSS: String {
        didSet { Self.defaults.set(customCSS, forKey: "customCSS") }
    }

    var enableStatistics: Bool {
        didSet { Self.defaults.set(enableStatistics, forKey: "enableStatistics") }
    }

    var statisticsEnableSync: Bool {
        didSet { Self.defaults.set(statisticsEnableSync, forKey: "statisticsEnableSync") }
    }

    var statisticsSyncMode: StatisticsSyncMode {
        didSet { Self.defaults.set(statisticsSyncMode.rawValue, forKey: "statisticsSyncMode") }
    }

    var statisticsAutostartMode: StatisticsAutostartMode {
        didSet { Self.defaults.set(statisticsAutostartMode.rawValue, forKey: "statisticsAutostartMode") }
    }

    var statisticsResetTime: Int {
        didSet {
            let normalized = StatisticsDayBoundary.normalizedResetMinutes(statisticsResetTime)
            if statisticsResetTime != normalized {
                statisticsResetTime = normalized
            }
            StatisticsResetTimePreference.save(normalized, to: Self.defaults)
        }
    }

    var dailyStatisticsTargetType: DailyTargetType {
        didSet { Self.defaults.set(dailyStatisticsTargetType.rawValue, forKey: "dailyStatisticsTargetType") }
    }

    var dailyStatisticsCharacterTarget: Int {
        didSet { Self.defaults.set(dailyStatisticsCharacterTarget, forKey: "dailyStatisticsCharacterTarget") }
    }

    var dailyStatisticsDurationTargetMinutes: Int {
        didSet { Self.defaults.set(dailyStatisticsDurationTargetMinutes, forKey: "dailyStatisticsDurationTargetMinutes") }
    }

    var weeklyStatisticsTargetDays: Int {
        didSet { Self.defaults.set(weeklyStatisticsTargetDays, forKey: "weeklyStatisticsTargetDays") }
    }

    var enableSasayaki: Bool {
        didSet { Self.defaults.set(enableSasayaki, forKey: "enableSasayaki") }
    }

    var sasayakiAutoScroll: Bool {
        didSet { Self.defaults.set(sasayakiAutoScroll, forKey: "sasayakiAutoScroll") }
    }

    var sasayakiAutoPause: Bool {
        didSet { Self.defaults.set(sasayakiAutoPause, forKey: "sasayakiAutoPause") }
    }

    var sasayakiSkipControls: Bool {
        didSet { Self.defaults.set(sasayakiSkipControls, forKey: "sasayakiSkipControls") }
    }

    var sasayakiEnableSync: Bool {
        didSet { Self.defaults.set(sasayakiEnableSync, forKey: "sasayakiEnableSync") }
    }

    var sasayakiTextColor: Color {
        didSet { Self.saveColor(sasayakiTextColor, key: "sasayakiTextColor") }
    }

    var sasayakiBackgroundColor: Color {
        didSet { Self.saveColor(sasayakiBackgroundColor, key: "sasayakiBackgroundColor") }
    }

    var sasayakiDarkTextColor: Color {
        didSet { Self.saveColor(sasayakiDarkTextColor, key: "sasayakiDarkTextColor") }
    }

    var sasayakiDarkBackgroundColor: Color {
        didSet { Self.saveColor(sasayakiDarkBackgroundColor, key: "sasayakiDarkBackgroundColor") }
    }

    init() {
        let defaults = Self.defaults
        self.shortcutConfiguration = Self.loadShortcutConfiguration()
        self.controllerConfiguration = Self.loadControllerConfiguration()
        self.crossAppSelectionLookupEnabled = defaults.object(forKey: "crossAppSelectionLookupEnabled") as? Bool ?? false

        self.bookshelfSortOption = defaults.string(forKey: "bookshelfSortOption")
            .flatMap(SortOption.init) ?? .recent
        self.bookshelfShowReading = defaults.object(forKey: "bookshelfShowReading") as? Bool ?? false

        self.autoUpdateDictionaries = defaults.object(forKey: "autoUpdateDictionaries") as? Bool ?? true
        self.dictionaryUpdateInterval = defaults.string(forKey: "dictionaryUpdateInterval")
            .flatMap(DictionaryUpdateInterval.init) ?? .weekly
        self.dictionaryTabDefault = defaults.object(forKey: "dictionaryTabDefault") as? Bool ?? false
        self.scanNonJapaneseText = defaults.object(forKey: "scanNonJapaneseText") as? Bool ?? true
        self.maxResults = defaults.object(forKey: "maxResults") as? Int ?? 16
        self.scanLength = defaults.object(forKey: "scanLength") as? Int ?? 16
        let legacyCollapseDictionaries = defaults.object(forKey: "collapseDictionaries") as? Bool ?? false
        self.collapseMode = defaults.string(forKey: "collapseMode")
            .flatMap(CollapseMode.init) ?? (legacyCollapseDictionaries ? .collapseAll : .expandAll)
        self.expandFirstDictionary = defaults.object(forKey: "expandFirstDictionary") as? Bool ?? false
        self.twoColumnLayout = defaults.object(forKey: "twoColumnLayout") as? Bool ?? false
        self.compactGlossaries = defaults.object(forKey: "compactGlossaries") as? Bool ?? true
        self.showExpressionTags = defaults.object(forKey: "showExpressionTags") as? Bool ?? false
        self.harmonicFrequency = defaults.object(forKey: "harmonicFrequency") as? Bool ?? false
        self.deduplicatePitchAccents = defaults.object(forKey: "deduplicatePitchAccents") as? Bool ?? false
        self.desktopLookupHoverDelayMs = defaults.object(forKey: "desktopLookupHoverDelayMs") as? Int ?? 45
        self.compactPitchAccents = defaults.object(forKey: "compactPitchAccents") as? Bool ?? true

        self.enableSync = defaults.object(forKey: "enableSync") as? Bool ?? false
        self.syncMode = defaults.string(forKey: "syncMode")
            .flatMap(SyncMode.init) ?? .auto
        self.enableAutoSync = defaults.object(forKey: "enableAutoSync") as? Bool ?? false
        self.googleClientId = defaults.object(forKey: "googleClientId") as? String ?? ""
        self.syncUploadBooks = defaults.object(forKey: "syncUploadBooks") as? Bool ?? true

        self.theme = defaults.string(forKey: "theme")
            .flatMap(Themes.init) ?? .system
        self.uiTheme = defaults.string(forKey: "uiTheme")
            .flatMap(Themes.init) ?? .system
        self.systemLightSepia = defaults.object(forKey: "systemLightSepia") as? Bool ?? false
        self.sepiaInvertInDark = defaults.object(forKey: "sepiaInvertInDark") as? Bool ?? false
        self.customBackgroundColor = UserConfig.loadColor(key: "customBackgroundColor") ?? Color(.sRGB, red: 1, green: 1, blue: 1)
        self.customTextColor = UserConfig.loadColor(key: "customTextColor") ?? Color(.sRGB, red: 0, green: 0, blue: 0)
        self.customInfoColor = UserConfig.loadColor(key: "customInfoColor") ?? Color(.sRGB, red: 0.6, green: 0.6, blue: 0.6)

        self.verticalWriting = defaults.object(forKey: "verticalWriting") as? Bool ?? true
        self.selectedFont = defaults.string(forKey: "selectedFont") ?? "Hiragino Mincho ProN"
        self.fontSize = defaults.object(forKey: "fontSize") as? Int ?? 22
        self.readerHideFurigana = defaults.object(forKey: "readerHideFurigana") as? Bool ?? false

        self.continuousMode = defaults.object(forKey: "continuousMode") as? Bool ?? false
        self.readerTwoColumnHorizontalPages = defaults.object(forKey: "readerTwoColumnHorizontalPages") as? Bool ?? false
        self.readerWheelPageTurnEnabled = defaults.object(forKey: "readerWheelPageTurnEnabled") as? Bool ?? true
        self.videoAutoPlayNext = defaults.object(forKey: "videoAutoPlayNext") as? Bool ?? true
        self.videoRememberPlaybackPosition =
            defaults.object(forKey: "videoRememberPlaybackPosition") as? Bool ?? true
        self.videoAutoPauseOnLookup =
            defaults.object(forKey: "videoAutoPauseOnLookup") as? Bool ?? true
        self.videoSubtitleGapFastForwardEnabled =
            defaults.object(forKey: "videoSubtitleGapFastForwardEnabled") as? Bool ?? false
        self.videoSubtitleGapFastForwardSpeed = Self.clampedVideoSubtitleGapFastForwardSpeed(
            defaults.object(forKey: "videoSubtitleGapFastForwardSpeed") as? Double ?? 2.7
        )
        self.videoControlBarLayout = defaults.string(forKey: "videoControlBarLayout")
            .flatMap(VideoControlBarLayout.init) ?? .floating
        self.videoSeekInterval = min(
            max(defaults.object(forKey: "videoSeekInterval") as? Double ?? 5, 1),
            60
        )
        self.videoMiningHistoryLimit = max(
            defaults.object(forKey: "videoMiningHistoryLimit") as? Int ?? 25,
            0
        )
        self.videoHardwareDecodingEnabled =
            defaults.object(forKey: "videoHardwareDecodingEnabled") as? Bool ?? true
        self.videoDeinterlacingEnabled =
            defaults.object(forKey: "videoDeinterlacingEnabled") as? Bool ?? false
        self.videoHDREnhancementEnabled =
            defaults.object(forKey: "videoHDREnhancementEnabled") as? Bool ?? false
        self.videoShaderPreset = defaults.string(forKey: "videoShaderPreset")
            .flatMap(VideoShaderPreset.init) ?? .off
        self.videoBrightness = Self.clampedVideoEqualizerValue(
            defaults.object(forKey: "videoBrightness") as? Double ?? 0
        )
        self.videoContrast = Self.clampedVideoEqualizerValue(
            defaults.object(forKey: "videoContrast") as? Double ?? 0
        )
        self.videoSaturation = Self.clampedVideoEqualizerValue(
            defaults.object(forKey: "videoSaturation") as? Double ?? 0
        )
        self.videoGamma = Self.clampedVideoEqualizerValue(
            defaults.object(forKey: "videoGamma") as? Double ?? 0
        )
        self.videoHue = Self.clampedVideoEqualizerValue(
            defaults.object(forKey: "videoHue") as? Double ?? 0
        )
        self.videoSubtitleFontFamily =
            defaults.string(forKey: "videoSubtitleFontFamily") ?? ""
        self.videoRespectASSStyle = defaults.bool(forKey: "videoRespectASSStyle")
        self.videoSubtitleFontSize = min(
            max(defaults.object(forKey: "videoSubtitleFontSize") as? Double ?? 36, 12),
            72
        )
        self.videoSubtitleFontWeight = min(
            max(defaults.object(forKey: "videoSubtitleFontWeight") as? Int ?? 700, 100),
            900
        )
        let subtitleEdgePreference = VideoSubtitleEdgePreferenceResolver.resolve(
            edgeStyleRawValue: defaults.string(forKey: "videoSubtitleEdgeStyle"),
            edgeStrength: defaults.object(forKey: "videoSubtitleEdgeStrength") as? Double,
            legacyShadowRadius: defaults.object(forKey: "videoSubtitleShadowRadius") as? Double
        )
        self.videoSubtitleEdgeStyle = subtitleEdgePreference.style
        self.videoSubtitleEdgeStrength = subtitleEdgePreference.strength
        self.videoSubtitleBackgroundOpacity = min(
            max(defaults.object(forKey: "videoSubtitleBackgroundOpacity") as? Double ?? 0, 0),
            1
        )
        self.videoSubtitleBackgroundDisabled =
            defaults.object(forKey: "videoSubtitleBackgroundDisabled") as? Bool ?? true
        let storedSubtitlePosition = defaults.object(
            forKey: "videoSubtitleVerticalPositionFraction"
        ) as? Double
        let resolvedSubtitlePosition = storedSubtitlePosition.map {
            VideoSubtitlePositionPolicy.normalized($0)
        } ?? VideoSubtitlePositionPolicy.migratedLegacyPosition(
            defaults.object(forKey: "videoSubtitleVerticalPosition") as? Double
        )
        self.videoSubtitleVerticalPosition = resolvedSubtitlePosition
        defaults.set(
            resolvedSubtitlePosition,
            forKey: "videoSubtitleVerticalPositionFraction"
        )
        let defaultVideoSubtitleColor = UserConfig.loadColor(key: "videoSubtitleColor") ?? Color.white
        self.videoSubtitleColor = defaultVideoSubtitleColor
        self.videoSubtitleLookupHighlightColor = UserConfig.loadColor(
            key: "videoSubtitleLookupHighlightColor"
        ) ?? Color(.sRGB, red: 181.0 / 255.0, green: 193.0 / 255.0, blue: 203.0 / 255.0, opacity: 62.0 / 255.0)
        self.videoSubtitleLookupHighlightTextColor = UserConfig.loadColor(
            key: "videoSubtitleLookupHighlightTextColor"
        ) ?? defaultVideoSubtitleColor
        self.videoSubtitleMaskEnabled =
            defaults.object(forKey: "videoSubtitleMaskEnabled") as? Bool ?? false
        self.videoSubtitleMaskMode = defaults.string(forKey: "videoSubtitleMaskMode")
            .flatMap(VideoSubtitleMaskMode.init) ?? .blur
        self.videoSubtitleMaskBlurRadius = min(
            max(defaults.object(forKey: "videoSubtitleMaskBlurRadius") as? Double ?? 10, 0),
            20
        )
        self.videoSubtitleMaskHiddenOpacity = min(
            max(defaults.object(forKey: "videoSubtitleMaskHiddenOpacity") as? Double ?? 0, 0),
            1
        )
        self.chapterSwipeDistance = defaults.object(forKey: "chapterSwipeDistance") as? Int ?? 20
        self.horizontalPadding = defaults.object(forKey: "layoutHorizontalPadding") as? Int ?? 5
        self.verticalPadding = defaults.object(forKey: "layoutVerticalPadding") as? Int ?? 0
        self.avoidPageBreak = defaults.object(forKey: "avoidPageBreak") as? Bool ?? false
        self.justifyText = defaults.object(forKey: "justifyText") as? Bool ?? false
        self.blurImages = defaults.object(forKey: "blurImages") as? Bool ?? false
        self.layoutAdvanced = defaults.object(forKey: "layoutAdvanced") as? Bool ?? false
        self.lineHeight = defaults.object(forKey: "lineHeight") as? Double ?? 1.65
        self.characterSpacing = defaults.object(forKey: "characterSpacing") as? Double ?? 0
        self.paragraphSpacing = defaults.object(forKey: "paragraphSpacing") as? Double ?? 0

        self.readerShowTitle = defaults.object(forKey: "readerShowTitle") as? Bool ?? true
        self.readerShowCharacters = defaults.object(forKey: "readerShowCharacters") as? Bool ?? true
        self.readerShowPercentage = defaults.object(forKey: "readerShowPercentage") as? Bool ?? true
        self.readerShowProgressTop = defaults.object(forKey: "readerShowProgressTop") as? Bool ?? true
        self.readerShowStatisticsToggle = defaults.object(forKey: "readerShowStatisticsToggle") as? Bool ?? false
        self.readerShowReadingSpeed = defaults.object(forKey: "readerShowReadingSpeed") as? Bool ?? false
        self.readerShowReadingTime = defaults.object(forKey: "readerShowReadingTime") as? Bool ?? false
        self.readerShowSasayakiToggle = defaults.object(forKey: "readerShowSasayakiToggle") as? Bool ?? false
        self.dictionaryEntryJumpCount = min(max(defaults.object(forKey: "dictionaryEntryJumpCount") as? Int ?? 1, 1), 10)
        self.popupWidth = defaults.object(forKey: "popupWidth") as? Int ?? 320
        self.popupHeight = defaults.object(forKey: "popupHeight") as? Int ?? 250
        self.popupScale = defaults.object(forKey: "popupScale") as? Double ?? 1.0
        self.popupActionBar = defaults.object(forKey: "popupActionBar") as? Bool ?? false
        self.popupDisableTransparency = defaults.object(forKey: "popupDisableTransparency") as? Bool ?? false
        self.popupFullWidth = defaults.object(forKey: "popupFullWidth") as? Bool ?? false
        self.popupSwipeToDismiss = defaults.object(forKey: "popupSwipeToDismiss") as? Bool ?? false
        self.popupSwipeThreshold = defaults.object(forKey: "popupSwipeThreshold") as? Int ?? 40

        if let data = defaults.data(forKey: "audioSources"),
           let sources = try? JSONDecoder().decode([AudioSource].self, from: data) {
            self.audioSources = sources
        } else {
            self.audioSources = [UserConfig.defaultAudioSource]
        }
        self.enableLocalAudio = defaults.object(forKey: "enableLocalAudio") as? Bool ?? false
        self.audioEnableAutoplay = defaults.object(forKey: "audioEnableAutoplay") as? Bool ?? false
        self.audioPlaybackMode = defaults.string(forKey: "audioPlaybackMode")
            .flatMap(AudioPlaybackMode.init) ?? .interrupt
        self.customCSS = defaults.string(forKey: "customCSS") ?? ""

        self.enableStatistics = defaults.object(forKey: "enableStatistics") as? Bool ?? false
        self.statisticsEnableSync = defaults.object(forKey: "statisticsEnableSync") as? Bool ?? false
        self.statisticsSyncMode = defaults.string(forKey: "statisticsSyncMode")
            .flatMap(StatisticsSyncMode.init) ?? .merge
        self.statisticsAutostartMode = defaults.string(forKey: "statisticsAutostartMode")
            .flatMap(StatisticsAutostartMode.init) ?? .off
        self.statisticsResetTime = StatisticsResetTimePreference.load(from: defaults)
        self.dailyStatisticsTargetType = defaults.string(forKey: "dailyStatisticsTargetType")
            .flatMap(DailyTargetType.init) ?? .characters
        self.dailyStatisticsCharacterTarget = StatisticsTargetSettings
            .snapCharacterTarget(defaults.object(forKey: "dailyStatisticsCharacterTarget") as? Int ?? 5_000)
        self.dailyStatisticsDurationTargetMinutes = StatisticsTargetSettings
            .snapDurationTarget(defaults.object(forKey: "dailyStatisticsDurationTargetMinutes") as? Int ?? 30)
        self.weeklyStatisticsTargetDays = min(max(defaults.object(forKey: "weeklyStatisticsTargetDays") as? Int ?? 4, 1), 7)

        self.enableSasayaki = defaults.object(forKey: "enableSasayaki") as? Bool ?? false
        self.sasayakiAutoScroll = defaults.object(forKey: "sasayakiAutoScroll") as? Bool ?? true
        self.sasayakiAutoPause = defaults.object(forKey: "sasayakiAutoPause") as? Bool ?? true
        self.sasayakiSkipControls = defaults.object(forKey: "sasayakiSkipControls") as? Bool ?? false
        self.sasayakiEnableSync = defaults.object(forKey: "sasayakiEnableSync") as? Bool ?? false
        self.sasayakiTextColor = UserConfig.loadColor(key: "sasayakiTextColor") ?? Color(.sRGB, red: 0, green: 0, blue: 0)
        self.sasayakiBackgroundColor = UserConfig.loadColor(key: "sasayakiBackgroundColor") ?? Color(.sRGB, red: 0.53, green: 0.81, blue: 0.98, opacity: 0.4)
        self.sasayakiDarkTextColor = UserConfig.loadColor(key: "sasayakiDarkTextColor") ?? Color(.sRGB, red: 1, green: 1, blue: 1)
        self.sasayakiDarkBackgroundColor = UserConfig.loadColor(key: "sasayakiDarkBackgroundColor") ?? Color(.sRGB, red: 0.53, green: 0.81, blue: 0.98, opacity: 0.4)
        Self.saveShortcutConfiguration(shortcutConfiguration)
        syncLocalAudioSource()
    }

    func resetVideoSubtitleAppearance() {
        videoRespectASSStyle = false
        videoSubtitleFontFamily = ""
        videoSubtitleFontSize = 36
        videoSubtitleFontWeight = 700
        videoSubtitleEdgeStyle = .highContrast
        videoSubtitleEdgeStrength = 0.5
        videoSubtitleBackgroundOpacity = 0
        videoSubtitleBackgroundDisabled = true
        videoSubtitleVerticalPosition = VideoSubtitlePositionPolicy.defaultPosition
        videoSubtitleColor = .white
        videoSubtitleLookupHighlightColor = Color(
            .sRGB,
            red: 181.0 / 255.0,
            green: 193.0 / 255.0,
            blue: 203.0 / 255.0,
            opacity: 62.0 / 255.0
        )
        videoSubtitleLookupHighlightTextColor = .white
    }

    func readerProfileSettings() -> ReaderProfileSettings {
        ReaderProfileSettings(
            theme: theme.rawValue,
            uiTheme: uiTheme.rawValue,
            systemLightSepia: systemLightSepia,
            sepiaInvertInDark: sepiaInvertInDark,
            customBackgroundColor: Self.profileColorHex(customBackgroundColor),
            customTextColor: Self.profileColorHex(customTextColor),
            customInfoColor: Self.profileColorHex(customInfoColor),
            verticalWriting: verticalWriting,
            selectedFont: selectedFont,
            fontSize: fontSize,
            hideFurigana: readerHideFurigana,
            continuousMode: continuousMode,
            twoColumnHorizontalPages: readerTwoColumnHorizontalPages,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            avoidPageBreak: avoidPageBreak,
            justifyText: justifyText,
            blurImages: blurImages,
            layoutAdvanced: layoutAdvanced,
            lineHeight: lineHeight,
            characterSpacing: characterSpacing,
            paragraphSpacing: paragraphSpacing,
            showTitle: readerShowTitle,
            showCharacters: readerShowCharacters,
            showPercentage: readerShowPercentage,
            showProgressTop: readerShowProgressTop,
            showStatisticsToggle: readerShowStatisticsToggle,
            showReadingSpeed: readerShowReadingSpeed,
            showReadingTime: readerShowReadingTime,
            showSasayakiToggle: readerShowSasayakiToggle
        )
    }

    func apply(readerProfileSettings settings: ReaderProfileSettings) {
        theme = Themes(rawValue: settings.theme) ?? .system
        uiTheme = Themes(rawValue: settings.uiTheme) ?? .system
        systemLightSepia = settings.systemLightSepia
        sepiaInvertInDark = settings.sepiaInvertInDark
        customBackgroundColor = Self.profileColor(settings.customBackgroundColor, fallback: customBackgroundColor)
        customTextColor = Self.profileColor(settings.customTextColor, fallback: customTextColor)
        customInfoColor = Self.profileColor(settings.customInfoColor, fallback: customInfoColor)
        verticalWriting = settings.verticalWriting
        selectedFont = settings.selectedFont
        fontSize = settings.fontSize
        readerHideFurigana = settings.hideFurigana
        continuousMode = settings.continuousMode
        readerTwoColumnHorizontalPages = settings.twoColumnHorizontalPages ?? false
        horizontalPadding = settings.horizontalPadding
        verticalPadding = settings.verticalPadding
        avoidPageBreak = settings.avoidPageBreak
        justifyText = settings.justifyText
        blurImages = settings.blurImages
        layoutAdvanced = settings.layoutAdvanced
        lineHeight = settings.lineHeight
        characterSpacing = settings.characterSpacing
        paragraphSpacing = settings.paragraphSpacing
        readerShowTitle = settings.showTitle
        readerShowCharacters = settings.showCharacters
        readerShowPercentage = settings.showPercentage
        readerShowProgressTop = settings.showProgressTop
        readerShowStatisticsToggle = settings.showStatisticsToggle
        readerShowReadingSpeed = settings.showReadingSpeed
        readerShowReadingTime = settings.showReadingTime
        readerShowSasayakiToggle = settings.showSasayakiToggle
    }

    func dictionaryProfileSettings() -> DictionaryProfileSettings {
        DictionaryProfileSettings(
            dictionaryTabDefault: dictionaryTabDefault,
            scanNonJapaneseText: scanNonJapaneseText,
            maxResults: maxResults,
            scanLength: scanLength,
            collapseMode: collapseMode.rawValue,
            expandFirstDictionary: expandFirstDictionary,
            twoColumnLayout: twoColumnLayout,
            compactGlossaries: compactGlossaries,
            showExpressionTags: showExpressionTags,
            harmonicFrequency: harmonicFrequency,
            deduplicatePitchAccents: deduplicatePitchAccents,
            compactPitchAccents: compactPitchAccents,
            customCSS: customCSS
        )
    }

    func apply(dictionaryProfileSettings settings: DictionaryProfileSettings) {
        dictionaryTabDefault = settings.dictionaryTabDefault
        scanNonJapaneseText = settings.scanNonJapaneseText
        maxResults = settings.maxResults
        scanLength = settings.scanLength
        collapseMode = CollapseMode(rawValue: settings.collapseMode) ?? .expandAll
        expandFirstDictionary = settings.expandFirstDictionary
        twoColumnLayout = settings.twoColumnLayout ?? false
        compactGlossaries = settings.compactGlossaries
        showExpressionTags = settings.showExpressionTags
        harmonicFrequency = settings.harmonicFrequency
        deduplicatePitchAccents = settings.deduplicatePitchAccents
        compactPitchAccents = settings.compactPitchAccents
        customCSS = settings.customCSS
    }

    private static func profileColorHex(_ color: Color) -> String {
        let resolved = color.resolve(in: EnvironmentValues())
        return ColorHexCodec.hexString(
            red: CGFloat(resolved.red),
            green: CGFloat(resolved.green),
            blue: CGFloat(resolved.blue),
            alpha: CGFloat(resolved.opacity)
        )
    }

    private static func profileColor(_ hex: String, fallback: Color) -> Color {
        guard let value = ColorHexCodec.components(hexString: hex) else { return fallback }
        return Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }

    private func syncLocalAudioSource() {
        audioSources = AudioSourceReorder.synchronizingLocalSource(
            audioSources,
            enabled: enableLocalAudio,
            canonicalSource: UserConfig.localAudioSource,
            legacyURLs: Set(Self.legacyLocalAudioURLs)
        )
    }

    private static func saveColor(_ color: Color, key: String) {
        let resolved = color.resolve(in: EnvironmentValues())
        Self.defaults.set(
            ColorHexCodec.hexString(
                red: CGFloat(resolved.red),
                green: CGFloat(resolved.green),
                blue: CGFloat(resolved.blue),
                alpha: CGFloat(resolved.opacity)
            ),
            forKey: key
        )
    }

    private static func loadColor(key: String) -> Color? {
        let defaults = Self.defaults
        if let hexString = defaults.string(forKey: key) {
            return ColorHexCodec.components(hexString: hexString).map {
                Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha)
            }
        }

        guard let colorData = defaults.data(forKey: key) else { return nil }
        if let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            let color = Color(nsColor: nsColor)
            saveColor(color, key: key)
            return color
        }
        return nil
    }

    private static func loadShortcut(key: String) -> ReaderKeyboardShortcut? {
        let defaults = Self.defaults
        if let data = defaults.data(forKey: key),
           let shortcut = try? JSONDecoder().decode(ReaderKeyboardShortcut.self, from: data) {
            return shortcut
        }

        // Migrate the earlier preset-only storage format.
        guard let rawValue = defaults.string(forKey: key) else {
            return nil
        }
        switch rawValue {
        case "leftArrow": return .leftArrow
        case "rightArrow": return .rightArrow
        case "bracketLeft": return .bracketLeft
        case "bracketRight": return .bracketRight
        case "p": return .p
        default: return nil
        }
    }

    func shortcutBinding(for action: ShortcutAction) -> KeyboardShortcutBinding {
        shortcutConfiguration.bindings[action.id] ?? action.defaultBinding
    }

    func setShortcutBinding(
        _ binding: KeyboardShortcutBinding,
        for action: ShortcutAction
    ) {
        shortcutConfiguration.bindings[action.id] = binding
    }

    func resetShortcutBinding(for action: ShortcutAction) {
        shortcutConfiguration.bindings.removeValue(forKey: action.id)
    }

    func controllerBinding(for action: ShortcutAction) -> XboxControllerBinding? {
        controllerConfiguration.bindings[action.id] ?? action.defaultControllerBinding
    }

    func setControllerBinding(
        _ binding: XboxControllerBinding,
        for action: ShortcutAction
    ) {
        controllerConfiguration.bindings[action.id] = binding
    }

    func resetControllerBinding(for action: ShortcutAction) {
        controllerConfiguration.bindings.removeValue(forKey: action.id)
    }

    private static func saveShortcutConfiguration(_ configuration: ShortcutConfiguration) {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: "shortcutConfiguration")
        }
    }

    private static func loadShortcutConfiguration() -> ShortcutConfiguration {
        let legacyActionIDs = [
            "readerPreviousPageShortcut": ReaderShortcutActions.previousPage.id,
            "readerNextPageShortcut": ReaderShortcutActions.nextPage.id,
            "sasayakiPreviousCueShortcut": SasayakiShortcutActions.previousCue.id,
            "sasayakiPlayPauseShortcut": SasayakiShortcutActions.playPause.id,
            "sasayakiNextCueShortcut": SasayakiShortcutActions.nextCue.id,
            "sasayakiReplayCueShortcut": SasayakiShortcutActions.replayCue.id,
            "sasayakiJumpCueShortcut": SasayakiShortcutActions.jumpCue.id,
            "dictionaryPreviousEntryShortcut": DictionaryShortcutActions.previousEntry.id,
            "dictionaryNextEntryShortcut": DictionaryShortcutActions.nextEntry.id
        ]
        let encoder = JSONEncoder()
        let legacyData: [String: Data] = Dictionary(
            uniqueKeysWithValues: legacyActionIDs.keys.compactMap { key in
                guard let binding = loadShortcut(key: key),
                      let data = try? encoder.encode(binding) else {
                    return nil
                }
                return (key, data)
            }
        )
        return ShortcutConfiguration.migrating(
            storedData: defaults.data(forKey: "shortcutConfiguration"),
            legacyData: legacyData,
            legacyActionIDs: legacyActionIDs
        )
    }

    private static func saveControllerConfiguration(_ configuration: ControllerConfiguration) {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: "controllerConfiguration")
        }
    }

    private static func loadControllerConfiguration() -> ControllerConfiguration {
        let legacyActionIDs = [
            "readerPreviousPageControllerBinding": ReaderShortcutActions.previousPage.id,
            "readerNextPageControllerBinding": ReaderShortcutActions.nextPage.id,
            "sasayakiPreviousCueControllerBinding": SasayakiShortcutActions.previousCue.id,
            "sasayakiPlayPauseControllerBinding": SasayakiShortcutActions.playPause.id,
            "sasayakiNextCueControllerBinding": SasayakiShortcutActions.nextCue.id,
            "sasayakiReplayCueControllerBinding": SasayakiShortcutActions.replayCue.id,
            "sasayakiJumpCueControllerBinding": SasayakiShortcutActions.jumpCue.id,
            "statisticsToggleControllerBinding": ReaderShortcutActions.toggleStatistics.id
        ]
        let decoder = JSONDecoder()
        let legacyBindings: [String: XboxControllerBinding] = Dictionary(
            uniqueKeysWithValues: legacyActionIDs.compactMap { key, actionID -> (String, XboxControllerBinding)? in
                guard let data = defaults.data(forKey: key),
                      let binding = try? decoder.decode(XboxControllerBinding.self, from: data) else {
                    return nil
                }
                return (actionID, binding)
            }
        )
        return ControllerConfiguration.migrating(
            storedData: defaults.data(forKey: "controllerConfiguration"),
            legacyBindings: legacyBindings
        )
    }

}
