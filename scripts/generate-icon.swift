import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift generate-icon.swift OUTPUT.png")
}

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Could not create icon bitmap")
}

// The supplied 132 × 122 image contains a 102 × 103 rounded tile and a
// turquoise waveform. Reconstruct these simple shapes at icon resolution.
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)
context.setFillColor(CGColor(red: 235 / 255, green: 249 / 255,
                             blue: 250 / 255, alpha: 1))
let tile = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                  cornerWidth: 230, cornerHeight: 230, transform: nil)
context.addPath(tile)
context.fillPath()

func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: (x - 13) * CGFloat(size) / 102,
            y: (y - 10) * CGFloat(size) / 103)
}

let waveform: [(CGFloat, CGFloat)] = [
    (32, 62.5), (40, 62.5), (44, 53.5), (48.5, 76.5),
    (54, 44.5), (58.5, 88.5), (64, 32), (69, 88.5),
    (74, 45), (79, 76), (84, 53.5), (88, 62.5), (95, 62.5)
]
context.setStrokeColor(CGColor(red: 3 / 255, green: 195 / 255,
                               blue: 207 / 255, alpha: 1))
context.setLineWidth(42)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: point(waveform[0].0, waveform[0].1))
for (x, y) in waveform.dropFirst() { context.addLine(to: point(x, y)) }
context.strokePath()

guard let image = context.makeImage() else { fatalError("Could not render icon") }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
guard let destination = CGImageDestinationCreateWithURL(output as CFURL,
                                                         UTType.png.identifier as CFString,
                                                         1, nil) else {
    fatalError("Could not create output PNG")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not save icon") }
