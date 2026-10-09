// Source of the app icon. Regenerate with:
//   swift design/AppIcon.swift icon_1024.png
// then resize into App/Assets.xcassets/AppIcon.appiconset (sips -z).

import AppKit
import CoreGraphics

// Draws the app icon at 1024×1024 following Apple's macOS icon grid:
// an 824-pt rounded square centered with room for the drop shadow.
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Soft drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(color(0x6CC3E8)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
// Sky: warm morning gradient.
let sky = CGGradient(colorsSpace: space, colors: [color(0xFFE6A8), color(0x8FD3F4), color(0x5BB5E8)] as CFArray, locations: [0, 0.45, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 300), end: CGPoint(x: 512, y: 924), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Rolling hills.
func hill(_ y: CGFloat, _ dip: CGFloat, _ top: UInt32, _ bottom: UInt32) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 80, y: 80))
    path.addLine(to: CGPoint(x: 80, y: y))
    path.addCurve(to: CGPoint(x: 944, y: y - dip), control1: CGPoint(x: 360, y: y + 120), control2: CGPoint(x: 680, y: y - dip - 90))
    path.addLine(to: CGPoint(x: 944, y: 80))
    path.closeSubpath()
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: y + 60), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()
}
hill(470, -60, 0x8DD35F, 0x5FAE3E)
hill(360, 40, 0x6CC04A, 0x3E8E2E)
ctx.restoreGState()

// Puzzle piece (a mod), cream with a soft shadow.
let piece = CGMutablePath()
let p = CGRect(x: 322, y: 230, width: 330, height: 300)
let r: CGFloat = 46
piece.move(to: CGPoint(x: p.minX + r, y: p.minY))
piece.addLine(to: CGPoint(x: p.maxX - r, y: p.minY))
piece.addArc(tangent1End: CGPoint(x: p.maxX, y: p.minY), tangent2End: CGPoint(x: p.maxX, y: p.minY + r), radius: r)
// right knob
piece.addLine(to: CGPoint(x: p.maxX, y: p.midY - 52))
piece.addCurve(to: CGPoint(x: p.maxX, y: p.midY + 52), control1: CGPoint(x: p.maxX + 110, y: p.midY - 92), control2: CGPoint(x: p.maxX + 110, y: p.midY + 92))
piece.addLine(to: CGPoint(x: p.maxX, y: p.maxY - r))
piece.addArc(tangent1End: CGPoint(x: p.maxX, y: p.maxY), tangent2End: CGPoint(x: p.maxX - r, y: p.maxY), radius: r)
// top knob (where the sprout grows)
piece.addLine(to: CGPoint(x: p.midX + 54, y: p.maxY))
piece.addCurve(to: CGPoint(x: p.midX - 54, y: p.maxY), control1: CGPoint(x: p.midX + 96, y: p.maxY + 112), control2: CGPoint(x: p.midX - 96, y: p.maxY + 112))
piece.addLine(to: CGPoint(x: p.minX + r, y: p.maxY))
piece.addArc(tangent1End: CGPoint(x: p.minX, y: p.maxY), tangent2End: CGPoint(x: p.minX, y: p.maxY - r), radius: r)
piece.addLine(to: CGPoint(x: p.minX, y: p.minY + r))
piece.addArc(tangent1End: CGPoint(x: p.minX, y: p.minY), tangent2End: CGPoint(x: p.minX + r, y: p.minY), radius: r)
piece.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x1F4D1A, 0.45))
ctx.addPath(piece); ctx.setFillColor(color(0xFFF3D6)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(piece); ctx.clip()
let cream = CGGradient(colorsSpace: space, colors: [color(0xFFFBEE), color(0xF4DFAE)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(cream, start: CGPoint(x: 400, y: 640), end: CGPoint(x: 600, y: 230), options: [])
ctx.restoreGState()
ctx.addPath(piece); ctx.setStrokeColor(color(0xC9A15A, 0.55)); ctx.setLineWidth(6); ctx.strokePath()

// Sprout: stem and two leaves.
let stemBase = CGPoint(x: p.midX, y: p.maxY + 70)
let stem = CGMutablePath()
stem.move(to: stemBase)
stem.addCurve(to: CGPoint(x: 498, y: 760), control1: CGPoint(x: 492, y: 640), control2: CGPoint(x: 512, y: 700))
ctx.addPath(stem); ctx.setStrokeColor(color(0x3E8E2E)); ctx.setLineWidth(30); ctx.setLineCap(.round); ctx.strokePath()

func leaf(from base: CGPoint, to tip: CGPoint, bulge: CGFloat, light: UInt32, dark: UInt32) {
    let dx = tip.x - base.x, dy = tip.y - base.y
    let normal = CGPoint(x: -dy, y: dx)
    let len = (normal.x * normal.x + normal.y * normal.y).squareRoot()
    let n = CGPoint(x: normal.x / len * bulge, y: normal.y / len * bulge)
    let mid1 = CGPoint(x: base.x + dx * 0.35, y: base.y + dy * 0.35)
    let mid2 = CGPoint(x: base.x + dx * 0.75, y: base.y + dy * 0.75)
    let path = CGMutablePath()
    path.move(to: base)
    path.addCurve(to: tip, control1: CGPoint(x: mid1.x + n.x, y: mid1.y + n.y), control2: CGPoint(x: mid2.x + n.x * 0.8, y: mid2.y + n.y * 0.8))
    path.addCurve(to: base, control1: CGPoint(x: mid2.x - n.x * 0.8, y: mid2.y - n.y * 0.8), control2: CGPoint(x: mid1.x - n.x, y: mid1.y - n.y))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: color(0x1F4D1A, 0.35))
    ctx.addPath(path); ctx.setFillColor(color(dark)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: [color(light), color(dark)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: base.x + n.x, y: base.y + n.y), end: CGPoint(x: base.x - n.x, y: base.y - n.y), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
    // midrib
    let rib = CGMutablePath(); rib.move(to: base)
    rib.addQuadCurve(to: CGPoint(x: base.x + dx * 0.85, y: base.y + dy * 0.85), control: CGPoint(x: mid1.x + n.x * 0.15, y: mid1.y + n.y * 0.15))
    ctx.addPath(rib); ctx.setStrokeColor(color(0xFFFFFF, 0.35)); ctx.setLineWidth(7); ctx.strokePath()
}
leaf(from: CGPoint(x: 500, y: 740), to: CGPoint(x: 330, y: 846), bulge: 70, light: 0x9BE36B, dark: 0x3F9A33)
leaf(from: CGPoint(x: 502, y: 748), to: CGPoint(x: 690, y: 872), bulge: -78, light: 0xA8EC72, dark: 0x45A637)

// A small golden star (stardrop sparkle).
func star(center c: CGPoint, outer: CGFloat, inner: CGFloat) {
    let path = CGMutablePath()
    for i in 0..<10 {
        let angle = CGFloat(i) * .pi / 5 + .pi / 2
        let radius = i % 2 == 0 ? outer : inner
        let point = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24, color: color(0xFFF2A8, 0.9))
    ctx.addPath(path); ctx.setFillColor(color(0xFFD23F)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(color(0xE0A100)); ctx.setLineWidth(5); ctx.setLineJoin(.round); ctx.strokePath()
}
star(center: CGPoint(x: 770, y: 790), outer: 62, inner: 27)

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(filePath: CommandLine.arguments[1]))
