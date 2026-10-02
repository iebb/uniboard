import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(red: 0.16, green: 0.20, blue: 0.17, alpha: 1).setFill()
NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

let tile = CGRect(x: 164, y: 172, width: 696, height: 696)
NSColor(red: 0.97, green: 0.95, blue: 0.90, alpha: 1).setFill()
NSBezierPath(roundedRect: tile, xRadius: 128, yRadius: 128).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let glyphAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 382, weight: .light),
    .foregroundColor: NSColor(red: 0.16, green: 0.20, blue: 0.17, alpha: 1),
    .paragraphStyle: paragraph
]
NSString(string: "U").draw(in: CGRect(x: 208, y: 319, width: 495, height: 451), withAttributes: glyphAttrs)
let plusAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 186, weight: .medium),
    .foregroundColor: NSColor(red: 0.73, green: 0.30, blue: 0.17, alpha: 1)
]
NSString(string: "+").draw(at: CGPoint(x: 629, y: 482), withAttributes: plusAttrs)
let labelAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 54, weight: .medium),
    .foregroundColor: NSColor(red: 0.43, green: 0.46, blue: 0.41, alpha: 1),
    .paragraphStyle: paragraph,
    .kern: 8
]
NSString(string: "UNIBOARD").draw(in: CGRect(x: 210, y: 262, width: 604, height: 66), withAttributes: labelAttrs)
image.unlockFocus()

let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.draw(image.cgImage(forProposedRect: nil, context: nil, hints: nil)!,
             in: CGRect(origin: .zero, size: size))
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot render icon") }
try FileManager.default.createDirectory(at: URL(fileURLWithPath: output).deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: URL(fileURLWithPath: output))
