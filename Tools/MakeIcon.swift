import AppKit
// Usage: icon4 <out.png> <light|dark|tinted>
let out = CommandLine.arguments[1], mode = CommandLine.arguments[2]
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff)/255, green: CGFloat((hex >> 8) & 0xff)/255, blue: CGFloat(hex & 0xff)/255, alpha: a)
}
func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }

// ---- Side-view small convertible, as an alpha mask ----
let m = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
m.setFillColor(c(0xFFFFFF)); m.setStrokeColor(c(0xFFFFFF))
let wheelY: CGFloat = 345, rearX: CGFloat = 300, frontX: CGFloat = 726, wheelR: CGFloat = 84

// Body: short with wheels at the corners; rounded tail, flat beltline, hood sloping down to a round nose
let body = CGMutablePath()
body.move(to: CGPoint(x: 198, y: 400))
body.addLine(to: CGPoint(x: 198, y: 470))
body.addCurve(to: CGPoint(x: 290, y: 556), control1: CGPoint(x: 198, y: 530), control2: CGPoint(x: 235, y: 556))
body.addLine(to: CGPoint(x: 640, y: 556))
body.addCurve(to: CGPoint(x: 820, y: 512), control1: CGPoint(x: 720, y: 556), control2: CGPoint(x: 790, y: 540))   // hood slopes down
body.addCurve(to: CGPoint(x: 842, y: 400), control1: CGPoint(x: 850, y: 485), control2: CGPoint(x: 850, y: 430))  // round nose
body.addCurve(to: CGPoint(x: 795, y: 360), control1: CGPoint(x: 838, y: 375), control2: CGPoint(x: 820, y: 360))
body.addLine(to: CGPoint(x: 240, y: 360))
body.addCurve(to: CGPoint(x: 198, y: 400), control1: CGPoint(x: 212, y: 360), control2: CGPoint(x: 198, y: 375))
body.closeSubpath()
m.addPath(body); m.setLineWidth(24); m.setLineJoin(.round); m.drawPath(using: .fillStroke)

// Two short headrests (rear and front seats)
m.addPath(rr(CGRect(x: 330, y: 540, width: 56, height: 74), 28)); m.fillPath()
m.addPath(rr(CGRect(x: 478, y: 540, width: 56, height: 84), 28)); m.fillPath()
// Windshield: a single raked pillar
m.setLineCap(.round); m.setLineJoin(.round); m.setLineWidth(26)
m.move(to: CGPoint(x: 668, y: 556)); m.addLine(to: CGPoint(x: 618, y: 660)); m.strokePath()

// Wheel arches cut out of the body, then wheels with a hub hole
m.setBlendMode(.clear)
for x in [rearX, frontX] {
    m.fillEllipse(in: CGRect(x: x - wheelR - 20, y: wheelY - wheelR - 20, width: 2 * (wheelR + 20), height: 2 * (wheelR + 20)))
}
m.setBlendMode(.normal)
for x in [rearX, frontX] { m.fillEllipse(in: CGRect(x: x - wheelR, y: wheelY - wheelR, width: 2 * wheelR, height: 2 * wheelR)) }
m.setBlendMode(.clear)
for x in [rearX, frontX] { m.fillEllipse(in: CGRect(x: x - 30, y: wheelY - 30, width: 60, height: 60)) }
// Round headlight and a door line
m.fillEllipse(in: CGRect(x: 784, y: 462, width: 42, height: 42))
let mask = m.makeImage()!

// ---- Compose ----
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: (mode == "light" ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
let full = CGRect(x: 0, y: 0, width: 1024, height: 1024)
let opts: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
if mode != "tinted" {
    let colors = mode == "light" ? [c(0x4A4A4E), c(0x232326)] : [c(0x1E1E20), c(0x0A0A0B)]
    ctx.drawLinearGradient(CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0, 1])!,
                           start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: opts)
}
let white = c(mode == "dark" ? 0xE5E5EA : 0xFFFFFF)
ctx.saveGState()
if mode == "light" { ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: c(0x000000, 0.35)) }
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.clip(to: full, mask: mask); ctx.setFillColor(white); ctx.fill(full)
ctx.endTransparencyLayer()
ctx.restoreGState()

// Music note (two beamed eighth notes) floating above the open top
ctx.setFillColor(white)
func noteHead(_ cx: CGFloat, _ cy: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy); ctx.rotate(by: 0.42)
    ctx.fillEllipse(in: CGRect(x: -44, y: -32, width: 88, height: 64))
    ctx.restoreGState()
}
let leftX: CGFloat = 432, rightX: CGFloat = 592
let leftHeadY: CGFloat = 712, rightHeadY: CGFloat = 742
// Scale the note down around its center, sitting a little lower toward the car
ctx.saveGState()
ctx.translateBy(x: 520, y: 760); ctx.scaleBy(x: 0.72, y: 0.72); ctx.translateBy(x: -520, y: -790)
noteHead(leftX, leftHeadY); noteHead(rightX, rightHeadY)
// Stems rise from the right side of each head
let stemW: CGFloat = 20
ctx.fill(CGRect(x: leftX + 26, y: leftHeadY, width: stemW, height: 168))
ctx.fill(CGRect(x: rightX + 26, y: rightHeadY, width: stemW, height: 168))
// Slanted beam joining the stem tops
let beam = CGMutablePath()
beam.move(to: CGPoint(x: leftX + 26, y: leftHeadY + 168 - 46))
beam.addLine(to: CGPoint(x: rightX + 26 + stemW, y: rightHeadY + 168 - 46))
beam.addLine(to: CGPoint(x: rightX + 26 + stemW, y: rightHeadY + 168))
beam.addLine(to: CGPoint(x: leftX + 26, y: leftHeadY + 168))
beam.closeSubpath()
ctx.addPath(beam); ctx.fillPath()
ctx.restoreGState()

try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
