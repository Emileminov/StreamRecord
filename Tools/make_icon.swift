import AppKit
import Foundation

// Генератор иконки: киношная хлопушка на тёплом жёлто-оранжевом градиенте.
// Рисуется чистым Core Graphics, без внешних картинок.
//
// Использование: swift Tools/make_icon.swift <путь к .iconset>

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("Укажите путь к .iconset\n".data(using: .utf8)!)
    exit(1)
}
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func rrect(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad)
}

func drawIcon(pixels: Int) -> Data {
    let s = CGFloat(pixels)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!

    let body = NSRect(x: s * 0.055, y: s * 0.055, width: s * 0.89, height: s * 0.89)
    let corner = body.width * 0.2237
    let bodyPath = rrect(body, corner)
    let mid = s / 2

    ctx.saveGraphicsState()
    bodyPath.addClip()

    // Тёплый жёлто-оранжевый фон.
    NSGradient(colors: [srgb(1.0, 0.82, 0.30), srgb(1.0, 0.55, 0.20)])!.draw(in: body, angle: -70)

    // Корпус хлопушки (тёмная доска) с двумя «строками».
    let board = NSRect(x: mid - s * 0.28, y: mid - s * 0.25, width: s * 0.56, height: s * 0.36)
    srgb(0.12, 0.12, 0.15).setFill()
    rrect(board, s * 0.04).fill()
    srgb(1, 1, 1, 0.9).setFill()
    for k in 0..<2 {
        rrect(NSRect(x: board.minX + s * 0.05,
                     y: board.minY + s * (0.08 + 0.09 * CGFloat(k)),
                     width: s * 0.30 - s * 0.10 * CGFloat(k),
                     height: s * 0.03), s * 0.015).fill()
    }

    // Верхняя планка в диагональную полоску, приоткрытая под углом.
    ctx.saveGraphicsState()
    let rot = NSAffineTransform()
    rot.translateX(by: board.minX, yBy: board.maxY + s * 0.015)
    rot.rotate(byDegrees: 14)
    rot.concat()
    let stick = NSRect(x: 0, y: 0, width: board.width, height: s * 0.10)
    rrect(stick, s * 0.03).addClip()
    srgb(0.12, 0.12, 0.15).setFill()
    NSBezierPath(rect: stick).fill()
    srgb(1, 1, 1, 0.95).setFill()
    var x: CGFloat = -s * 0.02
    while x < stick.width {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x, y: 0))
        p.line(to: NSPoint(x: x + s * 0.07, y: 0))
        p.line(to: NSPoint(x: x + s * 0.11, y: stick.height))
        p.line(to: NSPoint(x: x + s * 0.04, y: stick.height))
        p.close()
        p.fill()
        x += s * 0.14
    }
    ctx.restoreGraphicsState()

    // Лёгкий блик по верху и тонкая кромка.
    NSGradient(colors: [srgb(1, 1, 1, 0.10), srgb(1, 1, 1, 0)])!.draw(in: body, angle: -90)
    ctx.restoreGraphicsState()

    srgb(0, 0, 0, 0.08).setStroke()
    let edge = rrect(body.insetBy(dx: s * 0.003, dy: s * 0.003), corner)
    edge.lineWidth = s * 0.006
    edge.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),      ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),      ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),   ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),   ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),   ("icon_512x512@2x.png", 1024),
]

for (name, px) in variants {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try! drawIcon(pixels: px).write(to: url)
}

print("Иконки (хлопушка) записаны в \(outDir)")
