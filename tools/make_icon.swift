// Génère Resources/AppIcon.icns : swift tools/make_icon.swift <dossier Resources>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(starting: NSColor(red: 0.42, green: 0.80, blue: 0.36, alpha: 1),
               ending: NSColor(red: 0.10, green: 0.50, blue: 0.30, alpha: 1))!.draw(in: path, angle: -90)
    // Feuille de papier
    let page = NSRect(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.14,
                      width: rect.width * 0.6, height: rect.height * 0.72)
    NSColor(white: 1, alpha: 0.95).setFill()
    NSBezierPath(roundedRect: page, xRadius: page.width * 0.08, yRadius: page.width * 0.08).fill()
    // Lignes de texte
    NSColor(red: 0.10, green: 0.50, blue: 0.30, alpha: 0.35).setFill()
    for i in 0..<5 {
        let w = page.width * (i == 0 ? 0.45 : (i % 2 == 0 ? 0.7 : 0.6))
        let h = page.height * 0.045
        let y = page.maxY - page.height * (0.43 + CGFloat(i) * 0.11)
        NSBezierPath(roundedRect: NSRect(x: page.minX + page.width * 0.14, y: y, width: w, height: h),
                     xRadius: h / 2, yRadius: h / 2).fill()
    }
    // « ++ »
    let font = NSFont.systemFont(ofSize: page.height * 0.22, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(red: 0.10, green: 0.50, blue: 0.30, alpha: 1)]
    let label = "++" as NSString
    let size = label.size(withAttributes: attrs)
    label.draw(at: NSPoint(x: page.minX + page.width * 0.12, y: page.maxY - size.height - page.height * 0.04), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "\(outDir)/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
print("Icône créée : \(outDir)/AppIcon.icns")
