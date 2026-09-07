import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("Usage: render_app_icon.swift <output.png>\n", stderr)
  exit(64)
}

let side: CGFloat = 1024
let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: Int(side),
  pixelsHigh: Int(side),
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
)!
let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
defer { NSGraphicsContext.restoreGraphicsState() }

func color(_ value: UInt32) -> NSColor {
  NSColor(
    red: CGFloat((value >> 16) & 0xff) / 255,
    green: CGFloat((value >> 8) & 0xff) / 255,
    blue: CGFloat(value & 0xff) / 255,
    alpha: 1
  )
}

let bounds = NSRect(x: 0, y: 0, width: side, height: side)
let outer = NSBezierPath(roundedRect: bounds, xRadius: 224, yRadius: 224)
color(0x000713).setFill()
outer.fill()

let inset = NSBezierPath(
  roundedRect: NSRect(x: 54, y: 54, width: 916, height: 916),
  xRadius: 190,
  yRadius: 190
)
color(0x303946).setStroke()
inset.lineWidth = 12
inset.stroke()

func stroke(_ points: [NSPoint], width: CGFloat, color: NSColor) {
  let path = NSBezierPath()
  path.move(to: points[0])
  for point in points.dropFirst() { path.line(to: point) }
  path.lineWidth = width
  path.lineCapStyle = .round
  path.lineJoinStyle = .round
  color.setStroke()
  path.stroke()
}

color(0x202B39).setFill()
for rect in [
  NSRect(x: 240, y: 234, width: 544, height: 46),
  NSRect(x: 300, y: 344, width: 424, height: 40),
  NSRect(x: 365, y: 450, width: 294, height: 34),
] {
  NSBezierPath(rect: rect).fill()
}

let steel = NSGradient(colors: [color(0xAEB6C3), color(0xF5F7FA)])!
func steelStroke(_ points: [NSPoint], width: CGFloat) {
  let path = NSBezierPath()
  path.move(to: points[0])
  for point in points.dropFirst() { path.line(to: point) }
  path.lineWidth = width
  path.lineCapStyle = .round
  path.lineJoinStyle = .round
  steel.draw(in: path, angle: 90)
}

steelStroke([NSPoint(x: 328, y: 180), NSPoint(x: 478, y: 562), NSPoint(x: 512, y: 602)], width: 34)
steelStroke([NSPoint(x: 696, y: 180), NSPoint(x: 546, y: 562), NSPoint(x: 512, y: 602)], width: 34)
steelStroke([NSPoint(x: 428, y: 180), NSPoint(x: 512, y: 396), NSPoint(x: 512, y: 602)], width: 34)
steelStroke([NSPoint(x: 596, y: 180), NSPoint(x: 512, y: 396)], width: 34)

let red = color(0xD80F10)
stroke([NSPoint(x: 512, y: 602), NSPoint(x: 512, y: 806)], width: 28, color: red)
red.setFill()
NSBezierPath(ovalIn: NSRect(x: 490, y: 784, width: 44, height: 44)).fill()

let text = NSAttributedString(
  string: "ТЧМ",
  attributes: [
    .font: NSFont.systemFont(ofSize: 92, weight: .heavy),
    .foregroundColor: color(0xE9EAEC),
    .kern: 10,
  ]
)
let textSize = text.size()
text.draw(at: NSPoint(x: (side - textSize.width) / 2, y: 850))

guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fputs("Could not encode the icon.\n", stderr)
  exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
