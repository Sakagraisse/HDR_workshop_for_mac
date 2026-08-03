import CoreGraphics
import CoreImage
import Foundation
import ImageIO

enum FullAppleEncoderError: LocalizedError {
    case missingInputs
    case missingOutputFolder
    case unableToLoad(String)
    case sourceIsNotHDR(String)
    case mismatchedDimensions
    case appleEncodingFailed(String)
    case malformedJPEG(String)
    case missingGeneratedGainMap
    case invalidMetadata(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingInputs: "Missing HDR source."
        case .missingOutputFolder: "Missing output folder."
        case let .unableToLoad(name): "Unable to load \(name) with Core Image."
        case let .sourceIsNotHDR(name): "\(name) does not decode with HDR headroom greater than 1.0."
        case .mismatchedDimensions: "HDR and custom SDR images must have identical pixel dimensions."
        case let .appleEncodingFailed(message): "Apple JPEG/gain-map encoding failed: \(message)"
        case let .malformedJPEG(message): "Malformed JPEG/MPF data: \(message)"
        case .missingGeneratedGainMap: "ImageIO did not generate the expected secondary gain-map JPEG."
        case let .invalidMetadata(message): "Invalid gain-map metadata: \(message)"
        case let .verificationFailed(message): "ISOHDR verification failed: \(message)"
        }
    }
}

struct FullAppleGainMapMetadata: Equatable, Sendable {
    let gainMapMin: Double
    let gainMapMax: Double
    let gamma: Double
    let offsetSDR: Double
    let offsetHDR: Double
    let capacityMin: Double
    let capacityMax: Double

    static func parse(from jpeg: Data, fallbackHeadroom: Double) throws -> Self {
        let text = String(decoding: jpeg, as: UTF8.self)
        let fallbackMax = log2(max(fallbackHeadroom, 1.000_001))

        let minValue = firstNumber(named: ["GainMapMin"], in: text) ?? 0
        let maxValue = firstNumber(named: ["GainMapMax"], in: text) ?? fallbackMax
        let gammaValue = firstNumber(named: ["Gamma"], in: text) ?? 1
        let offsetSDRValue = firstNumber(named: ["OffsetSDR", "BaseOffset"], in: text) ?? 0.000_001
        let offsetHDRValue = firstNumber(named: ["OffsetHDR", "AlternateOffset"], in: text) ?? 0.000_001
        let capacityMinValue = firstNumber(named: ["BaseHeadroom", "HDRCapacityMin"], in: text) ?? 0
        let capacityMaxValue = firstNumber(named: ["AlternateHeadroom", "HDRCapacityMax"], in: text) ?? maxValue

        guard maxValue > minValue,
              gammaValue > 0,
              capacityMaxValue > capacityMinValue else {
            throw FullAppleEncoderError.invalidMetadata(
                "min=\(minValue), max=\(maxValue), gamma=\(gammaValue), capacity=\(capacityMinValue)…\(capacityMaxValue)"
            )
        }

        return Self(
            gainMapMin: minValue,
            gainMapMax: maxValue,
            gamma: gammaValue,
            offsetSDR: max(0, offsetSDRValue),
            offsetHDR: max(0, offsetHDRValue),
            capacityMin: capacityMinValue,
            capacityMax: capacityMaxValue
        )
    }

    private static func firstNumber(named names: [String], in text: String) -> Double? {
        for name in names {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let patterns = [
                "<(?:HDRToneMap|hdrgm):\(escaped)>([^<]+)</(?:HDRToneMap|hdrgm):\(escaped)>",
                "(?:HDRToneMap|hdrgm):\(escaped)=\\\"([^\\\"]+)\\\""
            ]
            for pattern in patterns {
                guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                guard let match = expression.firstMatch(in: text, range: range),
                      let capture = Range(match.range(at: 1), in: text),
                      let value = Double(text[capture]) else { continue }
                return value
            }
        }
        return nil
    }
}

struct FullAppleVerification: Equatable, Sendable {
    let primaryLength: Int
    let gainMapLength: Int
    let hasUltraHDRXMP: Bool
    let hasGContainer: Bool
    let hasISOPrimary: Bool
    let hasISOSecondary: Bool
    let hasValidMPF: Bool
    let hasAppleLegacyMarker: Bool
}

