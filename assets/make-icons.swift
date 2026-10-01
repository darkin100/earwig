// Renders Earwig's icons from code so they can be regenerated and tweaked:
//   assets/AppIcon.icns        — the app icon (Finder, dialogs, permission prompts)
//   assets/MenuBarIcon*.png    — the idle menu bar glyph (a template image)
// Run from the repo root:  swift assets/make-icons.swift
// (needs the same SDKROOT pin as build.sh on this toolchain)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Shapes (drawn in a 1024×1024, y-down design space)

/// The ear: an outer helix curling into the lobe, plus the inner fold.
func earPaths() -> (helix: CGPath, fold: CGPath) {
    let helix = CGMutablePath()
    helix.move(to: CGPoint(x: 418, y: 500))
    helix.addCurve(to: CGPoint(x: 560, y: 282),
                   control1: CGPoint(x: 404, y: 370), control2: CGPoint(x: 470, y: 282))
    helix.addCurve(to: CGPoint(x: 706, y: 452),
                   control1: CGPoint(x: 650, y: 282), control2: CGPoint(x: 706, y: 358))
    helix.addCurve(to: CGPoint(x: 612, y: 628),
                   control1: CGPoint(x: 706, y: 540), control2: CGPoint(x: 648, y: 578))
    helix.addCurve(to: CGPoint(x: 548, y: 742),
                   control1: CGPoint(x: 580, y: 672), control2: CGPoint(x: 590, y: 720))
    helix.addCurve(to: CGPoint(x: 452, y: 716),
                   control1: CGPoint(x: 510, y: 762), control2: CGPoint(x: 470, y: 748))

    let fold = CGMutablePath()
    fold.move(to: CGPoint(x: 500, y: 470))
    fold.addCurve(to: CGPoint(x: 568, y: 390),
                  control1: CGPoint(x: 500, y: 424), control2: CGPoint(x: 530, y: 390))
    fold.addCurve(to: CGPoint(x: 624, y: 456),
                  control1: CGPoint(x: 604, y: 390), control2: CGPoint(x: 624, y: 420))
    fold.addCurve(to: CGPoint(x: 560, y: 540),
                  control1: CGPoint(x: 624, y: 500), control2: CGPoint(x: 588, y: 516))
    return (helix, fold)
}

/// Sound arriving at the ear: three arcs opening toward it.
func wavePaths() -> [CGPath] {
    let center = CGPoint(x: 470, y: 520)
    return [150.0, 225.0, 300.0].map { radius in
        let p = CGMutablePath()
        p.addArc(center: center, radius: radius,
                 startAngle: .pi * 0.84, endAngle: .pi * 1.16, clockwise: false)
        return p
    }
}

/// macOS-style rounded square (continuous-ish corners via a superellipse).
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n = 5.0, steps = 360
    let a = rect.width / 2, b = rect.height / 2
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * copysign(pow(abs(c), 2 / n), c)
        let y = rect.midY + b * copysign(pow(abs(s), 2 / n), s)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// MARK: - Rendering

func makeContext(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip to the y-down design space and scale 1024 → size.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    return ctx
}

func strokeEar(_ ctx: CGContext, width: CGFloat) {
    let ear = earPaths()
    ctx.setLineWidth(width)
    ctx.addPath(ear.helix); ctx.strokePath()
    ctx.setLineWidth(width * 0.82)
    ctx.addPath(ear.fold); ctx.strokePath()
}

func appIcon(_ size: Int) -> CGImage {
    let ctx = makeContext(size)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: tile)

    // Drop shadow under the tile, as macOS icons have.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x1B1D45)); ctx.fillPath()
    ctx.restoreGState()

    // Background: deep indigo, lighter at the top.
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [rgb(0x4B4FC4), rgb(0x1B1D45)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // Soft glow behind the ear.
    let glow = CGGradient(colorsSpace: nil, colors: [rgb(0x8B8FFF, 0.35), rgb(0x8B8FFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 580, y: 500), startRadius: 0,
                           endCenter: CGPoint(x: 580, y: 500), endRadius: 360, options: [])

    // Centre the ear-and-waves group on the tile.
    ctx.translateBy(x: 40, y: 0)

    // Sound waves: amber nearest the ear, warming to coral and rose.
    for (i, wave) in wavePaths().enumerated() {
        ctx.setStrokeColor(rgb([0xFFC247, 0xFF8A5C, 0xE8618C][i]))
        ctx.setLineWidth(34)
        ctx.addPath(wave); ctx.strokePath()
    }

    // The ear, with a subtle shadow for depth.
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: rgb(0x000000, 0.3))
    ctx.setStrokeColor(rgb(0xF7F3EA))
    strokeEar(ctx, width: 58)
    ctx.restoreGState()

    // Hairline highlight on the tile edge.
    ctx.addPath(shape)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.12)); ctx.setLineWidth(3); ctx.strokePath()
    return ctx.makeImage()!
}

/// Menu bar glyph: the ear alone, black on clear (used as a template image).
func menuBarIcon(_ size: Int) -> CGImage {
    let ctx = makeContext(size)
    // Scale the ear up to fill the small canvas.
    ctx.translateBy(x: 512, y: 512)
    ctx.scaleBy(x: 1.9, y: 1.9)
    ctx.translateBy(x: -560, y: -512)
    ctx.setStrokeColor(rgb(0x000000))
    strokeEar(ctx, width: 60)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(path)") }
}

// MARK: - Main

let assets = URL(fileURLWithPath: "assets")
let iconset = assets.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(appIcon(base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png").path)
    writePNG(appIcon(base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png").path)
}
writePNG(appIcon(1024), to: assets.appendingPathComponent("AppIcon-preview.png").path)
writePNG(menuBarIcon(18), to: assets.appendingPathComponent("MenuBarIcon.png").path)
writePNG(menuBarIcon(36), to: assets.appendingPathComponent("MenuBarIcon@2x.png").path)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Wrote assets/AppIcon.icns and menu bar icons" : "iconutil failed")
