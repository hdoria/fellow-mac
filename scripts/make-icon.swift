import AppKit
import Foundation

// Original geometric cup artwork. The same path geometry is rendered at every size.
let output = URL(
  fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns")
let manager = FileManager.default
let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let iconset = temporary.appendingPathComponent("AppIcon.iconset")
try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: temporary) }

func render(size: Int) throws -> Data {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else {
    throw NSError(domain: "IconGeneration", code: 1)
  }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
  context.imageInterpolation = .high
  NSColor(calibratedRed: 0.105, green: 0.11, blue: 0.12, alpha: 1).setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912),
    xRadius: 205, yRadius: 205
  ).fill()

  let copper = NSColor(calibratedRed: 0.80, green: 0.48, blue: 0.29, alpha: 1)
  copper.setStroke()
  let handle = NSBezierPath(
    roundedRect: NSRect(x: 625, y: 350, width: 160, height: 195),
    xRadius: 72, yRadius: 72)
  handle.lineWidth = 48
  handle.stroke()

  NSColor(calibratedRed: 0.92, green: 0.87, blue: 0.78, alpha: 1).setFill()
  let cup = NSBezierPath()
  cup.move(to: NSPoint(x: 282, y: 605))
  cup.line(to: NSPoint(x: 673, y: 605))
  cup.line(to: NSPoint(x: 651, y: 356))
  cup.curve(
    to: NSPoint(x: 559, y: 270),
    controlPoint1: NSPoint(x: 647, y: 303), controlPoint2: NSPoint(x: 613, y: 270))
  cup.line(to: NSPoint(x: 396, y: 270))
  cup.curve(
    to: NSPoint(x: 304, y: 356),
    controlPoint1: NSPoint(x: 342, y: 270), controlPoint2: NSPoint(x: 308, y: 303))
  cup.close()
  cup.fill()

  copper.setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 318, y: 553, width: 319, height: 22),
    xRadius: 11, yRadius: 11
  ).fill()
  NSBezierPath(
    roundedRect: NSRect(x: 258, y: 207, width: 440, height: 24),
    xRadius: 12, yRadius: 12
  ).fill()
  copper.setStroke()
  for x: CGFloat in [415, 530] {
    let steam = NSBezierPath()
    steam.move(to: NSPoint(x: x, y: 674))
    steam.curve(
      to: NSPoint(x: x + 4, y: 795),
      controlPoint1: NSPoint(x: x - 42, y: 724),
      controlPoint2: NSPoint(x: x + 47, y: 751))
    steam.lineWidth = 25
    steam.lineCapStyle = .round
    steam.stroke()
  }
  NSGraphicsContext.restoreGraphicsState()
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "IconGeneration", code: 2)
  }
  return png
}

for points in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let suffix = scale == 2 ? "@2x" : ""
    let name = "icon_\(points)x\(points)\(suffix).png"
    try render(size: points * scale).write(to: iconset.appendingPathComponent(name))
  }
}
try manager.createDirectory(
  at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
  throw NSError(domain: "IconGeneration", code: Int(process.terminationStatus))
}
print("Icon created: \(output.path)")
