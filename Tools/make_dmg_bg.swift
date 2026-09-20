import AppKit
import Foundation

// Фон для окна DMG: тёплый градиент, заголовок и стрелка от приложения к Applications.
// Использование: swift Tools/make_dmg_bg.swift <выходной .png> [масштаб]

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("Укажите путь к .png\n".data(using: .utf8)!)
    exit(1)
}
let outPath = CommandLine.arguments[1]
let scale = CommandLine.arguments.count > 2 ? CGFloat(Double(CommandLine.arguments[2]) ?? 1) : 1

// Размер окна DMG в точках — должен совпадать с --window-size в make_dmg.sh.
let W: CGFloat = 660, H: CGFloat = 400
// Центр иконок по вертикали, считая от верха окна (совпадает с --icon позициями).
let iconCY: CGFloat = 205

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                           pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
// Рисуем в точках, а не в пикселях — иначе при scale=2 всё уедет.
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Тёплый почти-белый градиент в тон иконке.
NSGradient(colors: [srgb(1.00, 0.992, 0.980), srgb(0.957, 0.945, 0.929)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

/// Рисует строку по центру; y отсчитывается от верхнего края окна.
func centered(_ text: String, font: NSFont, color: NSColor, top: CGFloat) {
    let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let size = str.size()
    str.draw(at: NSPoint(x: ((W - size.width) / 2).rounded(), y: H - top - size.height))
}

centered("StreamRecord",
         font: .systemFont(ofSize: 24, weight: .semibold),
         color: srgb(0.13, 0.13, 0.16), top: 46)
centered("Запись видео с USB-камеры",
         font: .systemFont(ofSize: 13, weight: .regular),
         color: srgb(0.46, 0.46, 0.52), top: 80)
centered("Перетащите приложение в папку Applications",
         font: .systemFont(ofSize: 13, weight: .medium),
         color: srgb(0.40, 0.40, 0.46), top: 330)

// Стрелка между иконками, на их линии по высоте.
let ay = H - iconCY
let x0: CGFloat = 280, x1: CGFloat = 380
srgb(1.0, 0.55, 0.20).setStroke()

let shaft = NSBezierPath()
shaft.lineWidth = 3
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: x0, y: ay))
shaft.line(to: NSPoint(x: x1 - 2, y: ay))
shaft.stroke()

let head = NSBezierPath()
head.lineWidth = 3
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.move(to: NSPoint(x: x1 - 13, y: ay + 9))
head.line(to: NSPoint(x: x1, y: ay))
head.line(to: NSPoint(x: x1 - 13, y: ay - 9))
head.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: outPath))
