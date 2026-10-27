import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.965, green: 0.949, blue: 0.918, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 208, yRadius: 208).fill()
        NSColor(calibratedRed: 0.69, green: 0.435, blue: 0.227, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 238, y: 190, width: 548, height: 640), xRadius: 66, yRadius: 66).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 267, y: 218, width: 490, height: 580), xRadius: 42, yRadius: 42).fill()
        NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 390, y: 758, width: 244, height: 105), xRadius: 30, yRadius: 30).fill()
        for y in [620, 472, 324] {
            NSColor(calibratedRed: 0.36, green: 0.54, blue: 0.45, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 323, y: y, width: 60, height: 60), xRadius: 16, yRadius: 16).fill()
            NSColor(calibratedWhite: 0.82, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 425, y: y + 17, width: 250, height: 24), xRadius: 12, yRadius: 12).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

// Write the standard ICNS container directly, without depending on IconServices.
// Every chunk contains one of the PNG representations generated above.
if CommandLine.arguments.count > 2 {
    func bigEndian(_ value: Int) -> Data {
        var number = UInt32(value).bigEndian
        return withUnsafeBytes(of: &number) { Data($0) }
    }
    var chunks = Data()
    let representations = [
        ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
        ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
        ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
        ("ic14", "icon_256x256@2x.png")
    ]
    for (type, filename) in representations {
        let png = try Data(contentsOf: output.appendingPathComponent(filename))
        chunks.append(Data(type.utf8)); chunks.append(bigEndian(png.count + 8)); chunks.append(png)
    }
    var container = Data("icns".utf8); container.append(bigEndian(chunks.count + 8)); container.append(chunks)
    try container.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
}
