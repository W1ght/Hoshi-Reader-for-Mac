import AppKit
import SwiftUI

private final class ShiftHoverLookupResources: @unchecked Sendable {
    var workItem: DispatchWorkItem?
    var modifierFlagsMonitor: Any?
}

private final class ClickableSubtitleTextView: NSTextView {
    var onCharacterClicked: ((Int, CGRect) -> NSRange?)?
    var hoverLookupDelayMs = 45
    var lookupHighlightColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.78)
    var lookupHighlightTextColor = NSColor.textColor

    private var shiftHoverState = VideoShiftHoverLookupState()
    private var lastHoverPoint: CGPoint?
    private let shiftHoverResources = ShiftHoverLookupResources()
    private var textTrackingArea: NSTrackingArea?
    private var lookupHighlightRange: NSRange?

    func applyEdgeRecipe(_ recipe: VideoSubtitleEdgeRecipe) {
        guard let textStorage else { return }
        let range = NSRange(location: 0, length: textStorage.length)
        guard range.length > 0 else {
            needsDisplay = true
            return
        }

        textStorage.removeAttribute(.strokeColor, range: range)
        textStorage.removeAttribute(.strokeWidth, range: range)
        textStorage.removeAttribute(.shadow, range: range)
        if recipe.outlineWidth > 0,
           let font,
           font.pointSize > 0 {
            let strokePercentage = -(recipe.outlineWidth / font.pointSize * 100)
            textStorage.addAttributes(
                [
                    .strokeColor: NSColor.black,
                    .strokeWidth: NSNumber(value: Double(strokePercentage)),
                ],
                range: range
            )
        }
        if recipe.shadowPassCount > 0, recipe.shadowRadius > 0 {
            let shadow = NSShadow()
            shadow.shadowOffset = .zero
            shadow.shadowBlurRadius = recipe.shadowRadius
            shadow.shadowColor = NSColor.black
            textStorage.addAttribute(.shadow, value: shadow, range: range)
        }
        needsDisplay = true
    }

    func containsInteractiveText(at point: CGPoint) -> Bool {
        guard let layoutManager, let textContainer else { return false }
        layoutManager.ensureLayout(for: textContainer)
        var textBounds = layoutManager.usedRect(for: textContainer)
        textBounds.origin.x += textContainerOrigin.x
        textBounds.origin.y += textContainerOrigin.y
        return textBounds.insetBy(dx: -10, dy: -8).contains(point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        containsInteractiveText(at: point) ? super.hitTest(point) : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let textTrackingArea {
            removeTrackingArea(textTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        textTrackingArea = trackingArea
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeModifierFlagsMonitor()
        guard window != nil else {
            cancelShiftHoverLookup(resetState: true)
            return
        }
        shiftHoverResources.modifierFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierFlagsChanged(event.modifierFlags)
            return event
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hasHoverPoint = containsInteractiveText(at: point)
        lastHoverPoint = hasHoverPoint ? point : nil
        _ = shiftHoverState.setShiftPressed(event.modifierFlags.contains(.shift))
        _ = shiftHoverState.setHoverPointAvailable(hasHoverPoint)
        if shiftHoverState.pointerMoved(), hasHoverPoint {
            scheduleShiftHoverLookup(at: point)
        } else {
            cancelShiftHoverLookup(resetState: false)
        }
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        lastHoverPoint = nil
        _ = shiftHoverState.setHoverPointAvailable(false)
        cancelShiftHoverLookup(resetState: false)
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard containsInteractiveText(at: point) else { return }
        super.mouseDown(with: event)
        guard selectedRange().length == 0, event.clickCount == 1 else { return }
        performLookup(at: point)
    }

    func clearLookupHighlight() {
        guard let lookupHighlightRange else { return }
        layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: lookupHighlightRange)
        layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: lookupHighlightRange)
        self.lookupHighlightRange = nil
    }

    func updateLookupHighlightColor(_ color: NSColor) {
        lookupHighlightColor = color
        guard let lookupHighlightRange else { return }
        layoutManager?.addTemporaryAttribute(
            .backgroundColor,
            value: color,
            forCharacterRange: lookupHighlightRange
        )
    }

    func updateLookupHighlightTextColor(_ color: NSColor) {
        lookupHighlightTextColor = color
        guard let lookupHighlightRange else { return }
        layoutManager?.addTemporaryAttribute(
            .foregroundColor,
            value: color,
            forCharacterRange: lookupHighlightRange
        )
    }

    deinit {
        let resources = shiftHoverResources
        Task { @MainActor in
            resources.workItem?.cancel()
            if let modifierFlagsMonitor = resources.modifierFlagsMonitor {
                NSEvent.removeMonitor(modifierFlagsMonitor)
            }
        }
    }

    private func performLookup(at point: CGPoint) {
        guard let layoutManager, let textContainer,
              containsInteractiveText(at: point) else {
            return
        }
        let containerPoint = CGPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else { return }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: characterIndex, length: 1),
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        if let range = onCharacterClicked?(characterIndex, rect) {
            setLookupHighlight(range)
        } else {
            clearLookupHighlight()
        }
    }

    private func setLookupHighlight(_ range: NSRange) {
        clearLookupHighlight()
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= string.utf16.count else { return }
        layoutManager?.addTemporaryAttribute(
            .backgroundColor,
            value: lookupHighlightColor,
            forCharacterRange: range
        )
        layoutManager?.addTemporaryAttribute(
            .foregroundColor,
            value: lookupHighlightTextColor,
            forCharacterRange: range
        )
        lookupHighlightRange = range
    }

    private func handleModifierFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard window?.isKeyWindow == true else { return }
        let isShiftPressed = flags.contains(.shift)
        if shiftHoverState.setShiftPressed(isShiftPressed),
           let lastHoverPoint {
            scheduleShiftHoverLookup(at: lastHoverPoint)
        } else if !isShiftPressed {
            cancelShiftHoverLookup(resetState: false)
        }
    }

    private func scheduleShiftHoverLookup(at point: CGPoint) {
        shiftHoverResources.workItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.shiftHoverState.pointerMoved() else { return }
            self.performLookup(at: point)
        }
        shiftHoverResources.workItem = workItem
        let delay = VideoShiftHoverLookupState.normalizedDelayMilliseconds(hoverLookupDelayMs)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay), execute: workItem)
    }

    private func cancelShiftHoverLookup(resetState: Bool) {
        shiftHoverResources.workItem?.cancel()
        shiftHoverResources.workItem = nil
        if resetState {
            shiftHoverState.cancel()
            lastHoverPoint = nil
        }
    }

    private func removeModifierFlagsMonitor() {
        guard let modifierFlagsMonitor = shiftHoverResources.modifierFlagsMonitor else { return }
        NSEvent.removeMonitor(modifierFlagsMonitor)
        shiftHoverResources.modifierFlagsMonitor = nil
    }
}

