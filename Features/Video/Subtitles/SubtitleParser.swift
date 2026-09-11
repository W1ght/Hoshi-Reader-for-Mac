import Foundation

nonisolated enum SubtitleParser {
    nonisolated static func parse(
        data: Data,
        sourceURL: URL,
        formatHint: SubtitleFormat? = nil,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) throws -> SubtitleDocument {
        try throwIfCancelled(isCancelled)
        let format = try formatHint ?? format(for: sourceURL)
        let text = decode(data)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        try throwIfCancelled(isCancelled)
        switch format {
        case .ass, .ssa:
            return try parseAdvancedSubStationAlpha(
                text,
                sourceURL: sourceURL,
                format: format,
                isCancelled: isCancelled
            )
        case .srt, .webVTT, .embedded:
            break
        }

        let normalizedText = text.replacing(#/\n{2,}/#, with: "\n\n")
        let blocks = normalizedText.components(separatedBy: "\n\n")
        var warnings: [String] = []
        var cues: [SubtitleCue] = []

        for (index, block) in blocks.enumerated() {
            try throwIfCancelled(isCancelled)
            guard let cue = parseBlock(block, index: index, format: format) else {
                let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed != "WEBVTT", !trimmed.hasPrefix("NOTE") {
                    warnings.append("Skipped subtitle block \(index + 1).")
                }
                continue
            }
            cues.append(cue)
        }

        try throwIfCancelled(isCancelled)
        cues.sort {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }
        try throwIfCancelled(isCancelled)
        guard !cues.isEmpty else {
            throw SubtitleParserError.noValidCues
        }
        return SubtitleDocument(sourceURL: sourceURL, format: format, cues: cues, warnings: warnings)
    }

    nonisolated private static func format(for url: URL) throws -> SubtitleFormat {
        switch url.pathExtension.lowercased() {
        case "srt":
            return .srt
        case "vtt":
            return .webVTT
        case "ass":
            return .ass
        case "ssa":
            return .ssa
        default:
            throw SubtitleParserError.unsupportedFormat
        }
    }

    nonisolated private static func decode(_ data: Data) -> String {
        if let value = String(data: data, encoding: .utf8) {
            return value.replacingOccurrences(of: "\u{feff}", with: "")
        }
        if let value = String(data: data, encoding: .utf16) {
            return value.replacingOccurrences(of: "\u{feff}", with: "")
        }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func parseBlock(_ block: String, index: Int, format: SubtitleFormat) -> SubtitleCue? {
        var lines = block.components(separatedBy: "\n")
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        guard !lines.isEmpty else { return nil }

        if format == .webVTT, lines.first?.hasPrefix("WEBVTT") == true {
            lines.removeFirst()
        }
        guard !lines.isEmpty else { return nil }

        let timingIndex = lines.firstIndex(where: { $0.contains("-->") })
        guard let timingIndex else { return nil }
        let timing = lines[timingIndex].components(separatedBy: "-->")
        guard timing.count == 2 else { return nil }
        let endToken = timing[1].split(whereSeparator: \.isWhitespace).first.map(String.init) ?? timing[1]
        guard let start = parseTimestamp(timing[0]),
              let end = parseTimestamp(endToken),
              end >= start else {
            return nil
        }

        let rawText = lines
            .dropFirst(timingIndex + 1)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let text = format == .webVTT
            ? cleanedWebVTTText(rawText)
            : rawText
        guard !text.isEmpty else { return nil }

        let declaredID = timingIndex > 0
            ? lines[timingIndex - 1].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return SubtitleCue(
            id: declaredID.isEmpty ? "\(index)" : declaredID,
            startTime: start,
            endTime: end,
            text: text
        )
    }

    nonisolated private static func cleanedWebVTTText(_ rawText: String) -> String {
        rawText
            .replacing(#/<[^>\n]+>/#, with: "")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lrm;", with: "")
            .replacingOccurrences(of: "&rlm;", with: "")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let timestamp = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = timestamp.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }

        let hours: Double
        let minutes: Double
        let seconds: Double
        if parts.count == 3 {
            guard let parsedHours = Double(parts[0]),
                  let parsedMinutes = Double(parts[1]),
                  let parsedSeconds = Double(parts[2]) else {
                return nil
            }
            hours = parsedHours
            minutes = parsedMinutes
            seconds = parsedSeconds
        } else {
            guard let parsedMinutes = Double(parts[0]),
                  let parsedSeconds = Double(parts[1]) else {
                return nil
            }
            hours = 0
            minutes = parsedMinutes
            seconds = parsedSeconds
        }
        let result = hours * 3600 + minutes * 60 + seconds
        guard timestampMilliseconds(result) != nil else { return nil }
        return result
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

    nonisolated private static func parseAdvancedSubStationAlpha(
        _ text: String,
        sourceURL: URL,
        format: SubtitleFormat,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> SubtitleDocument {
        var warnings: [String] = []
        var cues: [SubtitleCue] = []
        var section = ""
        var eventFields = format == .ssa
            ? defaultSSADialogueFields
            : defaultASSDialogueFields
        var styleFields = format == .ssa
            ? defaultSSAStyleFields
            : defaultASSStyleFields
        var styleAlignments: [String: Int] = [:]
        var styleDefinitions: [String: [String: String]] = [:]
        var scriptWidth: Double = 384
        var scriptHeight: Double = 288
        var parsedEvents: [ParsedASSEvent] = []
        var dialogueLineIndices: Set<Int> = []
        let sourceLines = text.components(separatedBy: "\n")

        for (lineIndex, rawLine) in sourceLines.enumerated() {
            try throwIfCancelled(isCancelled)
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = line.lowercased()
                continue
            }

            if section == "[v4+ styles]" || section == "[v4 styles]" {
                if let formatValue = value(after: "Format:", in: line) {
                    let parsedFields = parseASSFields(formatValue)
                    if parsedFields.contains("name") {
                        styleFields = parsedFields
                    }
                    continue
                }
                if let styleValue = value(after: "Style:", in: line),
                   let style = parseASSStyle(
                       styleValue,
                       fields: styleFields,
                       usesLegacyAlignment: section == "[v4 styles]"
                   ) {
                    styleAlignments[style.name.lowercased()] = style.alignment
                    let values = styleValue.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    if values.count == styleFields.count {
                        styleDefinitions[style.name.lowercased()] = Dictionary(
                            zip(styleFields, values), uniquingKeysWith: { _, last in last }
                        )
                    }
                }
                continue
            }

            if section == "[script info]" {
                if let raw = value(after: "PlayResX:", in: line),
                   let width = Double(raw), width.isFinite, width > 0 {
                    scriptWidth = width
                }
                if let raw = value(after: "PlayResY:", in: line),
                   let height = Double(raw), height.isFinite, height > 0 {
                    scriptHeight = height
                }
            }

            guard section == "[events]" else { continue }

            if let formatValue = value(after: "Format:", in: line) {
                let parsedFields = parseASSFields(formatValue)
                if parsedFields.contains("start"),
                   parsedFields.contains("end"),
                   parsedFields.contains("text") {
                    eventFields = parsedFields
                }
                continue
            }

            let eventKind: ASSSubtitleEventKind
            let eventValue: String
            if let dialogueValue = value(after: "Dialogue:", in: line) {
                eventKind = .dialogue
                eventValue = dialogueValue
                dialogueLineIndices.insert(lineIndex)
            } else if let commentValue = value(after: "Comment:", in: line) {
                eventKind = .comment
                eventValue = commentValue
            } else {
                continue
            }

            guard let event = parseASSEvent(
                eventValue,
                rawLine: rawLine,
                fields: eventFields,
                lineIndex: lineIndex,
                kind: eventKind,
                styleAlignments: styleAlignments
            ) else {
                if eventKind == .dialogue {
                    warnings.append("Skipped ASS dialogue line \(lineIndex + 1).")
                }
                continue
            }
            parsedEvents.append(event)
            if let cue = event.cue {
                cues.append(cue)
            }
        }

        try throwIfCancelled(isCancelled)
        cues.sort {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }
        try throwIfCancelled(isCancelled)
        guard !cues.isEmpty else {
            throw SubtitleParserError.noValidCues
        }

        let duplicateKeys = try multilayerDuplicateKeys(
            in: parsedEvents,
            isCancelled: isCancelled
        )
        try throwIfCancelled(isCancelled)
        let primaryLineIndices = Set(parsedEvents.compactMap { event -> Int? in
            guard event.isPrimaryCandidate,
                  let duplicateKey = event.duplicateKey,
                  !duplicateKeys.contains(duplicateKey) else {
                return nil
            }
            return event.lineIndex
        })
        let primaryCueIDs = Set(parsedEvents.compactMap { event -> String? in
            guard primaryLineIndices.contains(event.lineIndex) else { return nil }
            return event.cue?.id
        })
        let eventMetadata = parsedEvents.map { event in
            ASSSubtitleEvent(
                id: "ass-event-\(event.lineNumber)",
                cueID: event.cue?.id,
                lineNumber: event.lineNumber,
                kind: event.kind,
                startTime: event.startTime,
                endTime: event.endTime,
                layer: event.layer,
                style: event.style,
                name: event.name,
                marginLeft: event.marginLeft,
                marginRight: event.marginRight,
                marginVertical: event.marginVertical,
                effect: event.effect,
                rawLine: event.rawLine,
                rawText: event.rawText,
                plainText: event.plainText,
                styleAlignment: event.styleAlignment,
                effectiveAlignment: event.effectiveAlignment,
                markers: event.markers,
                isPrimaryDialogue: primaryLineIndices.contains(event.lineIndex)
            )
        }
        try throwIfCancelled(isCancelled)

        let hasRemainingDialogue = dialogueLineIndices.contains {
            !primaryLineIndices.contains($0)
        }
        let effectsOnlyData: Data?
        if !primaryLineIndices.isEmpty, hasRemainingDialogue {
            try throwIfCancelled(isCancelled)
            let effectsText = sourceLines.enumerated()
                .filter { !primaryLineIndices.contains($0.offset) }
                .map(\.element)
                .joined(separator: "\n")
            effectsOnlyData = Data(effectsText.utf8)
            try throwIfCancelled(isCancelled)
        } else {
            effectsOnlyData = nil
        }
        let drawingLines = Set(parsedEvents.filter {
            $0.kind == .dialogue && $0.cue == nil && $0.markers.contains(.drawing)
        }.map(\.lineIndex))
        let interactiveEffectsOnlyData: Data? = drawingLines.isEmpty ? nil : Data(
            sourceLines.enumerated().filter {
                !dialogueLineIndices.contains($0.offset) || drawingLines.contains($0.offset)
            }.map(\.element).joined(separator: "\n").utf8
        )

        return SubtitleDocument(
            sourceURL: sourceURL,
            format: format,
            cues: cues,
            warnings: warnings,
            assRenderPlan: ASSRenderPlan(
                primaryCueIDs: primaryCueIDs,
                events: eventMetadata,
                effectsOnlyData: effectsOnlyData,
                styleDefinitions: styleDefinitions,
                scriptWidth: scriptWidth,
                scriptHeight: scriptHeight,
                interactiveEffectsOnlyData: interactiveEffectsOnlyData
            )
        )
    }

    nonisolated private struct ParsedASSStyle {
        let name: String
        let alignment: Int
    }

    nonisolated private struct ASSDuplicateKey: Hashable {
        let startMilliseconds: Int64
        let endMilliseconds: Int64
        let text: String
    }

    nonisolated private struct ParsedASSEvent {
        let lineIndex: Int
        let lineNumber: Int
        let kind: ASSSubtitleEventKind
        let startTime: TimeInterval?
        let endTime: TimeInterval?
        let layer: Int?
        let style: String
        let name: String
        let marginLeft: Int?
        let marginRight: Int?
        let marginVertical: Int?
        let effect: String
        let rawLine: String
        let rawText: String
        let plainText: String
        let styleAlignment: Int?
        let effectiveAlignment: Int?
        let markers: ASSSubtitleEventMarkers
        let cue: SubtitleCue?

        var isPrimaryCandidate: Bool {
            guard kind == .dialogue,
                  cue != nil,
                  styleAlignment.map(Self.isBottomAlignment) == true,
                  effectiveAlignment.map(Self.isBottomAlignment) == true else {
                return false
            }
            let exclusions: ASSSubtitleEventMarkers = [
                .position,
                .movement,
                .origin,
                .clipping,
                .drawing,
                .karaoke,
                .animation,
                .geometricAnimation,
                .eventEffect,
                .lyrics
            ]
            return markers.intersection(exclusions).isEmpty
        }

        var duplicateKey: ASSDuplicateKey? {
            guard let startTime,
                  let endTime,
                  let startMilliseconds = SubtitleParser.timestampMilliseconds(startTime),
                  let endMilliseconds = SubtitleParser.timestampMilliseconds(endTime),
                  !plainText.isEmpty else {
                return nil
            }
            return ASSDuplicateKey(
                startMilliseconds: startMilliseconds,
                endMilliseconds: endMilliseconds,
                text: plainText
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
            )
        }

        private static func isBottomAlignment(_ alignment: Int) -> Bool {
            (1...3).contains(alignment)
        }
    }

    nonisolated private static let defaultASSDialogueFields = [
        "layer",
        "start",
        "end",
        "style",
        "name",
        "marginl",
        "marginr",
        "marginv",
        "effect",
        "text"
    ]

    nonisolated private static let defaultSSADialogueFields = [
        "marked",
        "start",
        "end",
        "style",
        "name",
        "marginl",
        "marginr",
        "marginv",
        "effect",
        "text"
    ]

    nonisolated private static let defaultASSStyleFields = [
        "name", "fontname", "fontsize", "primarycolour", "secondarycolour",
        "outlinecolour", "backcolour", "bold", "italic", "underline",
        "strikeout", "scalex", "scaley", "spacing", "angle", "borderstyle",
        "outline", "shadow", "alignment", "marginl", "marginr", "marginv",
        "encoding"
    ]

    nonisolated private static let defaultSSAStyleFields = [
        "name", "fontname", "fontsize", "primarycolour", "secondarycolour",
        "tertiarycolour", "backcolour", "bold", "italic", "borderstyle",
        "outline", "shadow", "alignment", "marginl", "marginr", "marginv",
        "alphalevel", "encoding"
    ]

    nonisolated private static func parseASSFields(_ rawValue: String) -> [String] {
        rawValue
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }

    nonisolated private static func parseASSStyle(
        _ rawStyle: String,
        fields: [String],
        usesLegacyAlignment: Bool
    ) -> ParsedASSStyle? {
        let values = splitASSValues(rawStyle, fields: fields)
        guard let name = field("name", fields: fields, values: values),
              !name.isEmpty else {
            return nil
        }
        let rawAlignment = field("alignment", fields: fields, values: values)
            .flatMap(parseASSInteger) ?? 2
        let alignment = usesLegacyAlignment
            ? normalizedLegacyAlignment(rawAlignment)
            : rawAlignment
        guard (1...9).contains(alignment) else { return nil }
        return ParsedASSStyle(name: name, alignment: alignment)
    }

    nonisolated private static func parseASSEvent(
        _ rawEvent: String,
        rawLine: String,
        fields: [String],
        lineIndex: Int,
        kind: ASSSubtitleEventKind,
        styleAlignments: [String: Int]
    ) -> ParsedASSEvent? {
        guard let startIndex = fields.firstIndex(of: "start"),
              let endIndex = fields.firstIndex(of: "end"),
              let textIndex = fields.firstIndex(of: "text") else {
            return nil
        }

        let values = splitASSValues(rawEvent, fields: fields)
        guard values.indices.contains(startIndex),
              values.indices.contains(endIndex),
              values.indices.contains(textIndex) else {
            return nil
        }

        let start = parseTimestamp(values[startIndex])
        let end = parseTimestamp(values[endIndex])
        let hasValidTiming = start != nil && end != nil && end! >= start!
        let rawText = values[textIndex]
        let plainText = cleanedASSText(rawText)
        let style = field("style", fields: fields, values: values) ?? ""
        let styleAlignment = styleAlignments[style.lowercased()]
        let effectiveAlignment = effectiveASSAlignment(
            rawText: rawText,
            baseAlignment: styleAlignment
        )
        var markers = assEventMarkers(in: rawText)
        let effect = field("effect", fields: fields, values: values) ?? ""
        if !effect.isEmpty {
            markers.insert(.eventEffect)
        }
        let name = field("name", fields: fields, values: values) ?? ""
        if hasLyricSemantics(style: style, name: name) {
            markers.insert(.lyrics)
        }

        let cue: SubtitleCue?
        if kind == .dialogue,
           hasValidTiming,
           !plainText.isEmpty,
           let start,
           let end {
            cue = SubtitleCue(
                id: "ass-\(lineIndex + 1)",
                startTime: start,
                endTime: end,
                text: plainText
            )
        } else {
            cue = nil
        }

        return ParsedASSEvent(
            lineIndex: lineIndex,
            lineNumber: lineIndex + 1,
            kind: kind,
            startTime: start,
            endTime: end,
            layer: parsedASSLayer(fields: fields, values: values),
            style: style,
            name: name,
            marginLeft: field("marginl", fields: fields, values: values).flatMap(parseASSInteger),
            marginRight: field("marginr", fields: fields, values: values).flatMap(parseASSInteger),
            marginVertical: field("marginv", fields: fields, values: values).flatMap(parseASSInteger),
            effect: effect,
            rawLine: rawLine,
            rawText: rawText,
            plainText: plainText,
            styleAlignment: styleAlignment,
            effectiveAlignment: effectiveAlignment,
            markers: markers,
            cue: cue
        )
    }

    nonisolated private static func splitASSValues(
        _ rawValue: String,
        fields: [String]
    ) -> [String] {
        guard !fields.isEmpty else { return [] }
        let pieces = rawValue
            .split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        guard let textIndex = fields.firstIndex(of: "text"),
              pieces.count > fields.count else {
            if pieces.count >= fields.count {
                return Array(pieces.prefix(fields.count))
            }
            return pieces + Array(repeating: "", count: fields.count - pieces.count)
        }

        let surplus = pieces.count - fields.count
        var result: [String] = []
        result.reserveCapacity(fields.count)
        for fieldIndex in fields.indices {
            if fieldIndex < textIndex {
                result.append(pieces[fieldIndex])
            } else if fieldIndex == textIndex {
                result.append(pieces[fieldIndex...(fieldIndex + surplus)].joined(separator: ","))
            } else {
                result.append(pieces[fieldIndex + surplus])
            }
        }
        return result
    }

    nonisolated private static func field(
        _ name: String,
        fields: [String],
        values: [String]
    ) -> String? {
        guard let index = fields.firstIndex(of: name), values.indices.contains(index) else {
            return nil
        }
        return values[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func parseASSInteger(_ rawValue: String) -> Int? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let equalsIndex = value.lastIndex(of: "=") {
            return Int(value[value.index(after: equalsIndex)...])
        }
        return Int(value)
    }

    nonisolated private static func parsedASSLayer(
        fields: [String],
        values: [String]
    ) -> Int? {
        field("layer", fields: fields, values: values).flatMap(parseASSInteger)
            ?? field("marked", fields: fields, values: values).flatMap(parseASSInteger)
    }

    nonisolated private static func normalizedLegacyAlignment(_ alignment: Int) -> Int {
        switch alignment {
        case 1, 2, 3:
            return alignment
        case 4, 8:
            return 7
        case 5:
            return 7
        case 6:
            return 8
        case 7:
            return 9
        case 9:
            return 4
        case 10:
            return 5
        case 11:
            return 6
        default:
            return alignment
        }
    }

    nonisolated private static func effectiveASSAlignment(
        rawText: String,
        baseAlignment: Int?
    ) -> Int? {
        guard let baseAlignment else { return nil }
        let modern = regexCaptures(
            modernAlignmentExpression,
            in: rawText
        ).compactMap { match in
            Int(match.value).map { (match.location, $0) }
        }
        let legacy = regexCaptures(
            legacyAlignmentExpression,
            in: rawText
        ).compactMap { match in
            Int(match.value).map {
                (match.location, normalizedLegacyAlignment($0))
            }
        }
        // libass treats alignment as a once-per-event property: the first
        // valid \an/\a wins, and a later \r style reset does not change it.
        return (modern + legacy).min(by: { $0.0 < $1.0 })?.1 ?? baseAlignment
    }

    nonisolated private static func hasLyricSemantics(
        style: String,
        name: String
    ) -> Bool {
        let strongTokens: Set<String> = [
            "kara", "karaoke", "lyric", "lyrics", "song", "songs",
            "insert", "vocal", "vocals",
        ]
        let styleTokens = semanticTokens(in: style)
        if !styleTokens.isDisjoint(with: strongTokens.union(["op", "ed", "opening", "ending"])) {
            return true
        }
        if !semanticTokens(in: name).isDisjoint(
            with: strongTokens.union(["op", "ed", "opening", "ending"])
        ) {
            return true
        }
        let combined = "\(style) \(name)".lowercased()
        return combined.contains("歌詞")
            || combined.contains("歌词")
            || combined.contains("主題歌")
            || combined.contains("主题歌")
    }

    nonisolated private static func semanticTokens(in value: String) -> Set<String> {
        Set(
            value.lowercased().split(whereSeparator: {
                !$0.isASCII || !$0.isLetter && !$0.isNumber
            }).map(String.init)
        )
    }

    nonisolated private static func assEventMarkers(
        in rawText: String
    ) -> ASSSubtitleEventMarkers {
        var markers: ASSSubtitleEventMarkers = []
        if containsRegex(positionExpression, in: rawText) { markers.insert(.position) }
        if containsRegex(movementExpression, in: rawText) { markers.insert(.movement) }
        if containsRegex(originExpression, in: rawText) { markers.insert(.origin) }
        if containsRegex(clippingExpression, in: rawText) { markers.insert(.clipping) }
        if containsRegex(drawingExpression, in: rawText) { markers.insert(.drawing) }
        if containsRegex(karaokeExpression, in: rawText) { markers.insert(.karaoke) }
        if containsRegex(animationExpression, in: rawText) {
            markers.insert(.animation)
        }
        if animationBodies(in: rawText).contains(where: {
            containsRegex(geometricAnimationExpression, in: $0)
        }) {
            markers.insert(.geometricAnimation)
        }
        return markers
    }

    nonisolated private static func animationBodies(in rawText: String) -> [String] {
        let characters = Array(rawText)
        guard characters.count >= 3 else { return [] }
        var bodies: [String] = []
        var index = 0
        while index + 2 < characters.count {
            guard characters[index] == "\\",
                  characters[index + 1].lowercased() == "t" else {
                index += 1
                continue
            }
            var openIndex = index + 2
            while openIndex < characters.count, characters[openIndex].isWhitespace {
                openIndex += 1
            }
            guard openIndex < characters.count, characters[openIndex] == "(" else {
                index += 1
                continue
            }
            var depth = 1
            var closeIndex = openIndex + 1
            while closeIndex < characters.count, depth > 0 {
                if characters[closeIndex] == "(" { depth += 1 }
                if characters[closeIndex] == ")" { depth -= 1 }
                closeIndex += 1
            }
            if depth == 0 {
                bodies.append(String(characters[(openIndex + 1)..<(closeIndex - 1)]))
                index = closeIndex
            } else {
                index += 1
            }
        }
        return bodies
    }

    nonisolated private static func containsRegex(
        _ expression: NSRegularExpression,
        in value: String
    ) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.firstMatch(in: value, range: range) != nil
    }

    nonisolated private static func regexCaptures(
        _ expression: NSRegularExpression,
        in value: String
    ) -> [(location: Int, value: String)] {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let captureRange = Range(result.range(at: 1), in: value) else {
                return nil
            }
            return (result.range.location, String(value[captureRange]))
        }
    }

    nonisolated private static let modernAlignmentExpression = makeExpression(
        #"\\an\s*([1-9])"#
    )
    nonisolated private static let legacyAlignmentExpression = makeExpression(
        #"\\a\s*(10|11|[1-9])"#
    )
    nonisolated private static let positionExpression = makeExpression(#"\\pos\s*\("#)
    nonisolated private static let movementExpression = makeExpression(#"\\move\s*\("#)
    nonisolated private static let originExpression = makeExpression(#"\\org\s*\("#)
    nonisolated private static let clippingExpression = makeExpression(#"\\i?clip\s*\("#)
    nonisolated private static let drawingExpression = makeExpression(
        #"\\p(?:bo\b|\s*[1-9])"#
    )
    nonisolated private static let karaokeExpression = makeExpression(
        #"\\(?:kf|ko|kt|k)\s*\d"#
    )
    nonisolated private static let animationExpression = makeExpression(
        #"\\(?:t\s*\(|fad(?:e)?\s*\()"#
    )
    nonisolated private static let geometricAnimationExpression = makeExpression(
        #"\\(?:fscx|fscy|fsp|fs|frx|fry|frz|fr|fax|fay|xbord|ybord|bord|xshad|yshad|shad)(?![a-z])"#
    )

    nonisolated private static func makeExpression(
        _ pattern: String
    ) -> NSRegularExpression {
        // All patterns are compile-time constants covered by the subtitle
        // parser tests, so a construction failure is a programmer error.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    nonisolated private static func multilayerDuplicateKeys(
        in events: [ParsedASSEvent],
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> Set<ASSDuplicateKey> {
        var counts: [ASSDuplicateKey: Int] = [:]
        counts.reserveCapacity(events.count)
        for event in events {
            try throwIfCancelled(isCancelled)
            guard event.kind == .dialogue, let key = event.duplicateKey else { continue }
            counts[key, default: 0] += 1
        }
        try throwIfCancelled(isCancelled)
        return Set(counts.compactMap { key, count in
            count > 1 ? key : nil
        })
    }

    nonisolated private static func throwIfCancelled(
        _ isCancelled: @Sendable () -> Bool
    ) throws {
        if isCancelled() {
            throw CancellationError()
        }
    }

    nonisolated private static func cleanedASSText(_ rawText: String) -> String {
        ASSSubtitleTextSanitizer.clean(rawText)
    }

    nonisolated private static func value(after prefix: String, in line: String) -> String? {
        guard line.range(
            of: prefix,
            options: [.anchored, .caseInsensitive]
        ) != nil else {
            return nil
        }
        return String(line.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
