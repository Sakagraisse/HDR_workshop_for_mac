import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
@testable import HDRUtilityKit

struct FullAppleJPEGTests {
    @Test func assemblesGoogleXMPISOAndValidMPFWithoutAppleLegacyMarker() throws {
        let source = syntheticApplePair()
        let metadata = FullAppleGainMapMetadata(
            gainMapMin: 0,
            gainMapMax: 2,
            gamma: 1,
            offsetSDR: 0.000_001,
            offsetHDR: 0.000_001,
            capacityMin: 0,
            capacityMax: 2
        )

        let assembler = FullAppleJPEGAssembler()
        let output = try assembler.assemble(appleContainer: source, metadata: metadata)
        let verification = try assembler.verify(output)

        #expect(verification.hasUltraHDRXMP)
        #expect(verification.hasGContainer)
        #expect(verification.hasISOPrimary)
        #expect(verification.hasISOSecondary)
        #expect(verification.hasValidMPF)
        #expect(!verification.hasAppleLegacyMarker)

    }

    @Test func parsesAppleToneMapMetadataForGoogleAndISOReuse() throws {
        let xmp = """
        <HDRToneMap:BaseHeadroom>0.000000</HDRToneMap:BaseHeadroom>
        <HDRToneMap:AlternateHeadroom>2.000000</HDRToneMap:AlternateHeadroom>
        <HDRToneMap:GainMapMin>0.125000</HDRToneMap:GainMapMin>
        <HDRToneMap:GainMapMax>1.999300</HDRToneMap:GainMapMax>
        <HDRToneMap:Gamma>1.000000</HDRToneMap:Gamma>
        <HDRToneMap:BaseOffset>0.000010</HDRToneMap:BaseOffset>
        <HDRToneMap:AlternateOffset>0.000020</HDRToneMap:AlternateOffset>
        """

        let metadata = try FullAppleGainMapMetadata.parse(from: Data(xmp.utf8), fallbackHeadroom: 4)
        #expect(metadata.gainMapMin == 0.125)
        #expect(metadata.gainMapMax == 1.9993)
        #expect(metadata.gamma == 1)
        #expect(metadata.offsetSDR == 0.00001)
        #expect(metadata.offsetHDR == 0.00002)
        #expect(metadata.capacityMin == 0)
        #expect(metadata.capacityMax == 2)
    }

    @Test func ignoresEOIBytePatternInsideJPEGMetadata() throws {
        let appPayload: [UInt8] = [0x41, 0xFF, 0xD9, 0x42]
        let appLength = UInt16(appPayload.count + 2)
        let scan: [UInt8] = [0xFF, 0xDA, 0x00, 0x02, 0x11, 0xFF, 0x00, 0xD9, 0xFF, 0xD9]
        let primary = [0xFF, 0xD8, 0xFF, 0xE1, UInt8(appLength >> 8), UInt8(appLength & 0xFF)] + appPayload + scan
        let secondary = [0xFF, 0xD8] + scan

        let pair = try FullAppleJPEGAssembler.splitJPEGPair(Data(primary + secondary))

        #expect(pair.primary.count == primary.count)
        #expect(pair.secondary.count == secondary.count)
    }

    @Test func encodesRealHDRUsingOnlyAppleFrameworks() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "full-apple-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let hdrURL = folder.appending(path: "source.exr")
        let outputURL = folder.appending(path: "output.jpg")
        try writeHDRFixture(to: hdrURL)

        let verification = try FullAppleJPEGEncoder().encode(
            hdrURL: hdrURL,
            sdrURL: nil,
            outputURL: outputURL,
            quality: 0.95,
            colorSpaceKind: .displayP3
        )

        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        #expect(verification.hasUltraHDRXMP)
        #expect(verification.hasGContainer)
        #expect(verification.hasISOPrimary)
        #expect(verification.hasISOSecondary)
        #expect(verification.hasValidMPF)
        #expect(!verification.hasAppleLegacyMarker)

