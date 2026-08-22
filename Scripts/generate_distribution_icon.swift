import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: generate_distribution_icon.swift <transparent-layer.png> <output.png>")
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Could not read \(inputURL.path)")
}

let size = 1024
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Could not create the icon canvas")
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let colors = [
    CGColor(colorSpace: colorSpace, components: [0.0, 0.58, 1.0, 1.0])!,
    CGColor(colorSpace: colorSpace, components: [0.0, 0.23, 0.72, 1.0])!,
] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)
context.interpolationQuality = .high
context.draw(logo, in: CGRect(x: 0, y: 0, width: size, height: size))

guard let result = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          outputURL as CFURL,
          UTType.png.identifier as CFString,
          1,
          nil
      ) else {
    fatalError("Could not create \(outputURL.path)")
}

CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not finish writing \(outputURL.path)")
}

print("Wrote 1024×1024 distribution icon to \(outputURL.path)")
