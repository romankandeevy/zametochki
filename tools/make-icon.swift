// Собирает build/AppIcon.icon (формат Icon Composer): ровная синяя заливка и белая «з» почерком Caveat.
// Блики, тень и стекло выключены, чтобы macOS не накладывала градиент. Компилирует build.sh через actool.
// Запуск: swift tools/make-icon.swift  (из папки проекта)
import AppKit

let fontURL = URL(fileURLWithPath: "Resources/Caveat.ttf")
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)

let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let s = CGFloat(px)
// Caveat вариативный: берём начертание 600, как жирноватый маркер.
let wght = 0x7767_6874
let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes([
    kCTFontNameAttribute: "Caveat-Regular",
    kCTFontVariationAttribute: [wght: 600],
] as CFDictionary), s * 0.62, nil)
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "з", attributes: [
    .font: font, .foregroundColor: NSColor.white,
]))
// Центрируем по контуру самой буквы, а не по строке: у «з» длинный хвост вниз.
let cg = ctx.cgContext
let bounds = CTLineGetImageBounds(line, cg)
cg.textPosition = CGPoint(x: (s - bounds.width) / 2 - bounds.minX, y: (s - bounds.height) / 2 - bounds.minY)
CTLineDraw(line, cg)
NSGraphicsContext.restoreGraphicsState()

let icon = URL(fileURLWithPath: "build/AppIcon.icon")
try? FileManager.default.removeItem(at: icon)
try! FileManager.default.createDirectory(at: icon.appendingPathComponent("Assets"), withIntermediateDirectories: true)
try! rep.representation(using: .png, properties: [:])!.write(to: icon.appendingPathComponent("Assets/z.png"))
let json = """
{
  "fill" : { "solid" : "srgb:0.11373,0.20784,0.58039,1.00000" },
  "groups" : [
    {
      "layers" : [ { "glass" : false, "image-name" : "z.png", "name" : "z" } ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "specular" : false,
      "translucency" : { "enabled" : false, "value" : 0 }
    }
  ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
"""
try! json.write(to: icon.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
