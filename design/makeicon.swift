import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let S = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8,
                    bytesPerRow: 0, space: srgb,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// ── Background: deep navy → electric blue, light from top-right
let bg = CGGradient(colorsSpace: srgb,
                    colors: [c(0x0C1440), c(0x16309B), c(0x2B62DF), c(0x4C8DF2)] as CFArray,
                    locations: [0, 0.42, 0.78, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 60, y: 60), end: CGPoint(x: 1000, y: 1000), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// Cyan bloom at the light source
let bloom = CGGradient(colorsSpace: srgb,
                       colors: [c(0x9BE8FF, 0.4), c(0x9BE8FF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: 830, y: 860), startRadius: 0,
                       endCenter: CGPoint(x: 830, y: 860), endRadius: 620, options: [])

// ── Clean planar constellation: hero + 4, star-with-rim, no crossings
struct N { let x: CGFloat; let y: CGFloat; let r: CGFloat; let green: Bool }
let nodes: [N] = [
    N(x: 400, y: 465, r: 108, green: false),   // hero
    N(x: 728, y: 640, r: 72, green: true),     // known (accent)
    N(x: 668, y: 288, r: 52, green: false),
    N(x: 476, y: 810, r: 44, green: false),
    N(x: 205, y: 682, r: 30, green: false),
]
let edges: [(Int, Int, CGFloat)] = [
    (0, 1, 0.62), (0, 2, 0.48), (0, 3, 0.48), (0, 4, 0.40),
    (1, 2, 0.34), (1, 3, 0.34),
]

ctx.setLineCap(.round)
for (a, b, alpha) in edges {
    ctx.setStrokeColor(c(0xFFFFFF, alpha * 0.30)); ctx.setLineWidth(34)
    ctx.move(to: CGPoint(x: nodes[a].x, y: nodes[a].y))
    ctx.addLine(to: CGPoint(x: nodes[b].x, y: nodes[b].y)); ctx.strokePath()
    ctx.setStrokeColor(c(0xFFFFFF, alpha)); ctx.setLineWidth(13)
    ctx.move(to: CGPoint(x: nodes[a].x, y: nodes[a].y))
    ctx.addLine(to: CGPoint(x: nodes[b].x, y: nodes[b].y)); ctx.strokePath()
}

for n in nodes {
    let rect = CGRect(x: n.x - n.r, y: n.y - n.r, width: n.r * 2, height: n.r * 2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -6, height: -18), blur: 40, color: c(0x060C2E, 0.6))
    let sphere = n.green
        ? CGGradient(colorsSpace: srgb,
                     colors: [c(0x8CF0B8), c(0x3BBE7E), c(0x1E8354)] as CFArray,
                     locations: [0, 0.55, 1])!
        : CGGradient(colorsSpace: srgb,
                     colors: [c(0xFFFFFF), c(0xF0F6FF), c(0xB4CDF2)] as CFArray,
                     locations: [0, 0.5, 1])!
    ctx.addEllipse(in: rect); ctx.clip()
    // light from top-right → highlight offset that way
    ctx.drawRadialGradient(sphere,
                           startCenter: CGPoint(x: n.x + n.r * 0.35, y: n.y + n.r * 0.4), startRadius: 0,
                           endCenter: CGPoint(x: n.x, y: n.y), endRadius: n.r * 1.3, options: [])
    ctx.restoreGState()
    ctx.setFillColor(c(0xFFFFFF, n.green ? 0.85 : 0.9))
    let hr = n.r * 0.30
    ctx.fillEllipse(in: CGRect(x: n.x + n.r * 0.22, y: n.y + n.r * 0.34, width: hr, height: hr))
}

let img = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote")
