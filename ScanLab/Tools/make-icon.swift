import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
guard CommandLine.arguments.count == 2 else { fatalError("Pass a new output PNG path") }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard !FileManager.default.fileExists(atPath: url.path) else { fatalError("Will not overwrite an existing icon") }
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.19, green: 0.16, blue: 0.46, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.setFillColor(CGColor(red: 0.28, green: 0.27, blue: 0.65, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 250, y: 150, width: 524, height: 724), cornerWidth: 46, cornerHeight: 46, transform: nil)); context.fillPath()
context.setStrokeColor(CGColor(red: 0.57, green: 0.97, blue: 0.80, alpha: 1)); context.setLineWidth(36); context.setLineCap(.round)
for (x,y,sx,sy) in [(190.0,190.0,1.0,1.0),(834.0,190.0,-1.0,1.0),(190.0,834.0,1.0,-1.0),(834.0,834.0,-1.0,-1.0)] {
 context.move(to: CGPoint(x:x,y:y+sy*110)); context.addLine(to: CGPoint(x:x,y:y)); context.addLine(to: CGPoint(x:x+sx*110,y:y)); context.strokePath()
}
context.strokeEllipse(in: CGRect(x: 400, y: 400, width: 224, height: 224))
context.move(to: CGPoint(x: 400,y:512)); context.addLine(to: CGPoint(x:624,y:512)); context.strokePath()
context.setFillColor(CGColor(red: 0.57, green: 0.97, blue: 0.80, alpha: 1)); context.fillEllipse(in: CGRect(x: 474, y: 474, width: 76, height: 76))
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not save icon") }