private final class PassThroughSubtitleScrollView: NSScrollView {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func layout() {
        super.layout()
        syncDocumentViewFrame()
    }

    func syncDocumentViewFrame() {
        guard let textView = documentView as? ClickableSubtitleTextView else { return }
        textView.frame = contentView.bounds
        textView.textContainer?.containerSize = NSSize(
            width: max(contentView.bounds.width, 1),
            height: max(contentView.bounds.height, 1)
        )
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
        super.mouseExited(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let textView = documentView as? ClickableSubtitleTextView else {
            return nil
        }
        let textPoint = textView.convert(point, from: self)
        guard textView.containsInteractiveText(at: textPoint) else {
            return nil
        }
        return super.hitTest(point)
    }
}

struct InteractiveSubtitleTextView: NSViewRepresentable {
    let text: String
    let scanLength: Int
    let contentLanguage: ContentLanguageProfile
    let hoverLookupDelayMs: Int
    let fontFamily: String
    let fontSize: Double
    let fontWeight: Int
    let edgeRecipe: VideoSubtitleEdgeRecipe
    let subtitleColor: Color
    let lookupHighlightColor: Color
    let lookupHighlightTextColor: Color
    let isLookupPopupVisible: Bool
    var onHoverChanged: (Bool) -> Void = { _ in }
    var attributedText: NSAttributedString? = nil
    var onSelection: (String, Int, CGRect) -> Int?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PassThroughSubtitleScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.onHoverChanged = onHoverChanged

