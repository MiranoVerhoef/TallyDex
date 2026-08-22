import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: generate_icon_layer.swift <input.png> <output.png>")
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Could not read \(inputURL.path)")
}

let canvasSize = 1024
let maximumWidth = 900.0
let maximumHeight = 480.0
let scale = min(maximumWidth / Double(logo.width), maximumHeight / Double(logo.height))
let width = Double(logo.width) * scale
let height = Double(logo.height) * scale
let drawingRect = CGRect(
    x: (Double(canvasSize) - width) / 2,
    y: (Double(canvasSize) - height) / 2,
    width: width,
    height: height
)

guard let context = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Could not create the icon layer canvas")
}

context.interpolationQuality = .high
context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
context.draw(logo, in: drawingRect)

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

print("Wrote centered 1024×1024 transparent icon layer to \(outputURL.path)")
