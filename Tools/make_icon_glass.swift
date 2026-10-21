import AppKit
import Foundation

// Иконка «тёмное стекло»: объектив-стеклянный шар с неоновым свечением и красной точкой REC.
// Использование: swift Tools/make_icon_glass.swift <путь к .iconset | файл.png>

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func rrect(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }
func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
}
func glow(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ col: NSColor) {
    NSGradient(colors: [col, col.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: cx, y: cy), radius: 0, toCenter: NSPoint(x: cx, y: cy), radius: r, options: [])
}

func drawIcon(pixels: Int) -> Data {
    let s = CGFloat(pixels)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let body = NSRect(x: s * 0.055, y: s * 0.055, width: s * 0.89, height: s * 0.89)
    let bodyPath = rrect(body, body.width * 0.2237)
    let mx = s / 2, my = s / 2

    // Мягкая тень под плиткой.
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = c(0, 0, 0, 0.5); sh.shadowBlurRadius = s * 0.025
    sh.shadowOffset = NSSize(width: 0, height: -s * 0.012); sh.set()
    c(0.08, 0.07, 0.11).setFill(); bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    // Тёмное матовое стекло с цветными «пятнами» за ним (как размытый фон).
    NSGradient(colors: [c(0.16, 0.16, 0.19), c(0.07, 0.07, 0.09)])!.draw(in: body, angle: -90)
    glow(body.minX + s * 0.18, body.maxY - s * 0.15, s * 0.5, c(0.35, 0.45, 1.0, 0.35))
    glow(body.maxX - s * 0.10, body.minY + s * 0.15, s * 0.5, c(1.0, 0.3, 0.7, 0.32))
    glow(body.maxX - s * 0.20, body.maxY - s * 0.20, s * 0.3, c(1.0, 0.6, 0.2, 0.18))
    // Широкий стеклянный блик сверху-слева.
    let sheen = NSBezierPath()
    sheen.move(to: NSPoint(x: body.minX, y: body.maxY))
    sheen.line(to: NSPoint(x: body.maxX * 0.82, y: body.maxY))
    sheen.curve(to: NSPoint(x: body.minX, y: body.maxY - body.height * 0.52),
                controlPoint1: NSPoint(x: body.maxX * 0.55, y: body.maxY - body.height * 0.22),
                controlPoint2: NSPoint(x: body.minX + body.width * 0.30, y: body.maxY - body.height * 0.42))
    sheen.close()
    NSGraphicsContext.saveGraphicsState()
    sheen.addClip()
    NSGradient(colors: [c(1, 1, 1, 0.26), c(1, 1, 1, 0.03)])!.draw(in: body, angle: -60)
    NSGraphicsContext.restoreGraphicsState()

    // --- Кольцо объектива: толстое стеклянное, цветной градиент ---
    let R = s * 0.285, lx = mx, ly = my - s * 0.01
    glow(lx, ly, R * 1.6, c(0.45, 0.4, 1.0, 0.20))
    let ringW = s * 0.075
    let ring = NSBezierPath()
    ring.append(circle(lx, ly, R)); ring.append(circle(lx, ly, R - ringW)); ring.windingRule = .evenOdd
    NSGraphicsContext.saveGraphicsState()
    let rsh = NSShadow(); rsh.shadowColor = c(0, 0, 0, 0.55); rsh.shadowBlurRadius = s * 0.03
    rsh.shadowOffset = NSSize(width: 0, height: -s * 0.012); rsh.set()
    c(0.5, 0.5, 0.6).setFill(); ring.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    ring.addClip()
    NSGradient(colors: [c(1.0, 0.62, 0.15), c(1.0, 0.30, 0.65), c(0.62, 0.38, 1.0), c(0.20, 0.55, 1.0), c(0.25, 0.85, 1.0)])!
        .draw(in: NSRect(x: lx - R, y: ly - R, width: R * 2, height: R * 2), angle: -45)
    // стеклянный блик на кольце (верх) и тёмная кромка низа
    NSGradient(colors: [c(1, 1, 1, 0.55), c(1, 1, 1, 0)])!
        .draw(in: NSRect(x: lx - R, y: ly + R * 0.25, width: R * 2, height: R * 0.8), angle: -90)
    NSGradient(colors: [c(0, 0, 0, 0), c(0, 0, 0, 0.30)])!
        .draw(in: NSRect(x: lx - R, y: ly - R, width: R * 2, height: R * 0.8), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    let ringHi = circle(lx, ly, R - s * 0.004); ringHi.lineWidth = s * 0.004
    c(1, 1, 1, 0.55).setStroke(); ringHi.stroke()

    // --- Стеклянная линза внутри кольца ---
    let r2 = R - ringW - s * 0.012
    NSGradient(colors: [c(0.10, 0.10, 0.16), c(0.01, 0.01, 0.03)])!.draw(in: circle(lx, ly, r2), angle: -90)
    NSGraphicsContext.saveGraphicsState()
    circle(lx, ly, r2).addClip()
    glow(lx + r2 * 0.40, ly + r2 * 0.40, r2 * 0.95, c(0.20, 0.55, 1.0, 0.85))
    glow(lx - r2 * 0.40, ly - r2 * 0.42, r2 * 0.85, c(1.0, 0.25, 0.75, 0.75))
    let inner = circle(lx, ly, r2 * 0.55); inner.lineWidth = s * 0.005
    c(1, 1, 1, 0.30).setStroke(); inner.stroke()
    NSGradient(colors: [c(0, 0, 0.03, 0.95), c(0.03, 0.04, 0.10, 0.9)])!.draw(in: circle(lx, ly, r2 * 0.30), angle: -90)
    glow(lx + r2 * 0.08, ly + r2 * 0.10, r2 * 0.17, c(0.7, 0.85, 1.0, 0.6))
    // большой стеклянный блик-полумесяц
    NSGradient(colors: [c(1, 1, 1, 0.50), c(1, 1, 1, 0.0)])!
        .draw(in: NSRect(x: lx - r2, y: ly + r2 * 0.1, width: r2 * 2, height: r2 * 0.95), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    let lrim = circle(lx, ly, r2); lrim.lineWidth = s * 0.004
    c(1, 1, 1, 0.35).setStroke(); lrim.stroke()

    // --- Красная точка REC ---
    let rx = body.maxX - s * 0.155, ry = body.maxY - s * 0.155, rr = s * 0.045
    glow(rx, ry, rr * 2.6, c(1.0, 0.15, 0.2, 0.45))
    NSGradient(colors: [c(1.0, 0.45, 0.45), c(0.9, 0.05, 0.12)])!.draw(in: circle(rx, ry, rr), angle: -90)

    NSGraphicsContext.restoreGraphicsState() // clip

    // Стеклянная кромка плитки: светлый верх → тёмный низ.
    NSGraphicsContext.saveGraphicsState()
    // обводка градиентом: рисуем кольцо как разность клипов
    let edgeRing = NSBezierPath(); edgeRing.append(bodyPath); edgeRing.append(rrect(body.insetBy(dx: s * 0.010, dy: s * 0.010), body.width * 0.2237 - s * 0.010)); edgeRing.windingRule = .evenOdd
    edgeRing.addClip()
    NSGradient(colors: [c(1, 1, 1, 0.9), c(1, 1, 1, 0.18), c(1.0, 0.55, 0.85, 0.55)])!.draw(in: body, angle: -60)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count >= 2 ? CommandLine.arguments[1] : "icon-glass.png"
if out.hasSuffix(".png") {
    try! drawIcon(pixels: 1024).write(to: URL(fileURLWithPath: out))
} else {
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        try! drawIcon(pixels: base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
        try! drawIcon(pixels: base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
    }
}
