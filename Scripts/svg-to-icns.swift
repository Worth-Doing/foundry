#!/usr/bin/env swift
import AppKit
import Foundation

// Paths
let projectDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let svgPath = projectDir.appendingPathComponent("Resources/foundry-logo.svg")
let iconsetDir = projectDir.appendingPathComponent("Resources/AppIcon.iconset")
let icnsPath = projectDir.appendingPathComponent("Resources/AppIcon.icns")
let pngPath = projectDir.appendingPathComponent("Resources/foundry-icon-1024.png")

// Required icon sizes: (filename, pixel size)
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

// Load SVG
guard let svgData = try? Data(contentsOf: svgPath) else {
    print("ERROR: Cannot read SVG at \(svgPath.path)")
    exit(1)
}

guard let svgImage = NSImage(data: svgData) else {
    print("ERROR: Cannot parse SVG as NSImage")
    exit(1)
}

print("SVG loaded: \(svgImage.size)")

// Render to PNG at a given pixel size
func renderPNG(image: NSImage, pixelSize: Int) -> Data? {
    let size = NSSize(width: pixelSize, height: pixelSize)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: size),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy,
               fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

// Create iconset directory
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// Generate all sizes
for (filename, pixelSize) in sizes {
    guard let pngData = renderPNG(image: svgImage, pixelSize: pixelSize) else {
        print("ERROR: Failed to render \(filename) at \(pixelSize)px")
        exit(1)
    }
    let outPath = iconsetDir.appendingPathComponent(filename)
    try pngData.write(to: outPath)
    print("  \(filename) (\(pixelSize)px) — \(pngData.count) bytes")
}

// Also save the 1024px version
if let bigPNG = renderPNG(image: svgImage, pixelSize: 1024) {
    try bigPNG.write(to: pngPath)
    print("  foundry-icon-1024.png (1024px) — \(bigPNG.count) bytes")
}

print("Iconset generated at \(iconsetDir.path)")

// Run iconutil to create .icns
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", icnsPath.path, iconsetDir.path]

try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    let icnsSize = try FileManager.default.attributesOfItem(atPath: icnsPath.path)[.size] as? Int ?? 0
    print("AppIcon.icns created — \(icnsSize) bytes")
} else {
    print("ERROR: iconutil failed with status \(process.terminationStatus)")
    exit(1)
}

print("Done!")
