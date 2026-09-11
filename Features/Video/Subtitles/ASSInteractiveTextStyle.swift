import AppKit

/// Draw the outline behind the fill without changing the text storage or
/// laying out a second copy of the glyphs. Temporary drawing attributes also
/// preserve the selection/highlight geometry of the original layout manager.
nonisolated final class SubtitleColorLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    private enum Pass { case normal, outline, fill }
    private var pass = Pass.normal

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var hasOutline = false
        textStorage.enumerateAttribute(.strokeWidth, in: characters) { value, _, stop in
            if let width = value as? NSNumber, width.doubleValue != 0 {
                hasOutline = true
                stop.pointee = true
            }
        }
        guard hasOutline else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        defer { pass = .normal }
        pass = .outline
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        pass = .fill
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldUseTemporaryAttributes attrs: [NSAttributedString.Key: Any],
                       forDrawingToScreen toScreen: Bool,
                       atCharacterIndex charIndex: Int,
                       effectiveRange effectiveCharRange: NSRangePointer?) -> [NSAttributedString.Key: Any]? {
        guard pass != .normal, let textStorage, charIndex < textStorage.length else { return attrs }
        var run = NSRange()
        let source = textStorage.attributes(at: charIndex, effectiveRange: &run)
        if let effectiveCharRange {
            effectiveCharRange.pointee = NSIntersectionRange(effectiveCharRange.pointee, run)
        }
        let width = (source[.strokeWidth] as? NSNumber)?.doubleValue ?? 0
        var result = attrs
        if pass == .outline {
            result[.underlineStyle] = 0
            result[.strikethroughStyle] = 0
            result[.foregroundColor] = NSColor.clear
            result[.strokeWidth] = abs(width)
            if width == 0 { result[.shadow] = NSShadow() }
        } else {
            result[.strokeWidth] = 0
            if width != 0 { result[.shadow] = NSShadow() }
        }
        return result
    }
}

/// Native adaptation of Fushi's visible-text/character-hit-test ownership:
/// https://github.com/hajisensai/Fushi/blob/28567c32b19c837f9d753dec46e3a540c55cd319/fushi/lib/src/media/video/video_subtitle_overlay.dart
/// Both projects are GPL-3.0. TextKit draws and hit-tests the same attributed text.
struct ASSInteractiveTextStyle {
    let text: NSAttributedString
    var anchor: CGPoint
    let alignment: CGPoint
    let width: CGFloat
    let opacity: Double
    let layer: Int

    static func layout(cues: [SubtitleCue], plan: ASSRenderPlan, size: CGSize, time: Double) -> [(cue: SubtitleCue, style: Self)] {
        var occupied: [String: CGFloat] = [:]
        return cues.compactMap { cue in
            guard var style = make(cue: cue, plan: plan, size: size, time: time) else { return nil }
            if let event = plan.events.first(where: { $0.cueID == cue.id }),
               event.markers.intersection([.position, .movement]).isEmpty {
                let key = "\(style.layer)|\(style.alignment.x)|\(style.alignment.y)|\(style.anchor.x)"
                let height = measuredSize(style.text, width: style.width).height
                let offset = occupied[key, default: 0]
                style.anchor.y += style.alignment.y == 1 ? -offset : offset
                occupied[key] = offset + height
            }
            return (cue, style)
        }
    }

