import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Normalize approved artwork to Apple's opaque 1024px icon. Preserve the master.
let output = CommandLine.arguments.dropFirst().first ?? "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let source = CommandLine.arguments.dropFirst(2).first ?? "marketing/icon/Uniboard-Icon.png"
guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: source) as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
      artwork.width == artwork.height else { fatalError("A square source icon is required") }
guard let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Cannot create icon renderer")
}
context.interpolationQuality = .high
context.draw(artwork, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
guard let icon = context.makeImage() else { fatalError("Cannot normalize icon") }
try FileManager.default.createDirectory(at: URL(fileURLWithPath: output).deletingLastPathComponent(), withIntermediateDirectories: true)
guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
                                                       UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Cannot create PNG destination")
}
CGImageDestinationAddImage(destination, icon, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write icon") }