        let textView = ClickableSubtitleTextView()
        configureTextView(textView, isSelectable: true)
        textView.alignment = .center
        textView.textColor = NSColor(subtitleColor)
        textView.lookupHighlightColor = NSColor(lookupHighlightColor)
        textView.lookupHighlightTextColor = NSColor(lookupHighlightTextColor)
        textView.font = subtitleFont()
        textView.string = text
        textView.applyEdgeRecipe(edgeRecipe)
        if let attributedText, attributedText.string == text {
            textView.textStorage?.setAttributedString(attributedText)
        }
        textView.hoverLookupDelayMs = hoverLookupDelayMs
        textView.onCharacterClicked = { offset, rect in
            guard let candidate = SubtitleSelectionResolver.lookupCandidate(
                in: text,
                utf16Offset: offset,
                scanLength: scanLength,
                contentLanguage: contentLanguage
            ) else { return nil }
            guard let matchedCount = onSelection(candidate.text, candidate.utf16Start, rect) else {
                return nil
            }
            let matchedText = String(candidate.text.prefix(matchedCount))
            return SubtitleSelectionResolver.highlightRange(for: candidate, matchedText: matchedText)
        }
        scrollView.documentView = textView
        scrollView.syncDocumentViewFrame()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ClickableSubtitleTextView else { return }
        (scrollView as? PassThroughSubtitleScrollView)?.onHoverChanged = onHoverChanged
        if textView.string != text {
            textView.clearLookupHighlight()
            textView.string = text
        }
        if !isLookupPopupVisible {
            textView.clearLookupHighlight()
        }
        textView.font = subtitleFont()
        textView.textColor = NSColor(subtitleColor)
        textView.updateLookupHighlightColor(NSColor(lookupHighlightColor))
        textView.updateLookupHighlightTextColor(NSColor(lookupHighlightTextColor))
        textView.hoverLookupDelayMs = hoverLookupDelayMs
        textView.applyEdgeRecipe(edgeRecipe)
        if let attributedText, attributedText.string == text {
            textView.textStorage?.setAttributedString(attributedText)
        }
        textView.onCharacterClicked = { offset, rect in
            guard let candidate = SubtitleSelectionResolver.lookupCandidate(
                in: text,
                utf16Offset: offset,
                scanLength: scanLength,
                contentLanguage: contentLanguage
            ) else { return nil }
            guard let matchedCount = onSelection(candidate.text, candidate.utf16Start, rect) else {
                return nil
            }
            let matchedText = String(candidate.text.prefix(matchedCount))
            return SubtitleSelectionResolver.highlightRange(for: candidate, matchedText: matchedText)
        }
        (scrollView as? PassThroughSubtitleScrollView)?.syncDocumentViewFrame()
    }

    private func configureTextView(_ textView: NSTextView, isSelectable: Bool) {
        // Subtitle colors are authored video colors, not document colors to
        // invert when macOS switches between light and dark appearance.
        textView.usesAdaptiveColorMappingForDarkAppearance = false
        textView.textContainer?.replaceLayoutManager(SubtitleColorLayoutManager())
        textView.isEditable = false
        textView.isSelectable = isSelectable
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.alignment = .center
    }

    private func subtitleFont() -> NSFont {
        let size = CGFloat(min(max(fontSize, 12), 72))
        let family = fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        if !family.isEmpty,
           let font = NSFontManager.shared.font(
                withFamily: family,
                traits: [],
                weight: fontManagerWeight(),
                size: size
           ) {
            return font
        }
        return .systemFont(ofSize: size, weight: subtitleFontWeight())
    }

    private func subtitleFontWeight() -> NSFont.Weight {
        switch min(max(fontWeight, 100), 900) {
        case 100: .ultraLight
        case 200: .thin
        case 300: .light
        case 400: .regular
        case 500: .medium
        case 600: .semibold
        case 700: .bold
        case 800: .heavy
        default: .black
        }
    }

    private func fontManagerWeight() -> Int {
        switch min(max(fontWeight, 100), 900) {
        case 100: 2
        case 200: 3
        case 300: 4
        case 400: 5
        case 500: 6
        case 600: 8
        case 700: 9
        case 800: 12
        default: 14
        }
    }
}
