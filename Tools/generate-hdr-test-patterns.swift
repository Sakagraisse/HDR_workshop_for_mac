#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let width = 1_000
private let height = 1_000
private let boost: Float = 4.0

private enum Pattern: String, CaseIterable {
    case halfRight = "half-right"
    case hdrCenter = "hdr-center"
}

private let glyphs: [Character: [String]] = [
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
]

private func isBoosted(x: Int, y: Int, pattern: Pattern) -> Bool {
    switch pattern {
    case .halfRight:
        return x >= width / 2
    case .hdrCenter:
        let text = Array("HDR")
        let scale = 40
        let glyphWidth = 5 * scale
        let spacing = scale
        let textWidth = text.count * glyphWidth + (text.count - 1) * spacing
        let textHeight = 7 * scale
        let originX = (width - textWidth) / 2
        let originY = (height - textHeight) / 2

        guard x >= originX, x < originX + textWidth,
              y >= originY, y < originY + textHeight else { return false }

        let localX = x - originX
        let stride = glyphWidth + spacing
        let glyphIndex = localX / stride
        guard glyphIndex < text.count else { return false }
        let withinGlyphX = localX % stride
        guard withinGlyphX < glyphWidth else { return false }

        let column = withinGlyphX / scale
        let row = (y - originY) / scale
        return glyphs[text[glyphIndex]]![row][column] == "1"
    }
}

private extension String {
    subscript(_ offset: Int) -> Character {
        self[index(startIndex, offsetBy: offset)]
    }
}

private func writePNG(_ bytes: [UInt8], channels: Int, to url: URL) throws {
    let colorSpace = channels == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
    let bitmapInfo: CGBitmapInfo = channels == 1
        ? CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        : CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    guard let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8 * channels,
        bytesPerRow: width * channels,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ), let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "HDRPatterns", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination"])
    }
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyPNGInterlaceType: 0] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "HDRPatterns", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not write \(url.path)"])
    }
}

private func writeFloatTIFF(pattern: Pattern, to url: URL) throws {
    var pixels = [Float](repeating: 1.0, count: width * height * 3)
    for y in 0..<height {
        for x in 0..<width {
            let value: Float = isBoosted(x: x, y: y, pattern: pattern) ? boost : 1.0
            let index = (y * width + x) * 3
            pixels[index] = value
            pixels[index + 1] = value
            pixels[index + 2] = value
        }
    }

    // Minimal uncompressed TIFF writer. ImageIO clips extended-range float pixels
    // to 1.0 during export, so writing the well-defined TIFF tags directly keeps
    // the intended 4.0 (+2 stop) values intact.
    struct Entry {
        let tag: UInt16
        let type: UInt16
        let count: UInt32
        let valueOrOffset: UInt32
    }

    func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    let iccData = colorSpace.copyICCData()! as Data
    let entryCount = 14
    let ifdSize = 2 + entryCount * 12 + 4
    let bitsOffset = UInt32(8 + ifdSize)
    let sampleFormatOffset = bitsOffset + 6
    let xResolutionOffset = sampleFormatOffset + 6
    let yResolutionOffset = xResolutionOffset + 8
    let iccOffset = yResolutionOffset + 8
    let pixelOffset = (iccOffset + UInt32(iccData.count) + 3) & ~UInt32(3)
    let byteCount = UInt32(width * height * 3 * MemoryLayout<Float>.size)

    let entries = [
        Entry(tag: 256, type: 4, count: 1, valueOrOffset: UInt32(width)),
        Entry(tag: 257, type: 4, count: 1, valueOrOffset: UInt32(height)),
        Entry(tag: 258, type: 3, count: 3, valueOrOffset: bitsOffset),
        Entry(tag: 259, type: 3, count: 1, valueOrOffset: 1),
        Entry(tag: 262, type: 3, count: 1, valueOrOffset: 2),
        Entry(tag: 273, type: 4, count: 1, valueOrOffset: pixelOffset),
        Entry(tag: 277, type: 3, count: 1, valueOrOffset: 3),
        Entry(tag: 278, type: 4, count: 1, valueOrOffset: UInt32(height)),
        Entry(tag: 279, type: 4, count: 1, valueOrOffset: byteCount),
        Entry(tag: 282, type: 5, count: 1, valueOrOffset: xResolutionOffset),
        Entry(tag: 283, type: 5, count: 1, valueOrOffset: yResolutionOffset),
        Entry(tag: 284, type: 3, count: 1, valueOrOffset: 1),
        Entry(tag: 339, type: 3, count: 3, valueOrOffset: sampleFormatOffset),
        Entry(tag: 34675, type: 7, count: UInt32(iccData.count), valueOrOffset: iccOffset),
    ]

    var data = Data(capacity: Int(pixelOffset + byteCount))
    data.append(contentsOf: [0x49, 0x49]) // little-endian TIFF
    appendLE(UInt16(42), to: &data)
    appendLE(UInt32(8), to: &data)
    appendLE(UInt16(entryCount), to: &data)
    for entry in entries {
        appendLE(entry.tag, to: &data)
        appendLE(entry.type, to: &data)
        appendLE(entry.count, to: &data)
        appendLE(entry.valueOrOffset, to: &data)
    }
    appendLE(UInt32(0), to: &data)
    [UInt16(32), 32, 32, 3, 3, 3].forEach { appendLE($0, to: &data) }
    [UInt32(72), 1, 72, 1].forEach { appendLE($0, to: &data) }
    data.append(iccData)
    while data.count < Int(pixelOffset) { data.append(0) }
    pixels.withUnsafeBytes { data.append(contentsOf: $0) }
    try data.write(to: url, options: .atomic)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "TestAssets/HDRTestPatterns", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let whiteRGB = [UInt8](repeating: 255, count: width * height * 3)
try writePNG(whiteRGB, channels: 3, to: outputDirectory.appendingPathComponent("base-white-srgb-rgb.png"))

for pattern in Pattern.allCases {
    var gainMap = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width where isBoosted(x: x, y: y, pattern: pattern) {
            gainMap[y * width + x] = 255
        }
    }
    try writePNG(gainMap, channels: 1, to: outputDirectory.appendingPathComponent("gainmap-\(pattern.rawValue)-plus2stops.png"))
    try writeFloatTIFF(pattern: pattern, to: outputDirectory.appendingPathComponent("master-linear-srgb-\(pattern.rawValue)-4x.tiff"))
}

print(outputDirectory.path)
