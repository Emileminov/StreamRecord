import AppKit
import Foundation

// Обложка для публикации (Telegram и т.п.): 1280×720.
// Использование: swift Tools/make_cover.swift <выход.png> <AppIcon.icns>

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write("Нужны: <выход.png> <AppIcon.icns>\n".data(using: .utf8)!)
    exit(1)
}
let outPath = CommandLine.arguments[1]
let iconPath = CommandLine.arguments[2]

let W: CGFloat = 1280, H: CGFloat = 720

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func rrect(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad)
}
/// y отсчитывается от верхнего края холста.
func text(_ s: String, x: CGFloat, top: CGFloat, font: NSFont, color: NSColor) -> NSSize {
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    let size = str.size()
    str.draw(at: NSPoint(x: x, y: H - top - size.height))
    return size
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!

// --- Фон: почти чёрный с тёплым свечением справа ---
srgb(0.055, 0.055, 0.067).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// Свечения рисуем на весь холст, смещая центр: у градиента, вписанного в
// меньший прямоугольник, видны его края.
let canvas = NSRect(x: 0, y: 0, width: W, height: H)
NSGradient(colors: [srgb(1.0, 0.55, 0.20, 0.32), srgb(1.0, 0.55, 0.20, 0)])!
    .draw(in: canvas, relativeCenterPosition: NSPoint(x: 0.50, y: -0.05))
NSGradient(colors: [srgb(1.0, 0.78, 0.30, 0.10), srgb(1.0, 0.78, 0.30, 0)])!
    .draw(in: canvas, relativeCenterPosition: NSPoint(x: -0.80, y: 0.45))

// --- Локап: иконка + название в одну строку ---
let iconSide: CGFloat = 84
let iconTop: CGFloat = 150
if let icon = NSImage(contentsOfFile: iconPath) {
    icon.draw(in: NSRect(x: 88, y: H - iconTop - iconSide, width: iconSide, height: iconSide))
}
let titleFont = NSFont.systemFont(ofSize: 56, weight: .bold)
let titleH = NSAttributedString(string: "S", attributes: [.font: titleFont]).size().height
_ = text("StreamRecord", x: 88 + iconSide + 24,
         top: iconTop + (iconSide - titleH) / 2,
         font: titleFont, color: .white)

// --- Подзаголовок ---
let subFont = NSFont.systemFont(ofSize: 30, weight: .regular)
let subColor = srgb(0.78, 0.78, 0.82)
_ = text("Записывайте с любой камеры —", x: 88, top: 296, font: subFont, color: subColor)
_ = text("от беззеркалки до iPhone", x: 88, top: 340, font: subFont, color: subColor)

// --- Плашки с возможностями ---
func chip(_ label: String, x: CGFloat, top: CGFloat) -> CGFloat {
    let font = NSFont.systemFont(ofSize: 17, weight: .medium)
    let str = NSAttributedString(string: label, attributes: [
        .font: font, .foregroundColor: srgb(0.93, 0.93, 0.95)])
    let size = str.size()
    let padX: CGFloat = 18, h: CGFloat = 40
    let box = NSRect(x: x, y: H - top - h, width: size.width + padX * 2, height: h)
    srgb(1, 1, 1, 0.07).setFill()
    rrect(box, h / 2).fill()
    srgb(1, 1, 1, 0.13).setStroke()
    let border = rrect(box.insetBy(dx: 0.5, dy: 0.5), h / 2)
    border.lineWidth = 1
    border.stroke()
    str.draw(at: NSPoint(x: box.minX + padX, y: box.midY - size.height / 2))
    return box.maxX + 12
}
var cx = chip("9:16 для рилсов", x: 88, top: 440)
cx = chip("Звук отдельным .wav", x: cx, top: 440)
_ = chip("Без перекодирования", x: cx, top: 440)

// --- Макет приложения: вертикальный кадр с сеткой и кнопкой записи ---
let mock = NSRect(x: 830, y: 94, width: 300, height: 533)

ctx.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
srgb(0.10, 0.10, 0.12).setFill()
rrect(mock, 28).fill()
ctx.restoreGraphicsState()

ctx.saveGraphicsState()
rrect(mock, 28).addClip()

// «Видео» — приглушённый тёплый градиент вместо кадра.
NSGradient(colors: [srgb(0.22, 0.20, 0.24), srgb(0.10, 0.10, 0.13)])!.draw(in: mock, angle: -70)
NSGradient(colors: [srgb(1.0, 0.55, 0.20, 0.18), srgb(1.0, 0.55, 0.20, 0)])!
    .draw(in: NSRect(x: mock.minX - 40, y: mock.midY - 60, width: 380, height: 380),
          relativeCenterPosition: .zero)

// Сетка третей.
srgb(0.92, 0.92, 0.92, 0.28).setStroke()
let grid = NSBezierPath()
grid.lineWidth = 1
for i in 1...2 {
    let gx = mock.minX + mock.width * CGFloat(i) / 3
    let gy = mock.minY + mock.height * CGFloat(i) / 3
    grid.move(to: NSPoint(x: gx, y: mock.minY)); grid.line(to: NSPoint(x: gx, y: mock.maxY))
    grid.move(to: NSPoint(x: mock.minX, y: gy)); grid.line(to: NSPoint(x: mock.maxX, y: gy))
}
grid.stroke()

// Затемнение у нижнего края, как в самом приложении.
NSGradient(colors: [srgb(0, 0, 0, 0.62), srgb(0, 0, 0, 0)])!
    .draw(in: NSRect(x: mock.minX, y: mock.minY, width: mock.width, height: 170), angle: 90)

// Кнопка записи с кольцевым индикатором.
let bc = NSPoint(x: mock.midX, y: mock.minY + 86)
let btnD: CGFloat = 56
let ringR = btnD / 2 + 11
let ringW: CGFloat = 5

let track = NSBezierPath(ovalIn: NSRect(x: bc.x - ringR, y: bc.y - ringR,
                                        width: ringR * 2, height: ringR * 2))
track.lineWidth = ringW
srgb(1, 1, 1, 0.20).setStroke()
track.stroke()

// Заполнение от 6 часов по часовой стрелке — как в приложении.
let level = 0.46
let arc = NSBezierPath()
let steps = 80
for i in 0...steps {
    let phi = Double.pi + level * 2 * Double.pi * Double(i) / Double(steps)
    let p = NSPoint(x: bc.x + ringR * CGFloat(sin(phi)), y: bc.y + ringR * CGFloat(cos(phi)))
    if i == 0 { arc.move(to: p) } else { arc.line(to: p) }
}
arc.lineWidth = ringW
arc.lineCapStyle = .round
NSColor.systemGreen.setStroke()
arc.stroke()

let btn = NSRect(x: bc.x - btnD / 2, y: bc.y - btnD / 2, width: btnD, height: btnD)
NSColor.systemRed.setFill()
NSBezierPath(ovalIn: btn).fill()
srgb(1, 1, 1, 0.95).setStroke()
let innerRing = NSBezierPath(ovalIn: btn.insetBy(dx: btnD * 0.07, dy: btnD * 0.07))
innerRing.lineWidth = 3
innerRing.stroke()
NSColor.white.setFill()
let dot = btnD * 0.44
NSBezierPath(ovalIn: NSRect(x: bc.x - dot / 2, y: bc.y - dot / 2, width: dot, height: dot)).fill()

// Плашка таймера слева от кнопки.
let pillW: CGFloat = 74, pillH: CGFloat = 26
let pill = NSRect(x: bc.x - ringR - 12 - pillW, y: bc.y - pillH / 2, width: pillW, height: pillH)
srgb(0, 0, 0, 0.45).setFill()
rrect(pill, 9).fill()
let timerFont = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
let timer = NSAttributedString(string: "00:12", attributes: [
    .font: timerFont, .foregroundColor: NSColor.white])
let ts = timer.size()
timer.draw(at: NSPoint(x: pill.midX - ts.width / 2, y: pill.midY - ts.height / 2))

ctx.restoreGraphicsState()

// Тонкая кромка макета.
srgb(1, 1, 1, 0.10).setStroke()
let edge = rrect(mock.insetBy(dx: 0.5, dy: 0.5), 28)
edge.lineWidth = 1
edge.stroke()

// --- Подпись внизу ---
_ = text("для macOS", x: 88, top: 596,
         font: .systemFont(ofSize: 18, weight: .medium), color: srgb(0.55, 0.55, 0.60))

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: outPath))
print("Обложка записана: \(outPath)")
