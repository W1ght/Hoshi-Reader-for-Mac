import SwiftUI

struct SubtitleOverlayView: View {
    let cues: [SubtitleCue]
    let contextCues: [SubtitleCue]
    let scanLength: Int
    let contentLanguage: ContentLanguageProfile
    let hoverLookupDelayMs: Int
    let maskEnabled: Bool
    let maskMode: VideoSubtitleMaskMode
    let maskBlurRadius: Double
    let maskHiddenOpacity: Double
    let fontFamily: String
    let fontSize: Double
    let fontWeight: Int
    let edgeStyle: VideoSubtitleEdgeStyle
    let edgeStrength: Double
    let backgroundOpacity: Double
    let backgroundDisabled: Bool
    let verticalPosition: Double
    let subtitleColor: Color
    let lookupHighlightColor: Color
    let lookupHighlightTextColor: Color
    let isLookupPopupVisible: Bool
    let isPlaybackPaused: Bool
    var assRenderPlan: ASSRenderPlan? = nil
    var playbackTime: Double = 0
    var onSelection: ((SubtitleCue, SelectionData) -> Int?)?

    var body: some View {
        if let assRenderPlan {
            GeometryReader { geometry in
                ForEach(ASSInteractiveTextStyle.layout(
                    cues: cues, plan: assRenderPlan, size: geometry.size, time: playbackTime
                ), id: \.cue.id) { item in
                        let style = item.style
                        let measured = ASSInteractiveTextStyle.measuredSize(style.text, width: style.width)
                        subtitleRow(item.cue, styledText: style.text)
                            .frame(width: style.width, height: measured.height)
                            .position(x: style.anchor.x + (0.5 - style.alignment.x) * style.width,
                                      y: style.anchor.y + (0.5 - style.alignment.y) * measured.height)
                            .opacity(style.opacity)
                            .zIndex(Double(style.layer))
                }
            }
        } else {
        SubtitleVerticalPositionLayout(position: verticalPosition) {
            VStack(spacing: 8) {
                ForEach(cues) { cue in
                    subtitleRow(cue)
                }
            }
            .padding(.horizontal, 24)
        }
        }
    }

    private func subtitleRow(_ cue: SubtitleCue, styledText: NSAttributedString? = nil) -> some View {
        SubtitleCueMaskRow(
                        cue: cue,
                        contextCues: contextCues,
                        scanLength: scanLength,
                        contentLanguage: contentLanguage,
                        hoverLookupDelayMs: hoverLookupDelayMs,
                        maskEnabled: maskEnabled,
                        maskMode: maskMode,
                        maskBlurRadius: maskBlurRadius,
                        maskHiddenOpacity: maskHiddenOpacity,
                        fontFamily: fontFamily,
                        fontSize: fontSize,
                        fontWeight: fontWeight,
                        edgeStyle: edgeStyle,
                        edgeStrength: edgeStrength,
                        backgroundOpacity: backgroundOpacity,
                        backgroundDisabled: backgroundDisabled,
                        subtitleColor: subtitleColor,
                        lookupHighlightColor: lookupHighlightColor,
                        lookupHighlightTextColor: lookupHighlightTextColor,
                        isLookupPopupVisible: isLookupPopupVisible,
                        isPlaybackPaused: isPlaybackPaused,
                        styledText: styledText,
                        onSelection: onSelection
                    )
    }
}

private struct SubtitleCueMaskRow: View {
    let cue: SubtitleCue
    let contextCues: [SubtitleCue]
    let scanLength: Int
    let contentLanguage: ContentLanguageProfile
    let hoverLookupDelayMs: Int
    let maskEnabled: Bool
    let maskMode: VideoSubtitleMaskMode
    let maskBlurRadius: Double
    let maskHiddenOpacity: Double
    let fontFamily: String
    let fontSize: Double
    let fontWeight: Int
    let edgeStyle: VideoSubtitleEdgeStyle
    let edgeStrength: Double
    let backgroundOpacity: Double
    let backgroundDisabled: Bool
    let subtitleColor: Color
    let lookupHighlightColor: Color
    let lookupHighlightTextColor: Color
    let isLookupPopupVisible: Bool
    let isPlaybackPaused: Bool
    var styledText: NSAttributedString? = nil
    var onSelection: ((SubtitleCue, SelectionData) -> Int?)?