    static func make(cue: SubtitleCue, plan: ASSRenderPlan, size: CGSize, time: Double) -> Self? {
        guard let event = plan.events.first(where: { $0.cueID == cue.id }) else { return nil }
        let base = plan.styleDefinitions[event.style.lowercased()] ?? [:]
        var style = base
        let sx = size.width / max(plan.scriptWidth, 1)
        let sy = size.height / max(plan.scriptHeight, 1)
        let alignmentNumber = min(max(event.effectiveAlignment ?? 2, 1), 9)
        let alignment = CGPoint(x: Double((alignmentNumber - 1) % 3) / 2,
                                y: 1 - Double((alignmentNumber - 1) / 3) / 2)
        func margin(_ eventValue: Int?, _ key: String, _ fallback: Double) -> Double {
            if let eventValue, eventValue > 0 { return Double(eventValue) }
            return number(base[key], fallback)
        }
        let left = margin(event.marginLeft, "marginl", 10) * sx
        let right = margin(event.marginRight, "marginr", 10) * sx
        let vertical = margin(event.marginVertical, "marginv", 10) * sy
        var anchor = CGPoint(
            x: alignment.x == 0 ? left : alignment.x == 1 ? size.width - right : size.width / 2,
            y: alignment.y == 0 ? vertical : alignment.y == 1 ? size.height - vertical : size.height / 2
        )
        let elapsed = max(0, time - cue.startTime) * 1000
        var opacity = 1.0
        var drawing = false
        let result = NSMutableAttributedString(string: "")
        let raw = event.rawText
        var cursor = raw.startIndex
        func append(_ fragment: Substring) {
            guard !drawing else { return }
            let plain = String(fragment).replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\h", with: " ")
            result.append(NSAttributedString(string: plain, attributes: attributes(style, scale: sy)))
        }
        while cursor < raw.endIndex {
            guard raw[cursor] == "{", let close = raw[cursor...].firstIndex(of: "}") else {
                let end = raw[cursor...].firstIndex(of: "{") ?? raw.endIndex
                if end == cursor { append(raw[cursor...]); break }
                append(raw[cursor..<end]); cursor = end; continue
            }
            let block = raw[raw.index(after: cursor)..<close]
            // Parenthesized animation payloads stay whole; their nested tags
            // must not accidentally override the event's static style.
            let pattern = #"\\(move|pos|fade|fad|alpha|[1-4]a|[1-4]c|bord|shad|blur|be|clip|iclip|fscx|fscy|fsp|frz|frx|fry|fr|pbo|fn|fs|r|p|b|i|u|s|c|t)(\([^)]*\)|[^\\]*)"#
            let blockText = String(block)
            let regex = try? NSRegularExpression(pattern: pattern)
            for match in regex?.matches(in: blockText, range: NSRange(blockText.startIndex..., in: blockText)) ?? [] {
                guard let keyRange = Range(match.range(at: 1), in: blockText),
                      let valueRange = Range(match.range(at: 2), in: blockText) else { continue }
                let key = String(blockText[keyRange]).lowercased()
                let value = String(blockText[valueRange]).trimmingCharacters(in: .whitespaces)
                let coordinates = value.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                    .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                switch key {
                case "pos" where coordinates.count == 2 && coordinates.allSatisfy(\.isFinite):
                    anchor = CGPoint(x: coordinates[0] * sx, y: coordinates[1] * sy)
                case "move" where (coordinates.count == 4 || coordinates.count == 6) && coordinates.allSatisfy(\.isFinite):
                    let start = coordinates.count == 6 ? coordinates[4] : 0
                    let end = coordinates.count == 6 ? coordinates[5] : (cue.endTime - cue.startTime) * 1000
                    let progress = min(max((elapsed - start) / max(end - start, 1), 0), 1)
                    anchor = CGPoint(x: (coordinates[0] + (coordinates[2] - coordinates[0]) * progress) * sx,
                                     y: (coordinates[1] + (coordinates[3] - coordinates[1]) * progress) * sy)
                case "fad" where coordinates.count == 2 && coordinates.allSatisfy(\.isFinite):
                    let remaining = max(0, cue.endTime - time) * 1000
                    opacity = min(min(elapsed / max(coordinates[0], 1), remaining / max(coordinates[1], 1)), 1)
                case "r": style = value.isEmpty ? base : plan.styleDefinitions[value.lowercased()] ?? base
                case "p": drawing = number(value, 0) > 0
                case "fn": style["fontname"] = value
                case "fs": style["fontsize"] = value
                case "b": style["bold"] = value
                case "i": style["italic"] = value
                case "u": style["underline"] = value
                case "s": style["strikeout"] = value
                case "c", "1c": style["primaryrgb"] = value
                case "3c": style["outlinergb"] = value
                case "4c": style["shadowrgb"] = value
                case "bord": style["outline"] = value
                case "shad": style["shadow"] = value
                case "alpha":
                    for channel in ["primary", "outline", "shadow"] {
                        style[channel + "alpha"] = value
                    }
                case "1a": style["primaryalpha"] = value
                case "3a": style["outlinealpha"] = value
                case "4a": style["shadowalpha"] = value
                default: break
                }
            }
            cursor = raw.index(after: close)
        }
        // The parser's text is the lookup/transcript truth. Never attach styled
        // ranges to a different string (drawing transitions and edge whitespace).
        let trimmed = result.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let attributed: NSAttributedString
        if trimmed == cue.text, let range = result.string.range(of: cue.text) {
            attributed = result.attributedSubstring(from: NSRange(range, in: result.string))
        } else {
            attributed = NSAttributedString(string: cue.text, attributes: attributes(base, scale: sy))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment.x == 0 ? .left : alignment.x == 1 ? .right : .center
        let final = NSMutableAttributedString(attributedString: attributed)
        final.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: final.length))
        return Self(text: final, anchor: anchor, alignment: alignment,
                    width: max(1, size.width - left - right), opacity: opacity, layer: event.layer ?? 0)
    }

    private static func number(_ value: String?, _ fallback: Double) -> Double {
        guard let value, let number = Double(value), number.isFinite else { return fallback }
        return number
    }

    private static func color(_ value: String?, fallback: NSColor) -> NSColor {
        guard let value else { return fallback }
        let cleaned = value.uppercased().replacingOccurrences(of: "&H", with: "").replacingOccurrences(of: "&", with: "")
        let packed = value.uppercased().contains("&H") ? UInt32(cleaned, radix: 16) : Int64(cleaned).map { UInt32(truncatingIfNeeded: $0) }
        guard let packed else { return fallback }
        return NSColor(srgbRed: Double(packed & 255) / 255,
                       green: Double((packed >> 8) & 255) / 255,
                       blue: Double((packed >> 16) & 255) / 255,
                       alpha: 1 - Double((packed >> 24) & 255) / 255)
    }

    private static func attributes(_ style: [String: String], scale: Double) -> [NSAttributedString.Key: Any] {
        let size = min(max(number(style["fontsize"], 24) * scale, 1), 512)
        var traits: NSFontTraitMask = []
        if number(style["bold"], 0) != 0 { traits.insert(.boldFontMask) }
        if number(style["italic"], 0) != 0 { traits.insert(.italicFontMask) }
        let font = NSFontManager.shared.font(withFamily: style["fontname"] ?? "Arial", traits: traits,
                                            weight: traits.contains(.boldFontMask) ? 9 : 5, size: size)
            ?? NSFont.systemFont(ofSize: size)
        let foreground = channelColor(style, channel: "primary", baseKey: "primarycolour", fallback: .white)
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
        let outline = min(max(number(style["outline"], 0) * scale, 0), 50)
        if outline > 0 {
            attrs[.strokeColor] = channelColor(style, channel: "outline", baseKey: "outlinecolour", fallback: .black)
            attrs[.strokeWidth] = -outline * 200 / size
        }
        let depth = min(max(number(style["shadow"], 0) * scale, 0), 50)
        if depth > 0 {
            let shadow = NSShadow()
            shadow.shadowColor = channelColor(style, channel: "shadow", baseKey: "backcolour", fallback: .black)
            shadow.shadowOffset = CGSize(width: depth, height: -depth)
            attrs[.shadow] = shadow
        }
        if number(style["underline"], 0) != 0 { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if number(style["strikeout"], 0) != 0 { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attrs
    }

    private static func channelColor(_ style: [String: String], channel: String, baseKey: String, fallback: NSColor) -> NSColor {
        var result = color(style[baseKey], fallback: fallback)
        func hex(_ value: String?) -> UInt32? {
            guard let value else { return nil }
            return UInt32(value.uppercased().replacingOccurrences(of: "&H", with: "")
                .replacingOccurrences(of: "&", with: ""), radix: 16)
        }
        // ASS RGB overrides do not reset the independently authored alpha.
        if let rgb = hex(style[channel + "rgb"]) {
            result = NSColor(srgbRed: Double(rgb & 255) / 255,
                             green: Double((rgb >> 8) & 255) / 255,
                             blue: Double((rgb >> 16) & 255) / 255,
                             alpha: result.alphaComponent)
        }
        if let alpha = hex(style[channel + "alpha"]) {
            result = result.withAlphaComponent(1 - Double(alpha & 255) / 255)
        }
        return result
    }

    static func measuredSize(_ text: NSAttributedString, width: CGFloat) -> CGSize {
        let storage = NSTextStorage(attributedString: text)
        let container = NSTextContainer(size: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        return CGSize(width: max(1, ceil(used.width)), height: max(1, ceil(used.height) + 12))
    }
}
