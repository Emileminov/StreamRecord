import AppKit
import Foundation

// 6 вариантов иконки: ПРОЗРАЧНОЕ стекло (Liquid Glass). Стеклянные формы лежат поверх цветной подложки,
// подложка видна сквозь стекло с лёгким увеличением (преломление), по краям внутренняя тень и яркие кромки.
// Использование: swift Tools/make_icon_variants.swift <папка>   (кладёт v1…v6.png и sheet.png)

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
func w(_ a: CGFloat) -> NSColor { c(1, 1, 1, a) }
func rrect(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }
func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSBezierPath { NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)) }
func glow(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ col: NSColor) {
    NSGradient(colors: [col, col.withAlphaComponent(0)])!.draw(fromCenter: NSPoint(x: cx, y: cy), radius: 0, toCenter: NSPoint(x: cx, y: cy), radius: r, options: [])
}
func clipped(_ p: NSBezierPath, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState(); p.addClip(); body(); NSGraphicsContext.restoreGraphicsState()
}
func outsideOf(_ p: NSBezierPath, _ b: NSRect) -> NSBezierPath {
    let o = NSBezierPath(rect: b.insetBy(dx: -b.width, dy: -b.height)); o.append(p); o.windingRule = .evenOdd; return o
}
func newRep(_ px: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

struct Palette { var base: [NSColor]; var blobs: [(CGFloat, CGFloat, CGFloat, NSColor)] }   // x,y,r в долях s

func backdrop(_ s: CGFloat, _ pal: Palette, in rect: NSRect) {
    NSGradient(colors: pal.base)!.draw(in: rect, angle: -90)
    for (x, y, r, col) in pal.blobs { glow(rect.minX + x * rect.width, rect.minY + y * rect.height, r * s, col) }
}

/// Прозрачное стекло: подложка внутри формы чуть увеличена, внутренняя тень/свет по краю, блик, яркая кромка.
func clearGlass(_ p: NSBezierPath, _ b: NSRect, _ img: NSBitmapImageRep, _ s: CGFloat, zoom: CGFloat = 1.10,
                tint: NSColor? = nil, rim: CGFloat = 0.006, depth: CGFloat = 1) {
    // тень снаружи
    clipped(outsideOf(p, b)) {
        let sh = NSShadow(); sh.shadowColor = c(0, 0, 0, 0.5); sh.shadowBlurRadius = s * 0.035; sh.shadowOffset = NSSize(width: 0, height: -s * 0.015); sh.set()
        c(0, 0, 0).setFill(); p.fill()
    }
    clipped(p) {
        // преломление: подложка с увеличением вокруг центра формы
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        ctx.translateBy(x: b.midX, y: b.midY); ctx.scaleBy(x: zoom, y: zoom); ctx.translateBy(x: -b.midX, y: -b.midY)
        img.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
        ctx.restoreGState()
        if let t = tint { t.setFill(); p.fill() }
        w(0.07).setFill(); p.fill()
        // внутренняя тень по краю (объём)
        let o = outsideOf(p, b)
        NSGraphicsContext.saveGraphicsState(); o.addClip()
        let s1 = NSShadow(); s1.shadowColor = c(0, 0, 0, 0.55 * depth); s1.shadowBlurRadius = s * 0.03; s1.shadowOffset = NSSize(width: s * 0.008, height: -s * 0.012); s1.set()
        c(0, 0, 0).setFill(); p.fill()
        NSGraphicsContext.restoreGraphicsState()
        // внутренний свет у верхне-левой кромки
        NSGraphicsContext.saveGraphicsState(); o.addClip()
        let s2 = NSShadow(); s2.shadowColor = w(0.65); s2.shadowBlurRadius = s * 0.012; s2.shadowOffset = NSSize(width: -s * 0.006, height: s * 0.008); s2.set()
        c(0, 0, 0).setFill(); p.fill()
        NSGraphicsContext.restoreGraphicsState()
        // глянцевый блик в верхней части
        NSGradient(colors: [w(0.30), w(0.0)])!.draw(in: NSRect(x: b.minX, y: b.midY + b.height * 0.05, width: b.width, height: b.height * 0.45), angle: -90)
        // мягкий отсвет по нижней кромке
        NSGradient(colors: [w(0.0), w(0.16)])!.draw(in: NSRect(x: b.minX, y: b.minY, width: b.width, height: b.height * 0.25), angle: -90)
    }
    // кромка: ярче сверху-слева и чуть снизу-справа
    let ring = NSBezierPath(); ring.append(p)
    let t = NSAffineTransform(); t.translateX(by: b.midX, yBy: b.midY)
    t.scaleX(by: (b.width - 2 * s * rim) / b.width, yBy: (b.height - 2 * s * rim) / b.height); t.translateX(by: -b.midX, yBy: -b.midY)
    ring.append(t.transform(p)); ring.windingRule = .evenOdd
    clipped(ring) { NSGradient(colors: [w(1.0), w(0.12), w(0.12), w(0.6)], atLocations: [0, 0.35, 0.65, 1], colorSpace: .sRGB)!.draw(in: b, angle: -55) }
}

func drawVariant(_ v: Int, pixels: Int) -> NSBitmapImageRep {
    let s = CGFloat(pixels), m = s / 2
    let body = NSRect(x: s * 0.055, y: s * 0.055, width: s * 0.89, height: s * 0.89)
    let plate = rrect(body, body.width * 0.2237)
    let red = c(1.0, 0.22, 0.25)

    let pals: [Palette] = [
        Palette(base: [c(0.10, 0.10, 0.16), c(0.03, 0.03, 0.07)], blobs: [(0.25, 0.75, 0.55, c(0.2, 0.4, 1, 0.75)), (0.8, 0.25, 0.55, c(0.95, 0.2, 0.6, 0.65)), (0.7, 0.8, 0.3, c(0.6, 0.3, 1, 0.4))]),
        Palette(base: [c(0.03, 0.10, 0.14), c(0.01, 0.03, 0.06)], blobs: [(0.3, 0.7, 0.6, c(0.1, 0.8, 0.8, 0.7)), (0.8, 0.3, 0.55, c(0.15, 0.35, 1, 0.7)), (0.2, 0.2, 0.3, c(0.4, 0.9, 0.6, 0.35))]),
        Palette(base: [c(0.14, 0.07, 0.07), c(0.05, 0.02, 0.04)], blobs: [(0.25, 0.75, 0.55, c(1, 0.55, 0.1, 0.75)), (0.8, 0.3, 0.6, c(0.95, 0.15, 0.45, 0.7)), (0.5, 0.15, 0.3, c(0.7, 0.2, 1, 0.4))]),
        Palette(base: [c(0.09, 0.07, 0.16), c(0.03, 0.02, 0.07)], blobs: [(0.3, 0.8, 0.55, c(0.55, 0.3, 1, 0.75)), (0.75, 0.25, 0.55, c(0.2, 0.55, 1, 0.7)), (0.2, 0.25, 0.3, c(1, 0.4, 0.8, 0.4))]),
        Palette(base: [c(0.13, 0.05, 0.07), c(0.04, 0.01, 0.03)], blobs: [(0.3, 0.75, 0.55, c(1, 0.25, 0.3, 0.75)), (0.8, 0.25, 0.5, c(1, 0.5, 0.15, 0.6)), (0.5, 0.5, 0.3, c(0.8, 0.2, 0.7, 0.35))]),
        Palette(base: [c(0.22, 0.24, 0.30), c(0.07, 0.08, 0.12)], blobs: [(0.2, 0.8, 0.6, c(0.3, 0.6, 1, 0.8)), (0.85, 0.2, 0.6, c(1, 0.35, 0.65, 0.75)), (0.6, 0.55, 0.35, c(1, 0.7, 0.3, 0.45))]),
    ]
    let pal = pals[v - 1]

    // подложка рисуется в отдельную картинку — чтобы стекло могло её «преломлять»
    let bd = newRep(pixels)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bd)
    backdrop(s, pal, in: NSRect(x: 0, y: 0, width: s, height: s))
    NSGraphicsContext.restoreGraphicsState()

    let rep = newRep(pixels)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // плитка с подложкой
    clipped(outsideOf(plate, body)) {
        let sh = NSShadow(); sh.shadowColor = c(0, 0, 0, 0.5); sh.shadowBlurRadius = s * 0.03; sh.shadowOffset = NSSize(width: 0, height: -s * 0.012); sh.set()
        c(0, 0, 0).setFill(); plate.fill()
    }
    clipped(plate) { bd.draw(in: NSRect(x: 0, y: 0, width: s, height: s)) }
    let plateRing = NSBezierPath(); plateRing.append(plate)
    plateRing.append(rrect(body.insetBy(dx: s * 0.004, dy: s * 0.004), body.width * 0.2237 - s * 0.004)); plateRing.windingRule = .evenOdd
    clipped(plateRing) { NSGradient(colors: [w(0.7), w(0.08), w(0.3)])!.draw(in: body, angle: -60) }

    clipped(plate) {
        switch v {
        case 1: // стеклянное кольцо объектива + красная стеклянная точка
            let R = s * 0.27
            let ring = NSBezierPath(); ring.append(circle(m, m, R)); ring.append(circle(m, m, R - s * 0.075)); ring.windingRule = .evenOdd
            clearGlass(ring, NSRect(x: m - R, y: m - R, width: R * 2, height: R * 2), bd, s, zoom: 1.12)
            let d = circle(m, m, s * 0.085)
            clearGlass(d, d.bounds, bd, s, zoom: 1.4, tint: red.withAlphaComponent(0.55))
        case 2: // большой стеклянный шар-линза
            let r = s * 0.28
            clearGlass(circle(m, m, r), NSRect(x: m - r, y: m - r, width: r * 2, height: r * 2), bd, s, zoom: 1.35, depth: 1.2)
        case 3: // стеклянная хлопушка
            let board = NSRect(x: m - s * 0.27, y: m - s * 0.25, width: s * 0.54, height: s * 0.34)
            clearGlass(rrect(board, s * 0.045), board, bd, s, zoom: 1.12)
            let tr = NSAffineTransform(); tr.translateX(by: board.minX, yBy: board.maxY + s * 0.025); tr.rotate(byDegrees: 12)
            let sp = tr.transform(rrect(NSRect(x: 0, y: 0, width: board.width, height: s * 0.10), s * 0.028))
            clearGlass(sp, sp.bounds, bd, s, zoom: 1.2)
        case 4: // стеклянная видеокамера
            let bodyR = NSRect(x: m - s * 0.31, y: m - s * 0.17, width: s * 0.44, height: s * 0.34)
            clearGlass(rrect(bodyR, s * 0.075), bodyR, bd, s, zoom: 1.15)
            let tri = NSBezierPath(); tri.move(to: NSPoint(x: m + s * 0.17, y: m)); tri.line(to: NSPoint(x: m + s * 0.32, y: m + s * 0.11)); tri.line(to: NSPoint(x: m + s * 0.32, y: m - s * 0.11)); tri.close(); tri.lineJoinStyle = .round
            clearGlass(tri, tri.bounds, bd, s, zoom: 1.2)
        case 5: // кнопка записи: кольцо + красный стеклянный шар
            let R = s * 0.30
            let ring = NSBezierPath(); ring.append(circle(m, m, R)); ring.append(circle(m, m, R - s * 0.05)); ring.windingRule = .evenOdd
            clearGlass(ring, NSRect(x: m - R, y: m - R, width: R * 2, height: R * 2), bd, s, zoom: 1.10)
            let r = s * 0.19
            clearGlass(circle(m, m, r), NSRect(x: m - r, y: m - r, width: r * 2, height: r * 2), bd, s, zoom: 1.3, tint: red.withAlphaComponent(0.55), depth: 1.2)
        default: // большая стеклянная плита на ярких обоях, внутри кольцо объектива
            let slab = body.insetBy(dx: s * 0.10, dy: s * 0.10)
            clearGlass(rrect(slab, slab.width * 0.24), slab, bd, s, zoom: 1.06, rim: 0.009)
            let R = s * 0.20
            let ring = NSBezierPath(); ring.append(circle(m, m, R)); ring.append(circle(m, m, R - s * 0.05)); ring.windingRule = .evenOdd
            clearGlass(ring, NSRect(x: m - R, y: m - R, width: R * 2, height: R * 2), bd, s, zoom: 1.2)
            let d = circle(m, m, s * 0.055)
            clearGlass(d, d.bounds, bd, s, zoom: 1.4, tint: red.withAlphaComponent(0.6))
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = CommandLine.arguments.count >= 2 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1560, pixelsHigh: 1040, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSGradient(colors: [c(0.62, 0.64, 0.70), c(0.38, 0.40, 0.46)])!.draw(in: NSRect(x: 0, y: 0, width: 1560, height: 1040), angle: -90)
NSGraphicsContext.restoreGraphicsState()
for v in 1...6 {
    try! drawVariant(v, pixels: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/v\(v).png"))
    let small = drawVariant(v, pixels: 500)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
    let col = (v - 1) % 3, row = (v - 1) / 3
    small.draw(in: NSRect(x: 20 + col * 520, y: 20 + (1 - row) * 520, width: 500, height: 500))
    NSGraphicsContext.restoreGraphicsState()
}
try! sheet.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/sheet.png"))