    @State private var isHovering = false
    @State private var availableTextWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            InteractiveSubtitleTextView(
                text: cue.text,
                scanLength: scanLength,
                contentLanguage: contentLanguage,
                hoverLookupDelayMs: hoverLookupDelayMs,
                fontFamily: fontFamily,
                fontSize: fontSize,
                fontWeight: fontWeight,
                edgeRecipe: edgeRecipe,
                subtitleColor: subtitleColor,
                lookupHighlightColor: lookupHighlightColor,
                lookupHighlightTextColor: lookupHighlightTextColor,
                isLookupPopupVisible: isLookupPopupVisible,
                onHoverChanged: { hovering in
                    isHovering = hovering
                },
                attributedText: styledText
            ) { lookupText, offset, localRect in
                let frame = geometry.frame(in: .named("video-player"))
                let selectionRect = CGRect(
                    x: frame.minX + localRect.minX,
                    y: frame.minY + localRect.minY,
                    width: max(localRect.width, 1),
                    height: max(localRect.height, 1)
                )
                let miningContext = VideoMiningContextSelectionBuilder.build(
                    cues: contextCues,
                    currentCueID: cue.id,
                    targetUTF16Location: offset
                )
                return onSelection?(
                    cue,
                    SelectionData(
                        text: lookupText,
                        sentence: cue.text,
                        rect: selectionRect,
                        normalizedOffset: offset,
                        miningContext: miningContext
                    )
                )
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            max(proxy.size.width, 1)
        } action: { width in
            availableTextWidth = width
        }
        .background {
            if styledText == nil && !backgroundDisabled && normalizedBackgroundOpacity > 0 {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(normalizedBackgroundOpacity))
            }
        }
        .blur(radius: maskedBlurRadius)
        .opacity(maskedOpacity)
        .animation(.smooth(duration: 0.12), value: isHovering)
        .animation(.smooth(duration: 0.12), value: isLookupPopupVisible)
        .frame(height: rowHeight)
        .padding(.horizontal, styledText == nil ? 14 : 0)
        .padding(.vertical, styledText == nil ? 6 : 0)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var maskedBlurRadius: CGFloat {
        guard maskEnabled, !isMaskRevealed, maskMode == .blur else { return 0 }
        return CGFloat(min(max(maskBlurRadius, 0), 20))
    }

    private var maskedOpacity: Double {
        guard maskEnabled, !isMaskRevealed, maskMode == .transparent else { return 1 }
        return min(max(maskHiddenOpacity, 0), 1)
    }

    private var edgeRecipe: VideoSubtitleEdgeRecipe {
        VideoSubtitleEdgeRecipe.make(
            style: edgeStyle,
            strength: edgeStrength,
            fontSize: CGFloat(min(max(fontSize, 12), 72))
        )
    }

    private var normalizedBackgroundOpacity: Double {
        min(max(backgroundOpacity, 0), 1)
    }

    private var isMaskRevealed: Bool {
        isHovering || isLookupPopupVisible || isPlaybackPaused
    }

    private var rowHeight: CGFloat {
        if let styledText {
            return ASSInteractiveTextStyle.measuredSize(
                styledText, width: availableTextWidth > 0 ? availableTextWidth : 640
            ).height
        }
        return SubtitleOverlayRowHeightMeasurer.height(
            for: cue.text,
            availableWidth: availableTextWidth > 0 ? availableTextWidth : 640,
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: fontWeight,
            edgeAllowance: edgeRecipe.layoutAllowance
        )
    }
}
