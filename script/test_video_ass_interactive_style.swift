import AppKit

@main
enum ASSInteractiveStyleTests {
    @MainActor static func main() throws {
        let source = #"""
        [Script Info]
        PlayResX: 640
        PlayResY: 360
        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, Bold, Italic, Alignment, MarginL, MarginR, MarginV, Outline, Shadow
        Style: Default,Arial,30,&H000000FF,0,0,2,10,10,20,2,0
        [Events]
        Format: Layer, Start, End, Style, Text
        Dialogue: 0,0:00:00.00,0:00:10.00,Default,{\pos(100,60)}日本語
        Dialogue: 1,0:00:00.00,0:00:10.00,Default,{\pos(100,60)\bord4}日本語
        Dialogue: 0,0:00:00.00,0:00:10.00,Default,{\move(0,0,640,360)\fad(1000,1000)\c&H00FF00&}移動
        Dialogue: 0,0:00:00.00,0:00:10.00,Default,{\i1}漢字{\r}かな
        Dialogue: 0,0:00:00.00,0:00:10.00,Default,{\p1}m 0 0 l 10 10{\p0}文字
        Dialogue: 0,0:00:00.00,0:00:10.00,Default,{\p1}m 0 0 l 20 20
        """#
        let document = try SubtitleParser.parse(data: Data(source.utf8), sourceURL: URL(fileURLWithPath: "/tmp/style.ass"))
        let plan = document.assRenderPlan!
        let drawings = String(data: plan.interactiveEffectsOnlyData!, encoding: .utf8)!
        precondition(drawings.contains("m 0 0 l 20 20") && !drawings.contains("日本語"),
                     "The native effects track must never duplicate interactive text")
        precondition(ASSRenderPlan.uniqueTextCues(document.cues).count == 4, "KFX copies must show one selectable row")
        let cue = document.cues.first { $0.text == "日本語" }!
        let styled = ASSInteractiveTextStyle.make(cue: cue, plan: plan, size: CGSize(width: 1280, height: 720), time: 5)!
        precondition(styled.text.string == cue.text, "Visible and lookup text must be identical")
        precondition(styled.anchor == CGPoint(x: 200, y: 120), "ASS position must scale with the video viewport")
        let font = styled.text.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        precondition(font.pointSize == 60, "ASS font size must use PlayResY")
        let red = styled.text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor
        precondition(red.redComponent > 0.99 && red.greenComponent < 0.01, "ASS color is BGR")
        let moving = document.cues.first { $0.text == "移動" }!
        let middle = ASSInteractiveTextStyle.make(cue: moving, plan: plan, size: CGSize(width: 640, height: 360), time: 5)!
        precondition(middle.anchor == CGPoint(x: 320, y: 180), "Move must follow playback time")
        precondition(middle.opacity == 1)
        let fading = ASSInteractiveTextStyle.make(cue: moving, plan: plan, size: CGSize(width: 640, height: 360), time: 0.5)!
        precondition(fading.opacity == 0.5)
        let mixed = document.cues.first { $0.text == "文字" }!
        precondition(ASSInteractiveTextStyle.make(cue: mixed, plan: plan, size: CGSize(width: 640, height: 360), time: 5)!.text.string == "文字")
        let inline = document.cues.first { $0.text == "漢字かな" }!
        let inlineStyle = ASSInteractiveTextStyle.make(cue: inline, plan: plan, size: CGSize(width: 640, height: 360), time: 5)!
        let first = inlineStyle.text.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        let last = inlineStyle.text.attribute(.font, at: 2, effectiveRange: nil) as! NSFont
        precondition(NSFontManager.shared.traits(of: first).contains(.italicFontMask))
        precondition(!NSFontManager.shared.traits(of: last).contains(.italicFontMask))
        precondition(ASSInteractiveTextStyle.measuredSize(inlineStyle.text, width: 300).height > 0)
        let layout = ASSInteractiveTextStyle.layout(cues: [inline, mixed], plan: plan, size: CGSize(width: 640, height: 360), time: 5)
        precondition(layout.count == 2 && layout[0].style.anchor.y != layout[1].style.anchor.y,
                     "Simultaneous unpositioned dialogue must not overlap")
        let colorSource = source + #"""

        Dialogue: 0,0:00:00.00,0:00:10.00,Default,{\alpha&H80&\1c&HFFFFFF&\3a&HFF&\shad2}透明度
        """#
        let colorDocument = try SubtitleParser.parse(data: Data(colorSource.utf8), sourceURL: URL(fileURLWithPath: "/tmp/color.ass"))
        let colorCue = colorDocument.cues.first { $0.text == "透明度" }!
        let colors = ASSInteractiveTextStyle.make(cue: colorCue, plan: colorDocument.assRenderPlan!, size: CGSize(width: 640, height: 360), time: 5)!.text
        let fill = colors.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor
        let border = colors.attribute(.strokeColor, at: 0, effectiveRange: nil) as! NSColor
        let shadow = colors.attribute(.shadow, at: 0, effectiveRange: nil) as! NSShadow
        precondition(abs(fill.alphaComponent - 127.0 / 255) < 0.001 && fill.redComponent == 1,
                     "An RGB override must preserve the alpha override")
        precondition(border.alphaComponent == 0, "Outline alpha must be independent of fill alpha")
        precondition(abs(shadow.shadowColor!.alphaComponent - 127.0 / 255) < 0.001,
                     "Global alpha must apply to shadow as well as text")
        try verifyRasterFill()
        print("ASS interactive style tests passed")
    }

    @MainActor static func verifyRasterFill() throws {
        let storage = NSTextStorage(string: "字幕 ภาษาไทย", attributes: [
            .font: NSFont.systemFont(ofSize: 60), .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black, .strokeWidth: -30.0
        ])
        let manager = SubtitleColorLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 560, height: 140))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 180,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.orange.setFill()
        NSRect(x: 0, y: 0, width: 600, height: 180).fill()
        manager.drawGlyphs(forGlyphRange: manager.glyphRange(for: container), at: CGPoint(x: 20, y: 20))
        NSGraphicsContext.restoreGraphicsState()
        var whitePixels = 0
        var blackPixels = 0
        for y in 0..<180 {
            for x in 0..<600 {
                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.9 { whitePixels += 1 }
                if max(color.redComponent, color.greenComponent, color.blueComponent) < 0.1 { blackPixels += 1 }
            }
        }
        precondition(whitePixels > 200 && blackPixels > 200,
                     "Even a thick black outline must leave a visible white glyph fill")
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/niratan-subtitle-color-test.png"))
    }
}