        let source = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let isoAuxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source,
            0,
            kCGImageAuxiliaryDataTypeISOGainMap
        )
        #expect(isoAuxiliary != nil)

        if let validationPath = ProcessInfo.processInfo.environment["FULL_APPLE_VALIDATION_OUTPUT"] {
            try Data(contentsOf: outputURL).write(
                to: URL(fileURLWithPath: validationPath),
                options: .atomic
            )
        }
    }

    @Test func encodesRGBJPEGRecognizedByImageIO() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "isohdr-rgb-jpeg-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let hdrURL = folder.appending(path: "source.exr")
        let outputURL = folder.appending(path: "output.jpg")
        try writeHDRFixture(to: hdrURL)

        _ = try FullAppleJPEGEncoder().encode(
            hdrURL: hdrURL,
            sdrURL: nil,
            outputURL: outputURL,
            quality: 0.95,
            colorSpaceKind: .displayP3,
            rgbGainMap: true
        )

        let record = try ImageAnalyzer().analyze(url: outputURL)
        #expect(record.gainMapSignals.hasISOAuxiliary)
        #expect(record.gainMapSignals.hasUltraHDRXMP)
        #expect(record.gainMapSignals.hasGContainer)
        #expect(record.gainMapSignals.gainMapChannelCount == 3)
        #expect((record.gainMapSignals.nativeHDRHeadroom ?? 0) > 1)
        #expect(!record.gainMapSignals.hasAppleLegacyMarker)

        if let validationPath = ProcessInfo.processInfo.environment["ISOHDR_RGB_VALIDATION_OUTPUT"] {
            try Data(contentsOf: outputURL).write(
                to: URL(fileURLWithPath: validationPath),
                options: .atomic
            )
        }
    }

    @Test func encodesISOHEICWithMonochromeAndRGBGainMaps() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "isohdr-heic-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let hdrURL = folder.appending(path: "source.exr")
        try writeHDRFixture(to: hdrURL)

        for rgb in [false, true] {
            let outputURL = folder.appending(path: rgb ? "rgb.heic" : "mono.heic")
            let verification = try FullAppleHEICEncoder().encode(
                hdrURL: hdrURL,
                sdrURL: nil,
                outputURL: outputURL,
                quality: 0.95,
                colorSpaceKind: .displayP3,
                rgbGainMap: rgb
            )

            #expect(verification.hasISOAuxiliary)
            #expect(verification.gainMapChannels == (rgb ? 3 : 1))
            #expect(verification.contentHeadroom > 1)

            let record = try ImageAnalyzer().analyze(url: outputURL)
            #expect(record.container == .heic)
            #expect(record.gainMapSignals.hasISOAuxiliary)
            #expect(!record.gainMapSignals.hasAppleAuxiliary)
            #expect(record.gainMapSignals.gainMapChannelCount == (rgb ? 3 : 1))
        }
    }

    @Test func compatiblePresetDefaultsToMonochromeDualTaggedJPEG() {
        var request = FullAppleConversionRequest(
            quality: 0.7,
            colorSpace: .sRGB,
            outputFormat: .heic,
            gainMapChannels: .rgb
        )

        request.restoreCompatibleJPEGDefaults()

        #expect(request.outputFormat == .jpeg)
        #expect(request.gainMapChannels == .monochrome)
        #expect(request.colorSpace == .displayP3)
        #expect(request.quality == 0.95)
    }

    private func syntheticApplePair() -> Data {
        let mpfPayload: [UInt8] = [
            0x4D, 0x50, 0x46, 0x00,
            0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08,
            0x00, 0x03,
            0xB0, 0x00, 0x00, 0x07, 0x00, 0x00, 0x00, 0x04, 0x30, 0x31, 0x30, 0x30,
            0xB0, 0x01, 0x00, 0x04, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02,
            0xB0, 0x02, 0x00, 0x07, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x32,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x03, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ]
        let length = UInt16(mpfPayload.count + 2)
        let mpf = [0xFF, 0xE2, UInt8(length >> 8), UInt8(length & 0xFF)] + mpfPayload
        let minimalScan: [UInt8] = [0xFF, 0xDA, 0x00, 0x02, 0xFF, 0xD9]
        let primary = [0xFF, 0xD8] + mpf + minimalScan
        let appleXMP = Array("http://ns.adobe.com/xap/1.0/\0urn:com:apple:photo:2020:aux:hdrgainmap".utf8)
        let appleLength = UInt16(appleXMP.count + 2)
        let secondary = [0xFF, 0xD8, 0xFF, 0xE1, UInt8(appleLength >> 8), UInt8(appleLength & 0xFF)] + appleXMP + minimalScan
        return Data(primary + secondary)
    }

    private func writeHDRFixture(to url: URL) throws {
        let width = 32
        let height = 16
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width where x >= width / 2 {
                let offset = (y * width + x) * 4
                pixels[offset] = 4
                pixels[offset + 1] = 4
                pixels[offset + 2] = 4
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let image = CIImage(
            bitmapData: data,
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: colorSpace
        )
        try CIContext().writeOpenEXRRepresentation(of: image, to: url, options: [:])
    }
}