struct FullAppleJPEGEncoder {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func encode(
        hdrURL: URL,
        sdrURL: URL?,
        outputURL: URL,
        quality: Double,
        colorSpaceKind: ColorSpaceKind,
        rgbGainMap: Bool = false
    ) throws -> FullAppleVerification {
        guard let hdrImage = CIImage(contentsOf: hdrURL, options: [.expandToHDR: true]) else {
            throw FullAppleEncoderError.unableToLoad(hdrURL.lastPathComponent)
        }
        let sourceHeadroom = max(Double(hdrImage.contentHeadroom), measuredHeadroom(hdrImage))
        guard sourceHeadroom > 1.000_1 else {
            throw FullAppleEncoderError.sourceIsNotHDR(hdrURL.lastPathComponent)
        }

        let sdrImage: CIImage
        if let sdrURL {
            guard let customSDR = CIImage(contentsOf: sdrURL) else {
                throw FullAppleEncoderError.unableToLoad(sdrURL.lastPathComponent)
            }
            guard integralSize(customSDR.extent) == integralSize(hdrImage.extent) else {
                throw FullAppleEncoderError.mismatchedDimensions
            }
            sdrImage = customSDR
        } else {
            sdrImage = hdrImage.applyingFilter(
                "CIToneMapHeadroom",
                parameters: [
                    "inputSourceHeadroom": sourceHeadroom,
                    "inputTargetHeadroom": 1.0
                ]
            )
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "isohdr-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let colorSpace = outputColorSpace(colorSpaceKind)
        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): min(max(quality, 0), 1),
            .hdrImage: hdrImage,
            .hdrGainMapAsRGB: rgbGainMap
        ]
        do {
            try context.writeJPEGRepresentation(
                of: sdrImage,
                to: temporaryURL,
                colorSpace: colorSpace,
                options: options
            )
        } catch {
            throw FullAppleEncoderError.appleEncodingFailed(error.localizedDescription)
        }

        let appleContainer = try Data(contentsOf: temporaryURL)
        let pair = try FullAppleJPEGAssembler.splitJPEGPair(appleContainer)
        let metadata = try FullAppleGainMapMetadata.parse(
            from: pair.secondary,
            fallbackHeadroom: sourceHeadroom
        )
        let finalData = try FullAppleJPEGAssembler().assemble(
            appleContainer: appleContainer,
            metadata: metadata
        )
        let verification = try FullAppleJPEGAssembler().verify(finalData)
        guard verification.hasUltraHDRXMP,
              verification.hasGContainer,
              verification.hasISOPrimary,
              verification.hasISOSecondary,
              verification.hasValidMPF,
              !verification.hasAppleLegacyMarker else {
            throw FullAppleEncoderError.verificationFailed(String(describing: verification))
        }
        try finalData.write(to: outputURL, options: .atomic)
        return verification
    }

    private func integralSize(_ extent: CGRect) -> CGSize {
        CGRectIntegral(extent).size
    }

    private func measuredHeadroom(_ image: CIImage) -> Double {
        let maximum = image.applyingFilter(
            "CIAreaMaximum",
            parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)]
        )
        var pixel = [Float](repeating: 0, count: 4)
        context.render(
            maximum,
            toBitmap: &pixel,
            rowBytes: MemoryLayout<Float>.size * 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBAf,
            colorSpace: nil
        )
        return Double(max(pixel[0], pixel[1], pixel[2]))
    }

    private func outputColorSpace(_ kind: ColorSpaceKind) -> CGColorSpace {
        switch kind {
        case .sRGB, .extendedLinearSRGB, .unknown:
            CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3, .rec2020:
            CGColorSpace(name: CGColorSpace.displayP3)!
        }
    }
}

struct FullAppleJPEGAssembler {
    private static let xmpNamespace = Array("http://ns.adobe.com/xap/1.0/".utf8) + [0]
    private static let isoNamespace = Array("urn:iso:std:iso:ts:21496:-1".utf8) + [0]
    private static let appleLegacyMarker = "urn:com:apple:photo:2020:aux:hdrgainmap"

    struct JPEGPair {
        let primary: Data
        let secondary: Data
    }

    func assemble(appleContainer: Data, metadata: FullAppleGainMapMetadata) throws -> Data {
        let pair = try Self.splitJPEGPair(appleContainer)
        var primary = try strippedJPEG(pair.primary, removeMPF: false)
        var secondary = try strippedJPEG(pair.secondary, removeMPF: true)

        let secondaryXMP = try appSegment(marker: 0xE1, payload: Self.xmpNamespace + Array(secondaryXMP(metadata: metadata).utf8))
        let secondaryISO = try appSegment(marker: 0xE2, payload: Self.isoNamespace + isoMetadata(metadata))
        secondary = try inserting([secondaryXMP, secondaryISO], into: secondary, beforeMPF: false)

        let primaryXMP = try appSegment(
            marker: 0xE1,
            payload: Self.xmpNamespace + Array(primaryXMP(secondaryLength: secondary.count).utf8)
        )
        let primaryISO = try appSegment(
            marker: 0xE2,
            payload: Self.isoNamespace + [0, 0, 0, 0]
        )
        primary = try inserting([primaryXMP, primaryISO], into: primary, beforeMPF: true)

        var final = Data()
        final.reserveCapacity(primary.count + secondary.count)
        final.append(primary)
        final.append(secondary)
        try patchMPF(in: &final, primaryLength: primary.count, secondaryLength: secondary.count)
        return final
    }

    func verify(_ data: Data) throws -> FullAppleVerification {
        let pair = try Self.splitJPEGPair(data)
        let primaryBytes = [UInt8](pair.primary)
        let secondaryBytes = [UInt8](pair.secondary)
        let primaryText = String(decoding: primaryBytes, as: UTF8.self)
        let secondaryText = String(decoding: secondaryBytes, as: UTF8.self)
        let mpfIsValid = try verifyMPF(data, primaryLength: pair.primary.count, secondaryLength: pair.secondary.count)

        return FullAppleVerification(
            primaryLength: pair.primary.count,
            gainMapLength: pair.secondary.count,
            hasUltraHDRXMP: primaryText.contains("hdrgm:Version=\"1.0\"") && secondaryText.contains("hdrgm:Version=\"1.0\""),
            hasGContainer: primaryText.contains("Container:Directory") && primaryText.contains("Item:Semantic=\"GainMap\"") && primaryText.contains("Item:Length=\"\(pair.secondary.count)\""),
            hasISOPrimary: containsSubsequence(primaryBytes, Self.isoNamespace),
            hasISOSecondary: containsSubsequence(secondaryBytes, Self.isoNamespace),
            hasValidMPF: mpfIsValid,
            hasAppleLegacyMarker: primaryText.contains(Self.appleLegacyMarker) || secondaryText.contains(Self.appleLegacyMarker)
        )
    }

    static func splitJPEGPair(_ data: Data) throws -> JPEGPair {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
            throw FullAppleEncoderError.malformedJPEG("missing primary SOI")
        }
        guard let primaryEnd = jpegEnd(in: bytes, startingAt: 0) else {
            throw FullAppleEncoderError.malformedJPEG("missing primary EOI")
        }
        guard let secondaryStart = findSubsequence(bytes, [0xFF, 0xD8], from: primaryEnd),
              let secondaryEnd = jpegEnd(in: bytes, startingAt: secondaryStart) else {
            throw FullAppleEncoderError.missingGeneratedGainMap
        }
        return JPEGPair(
            primary: Data(bytes[0..<primaryEnd]),
            secondary: Data(bytes[secondaryStart..<secondaryEnd])
        )
    }

    private func strippedJPEG(_ jpeg: Data, removeMPF: Bool) throws -> Data {
        let bytes = [UInt8](jpeg)
        let segments = try headerSegments(bytes)
        guard let sos = segments.first(where: { $0.marker == 0xDA }) else {
            throw FullAppleEncoderError.malformedJPEG("missing SOS")
        }

        var output = Array(bytes[0..<2])
        for segment in segments where segment.start < sos.start {
            let payload = Array(bytes[segment.payloadStart..<segment.end])
            let isXMP = segment.marker == 0xE1 && payload.starts(with: Self.xmpNamespace)
            let isISO = segment.marker == 0xE2 && payload.starts(with: Self.isoNamespace)
            let isMPF = segment.marker == 0xE2 && payload.starts(with: [0x4D, 0x50, 0x46, 0])
            if isXMP || isISO || (removeMPF && isMPF) { continue }
            output.append(contentsOf: bytes[segment.start..<segment.end])
        }
        output.append(contentsOf: bytes[sos.start..<bytes.count])
        return Data(output)
    }

    private func inserting(_ additions: [[UInt8]], into jpeg: Data, beforeMPF: Bool) throws -> Data {
        let bytes = [UInt8](jpeg)
        let segments = try headerSegments(bytes)
        let insertionOffset: Int
        if beforeMPF,
           let mpf = segments.first(where: {
               $0.marker == 0xE2 && Array(bytes[$0.payloadStart..<$0.end]).starts(with: [0x4D, 0x50, 0x46, 0])
           }) {
            insertionOffset = mpf.start
        } else if let firstHeaderSegment = segments.first {
            insertionOffset = firstHeaderSegment.start
        } else {
            insertionOffset = 2
        }

        var output = Array(bytes[0..<insertionOffset])
        additions.forEach { output.append(contentsOf: $0) }
        output.append(contentsOf: bytes[insertionOffset..<bytes.count])
        return Data(output)
    }

    private func primaryXMP(secondaryLength: Int) -> String {
        """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="HDRUtility ISOHDR">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
              xmlns:hdrgm="http://ns.adobe.com/hdr-gain-map/1.0/"
              xmlns:Container="http://ns.google.com/photos/1.0/container/"
              xmlns:Item="http://ns.google.com/photos/1.0/container/item/"
              hdrgm:Version="1.0">
              <Container:Directory>
                <rdf:Seq>
                  <rdf:li rdf:parseType="Resource"><Container:Item Item:Semantic="Primary" Item:Mime="image/jpeg"/></rdf:li>
                  <rdf:li rdf:parseType="Resource"><Container:Item Item:Semantic="GainMap" Item:Mime="image/jpeg" Item:Length="\(secondaryLength)"/></rdf:li>
                </rdf:Seq>
              </Container:Directory>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
    }

    private func secondaryXMP(metadata: FullAppleGainMapMetadata) -> String {
        """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="HDRUtility ISOHDR">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
              xmlns:hdrgm="http://ns.adobe.com/hdr-gain-map/1.0/"
              hdrgm:Version="1.0"
              hdrgm:GainMapMin="\(format(metadata.gainMapMin))"
              hdrgm:GainMapMax="\(format(metadata.gainMapMax))"
              hdrgm:Gamma="\(format(metadata.gamma))"
              hdrgm:OffsetSDR="\(format(metadata.offsetSDR))"
              hdrgm:OffsetHDR="\(format(metadata.offsetHDR))"
              hdrgm:HDRCapacityMin="\(format(metadata.capacityMin))"
              hdrgm:HDRCapacityMax="\(format(metadata.capacityMax))"
              hdrgm:BaseRenditionIsHDR="False"/>
          </rdf:RDF>
        </x:xmpmeta>
        """
    }

    private func isoMetadata(_ metadata: FullAppleGainMapMetadata) -> [UInt8] {
        let denominator: UInt32 = 1_000_000
        func signed(_ value: Double) -> Int32 {
            Int32(clamping: Int64((value * Double(denominator)).rounded()))
        }
        func unsigned(_ value: Double) -> UInt32 {
            UInt32(clamping: Int64((value * Double(denominator)).rounded()))
        }

        var bytes: [UInt8] = []
        appendBE(UInt16(0), to: &bytes)
        appendBE(UInt16(0), to: &bytes)
        bytes.append(0x40) // single channel, use base color space, explicit denominators
        appendBE(unsigned(metadata.capacityMin), to: &bytes)
        appendBE(denominator, to: &bytes)
        appendBE(unsigned(metadata.capacityMax), to: &bytes)
        appendBE(denominator, to: &bytes)
        appendBE(UInt32(bitPattern: signed(metadata.gainMapMin)), to: &bytes)
        appendBE(denominator, to: &bytes)
        appendBE(UInt32(bitPattern: signed(metadata.gainMapMax)), to: &bytes)
        appendBE(denominator, to: &bytes)
        appendBE(unsigned(metadata.gamma), to: &bytes)
        appendBE(denominator, to: &bytes)
        appendBE(UInt32(bitPattern: signed(metadata.offsetSDR)), to: &bytes)
        appendBE(denominator, to: &bytes)
        appendBE(UInt32(bitPattern: signed(metadata.offsetHDR)), to: &bytes)
        appendBE(denominator, to: &bytes)
        return bytes
    }

    private func appSegment(marker: UInt8, payload: [UInt8]) throws -> [UInt8] {
        guard payload.count + 2 <= Int(UInt16.max) else {
            throw FullAppleEncoderError.invalidMetadata("APP segment exceeds JPEG 64 KiB limit")
        }
        let length = UInt16(payload.count + 2)
        return [0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)] + payload
    }

    private func patchMPF(in data: inout Data, primaryLength: Int, secondaryLength: Int) throws {
        var bytes = [UInt8](data)
        let location = try mpfEntryLocation(bytes)
        writeU32(UInt32(primaryLength), at: location.entries + 4, bigEndian: location.bigEndian, in: &bytes)
        writeU32(UInt32(secondaryLength), at: location.entries + 20, bigEndian: location.bigEndian, in: &bytes)
        let relativeOffset = primaryLength - location.tiffBase
        guard relativeOffset >= 0 else { throw FullAppleEncoderError.malformedJPEG("negative MPF offset") }
        writeU32(UInt32(relativeOffset), at: location.entries + 24, bigEndian: location.bigEndian, in: &bytes)
        data = Data(bytes)
    }

    private func verifyMPF(_ data: Data, primaryLength: Int, secondaryLength: Int) throws -> Bool {
        let bytes = [UInt8](data)
        let location = try mpfEntryLocation(bytes)
        let storedPrimaryLength = Int(readU32(at: location.entries + 4, bigEndian: location.bigEndian, in: bytes))
        let storedSecondaryLength = Int(readU32(at: location.entries + 20, bigEndian: location.bigEndian, in: bytes))
        let storedSecondaryOffset = Int(readU32(at: location.entries + 24, bigEndian: location.bigEndian, in: bytes))
        return storedPrimaryLength == primaryLength &&
            storedSecondaryLength == secondaryLength &&
            location.tiffBase + storedSecondaryOffset == primaryLength
    }

    private func mpfEntryLocation(_ bytes: [UInt8]) throws -> (entries: Int, tiffBase: Int, bigEndian: Bool) {
        let segments = try headerSegments(bytes)
        guard let mpf = segments.first(where: {
            $0.marker == 0xE2 && Array(bytes[$0.payloadStart..<$0.end]).starts(with: [0x4D, 0x50, 0x46, 0])
        }) else {
            throw FullAppleEncoderError.malformedJPEG("missing MPF APP2 segment")
        }
        let tiffBase = mpf.payloadStart + 4
        guard tiffBase + 8 <= bytes.count else { throw FullAppleEncoderError.malformedJPEG("truncated MPF TIFF header") }
        let bigEndian: Bool
        if bytes[tiffBase] == 0x4D, bytes[tiffBase + 1] == 0x4D { bigEndian = true }
        else if bytes[tiffBase] == 0x49, bytes[tiffBase + 1] == 0x49 { bigEndian = false }
        else { throw FullAppleEncoderError.malformedJPEG("invalid MPF byte order") }

        let ifd = tiffBase + Int(readU32(at: tiffBase + 4, bigEndian: bigEndian, in: bytes))
        guard ifd + 2 <= bytes.count else { throw FullAppleEncoderError.malformedJPEG("invalid MPF IFD") }
        let count = Int(readU16(at: ifd, bigEndian: bigEndian, in: bytes))
        for index in 0..<count {
            let entry = ifd + 2 + index * 12
            guard entry + 12 <= bytes.count else { throw FullAppleEncoderError.malformedJPEG("truncated MPF entry") }
            if readU16(at: entry, bigEndian: bigEndian, in: bytes) == 0xB002 {
                let valueOffset = Int(readU32(at: entry + 8, bigEndian: bigEndian, in: bytes))
                let entries = tiffBase + valueOffset
                guard entries + 32 <= bytes.count else { throw FullAppleEncoderError.malformedJPEG("invalid MP entry array") }
                return (entries, tiffBase, bigEndian)
            }
        }
        throw FullAppleEncoderError.malformedJPEG("missing MPEntry tag")
    }

    private struct Segment {
        let marker: UInt8
        let start: Int
        let payloadStart: Int
        let end: Int
    }

    private func headerSegments(_ bytes: [UInt8]) throws -> [Segment] {
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
            throw FullAppleEncoderError.malformedJPEG("missing SOI")
        }
        var segments: [Segment] = []
        var cursor = 2
        while cursor + 1 < bytes.count {
            guard bytes[cursor] == 0xFF else { throw FullAppleEncoderError.malformedJPEG("expected marker at \(cursor)") }
            let marker = bytes[cursor + 1]
            if marker == 0xD9 { break }
            if marker == 0xDA {
                guard cursor + 4 <= bytes.count else { throw FullAppleEncoderError.malformedJPEG("truncated SOS") }
                let length = Int(bytes[cursor + 2]) << 8 | Int(bytes[cursor + 3])
                segments.append(Segment(marker: marker, start: cursor, payloadStart: cursor + 4, end: cursor + 2 + length))
                break
            }
            guard cursor + 4 <= bytes.count else { throw FullAppleEncoderError.malformedJPEG("truncated marker") }
            let length = Int(bytes[cursor + 2]) << 8 | Int(bytes[cursor + 3])
            guard length >= 2, cursor + 2 + length <= bytes.count else {
                throw FullAppleEncoderError.malformedJPEG("invalid segment length")
            }
            let end = cursor + 2 + length
            segments.append(Segment(marker: marker, start: cursor, payloadStart: cursor + 4, end: end))
            cursor = end
        }
        return segments
    }

    private static func jpegEnd(in bytes: [UInt8], startingAt start: Int) -> Int? {
        guard start + 1 < bytes.count, bytes[start] == 0xFF, bytes[start + 1] == 0xD8 else { return nil }
        var cursor = start + 2
        var insideScan = false

        while cursor < bytes.count {
            if insideScan {
                guard let markerStart = bytes[cursor...].firstIndex(of: 0xFF) else { return nil }
                cursor = markerStart
            } else if bytes[cursor] != 0xFF {
                return nil
            }

            let markerStart = cursor
            while cursor < bytes.count, bytes[cursor] == 0xFF { cursor += 1 }
            guard cursor < bytes.count else { return nil }
            let marker = bytes[cursor]
            cursor += 1

            if insideScan && (marker == 0x00 || (0xD0...0xD7).contains(marker)) {
                continue
            }
            if marker == 0xD9 { return cursor }
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) {
                insideScan = false
                continue
            }

            guard cursor + 1 < bytes.count else { return nil }
            let length = Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1])
            guard length >= 2, markerStart + 2 + length <= bytes.count else { return nil }
            cursor = markerStart + 2 + length
            insideScan = marker == 0xDA
        }
        return nil
    }

    private func format(_ value: Double) -> String {
        String(format: "%.9g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func appendBE<T: FixedWidthInteger>(_ value: T, to bytes: inout [UInt8]) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
    }

    private func readU16(at offset: Int, bigEndian: Bool, in bytes: [UInt8]) -> UInt16 {
        let value = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        return bigEndian ? value : value.byteSwapped
    }

    private func readU32(at offset: Int, bigEndian: Bool, in bytes: [UInt8]) -> UInt32 {
        let value = UInt32(bytes[offset]) << 24 |
            UInt32(bytes[offset + 1]) << 16 |
            UInt32(bytes[offset + 2]) << 8 |
            UInt32(bytes[offset + 3])
        return bigEndian ? value : value.byteSwapped
    }

    private func writeU32(_ value: UInt32, at offset: Int, bigEndian: Bool, in bytes: inout [UInt8]) {
        let encoded = bigEndian ? value : value.byteSwapped
        bytes[offset] = UInt8((encoded >> 24) & 0xFF)
        bytes[offset + 1] = UInt8((encoded >> 16) & 0xFF)
        bytes[offset + 2] = UInt8((encoded >> 8) & 0xFF)
        bytes[offset + 3] = UInt8(encoded & 0xFF)
    }

    private static func findSubsequence(_ bytes: [UInt8], _ needle: [UInt8], from start: Int) -> Int? {
        guard !needle.isEmpty, start <= bytes.count - needle.count else { return nil }
        for index in start...(bytes.count - needle.count) where bytes[index..<(index + needle.count)].elementsEqual(needle) {
            return index
        }
        return nil
    }

    private func containsSubsequence(_ bytes: [UInt8], _ needle: [UInt8]) -> Bool {
        Self.findSubsequence(bytes, needle, from: 0) != nil
    }
}
