import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import HDRUtilityKit

@Suite("ProRAW batch selection")
struct ProRAWBatchTests {
    @Test("Parallel conversion defaults and choices")
    func parallelConversionDefaults() {
        let request = ProRAWBatchConversionRequest()

        #expect(request.parallelConversions == 10)
        #expect(request.quality == 0.90)
        #expect(request.resizeToApple24MP == false)
        #expect(ProRAWBatchConversionRequest.parallelConversionChoices == Array(stride(from: 2, through: 20, by: 2)))
    }

    @Test("A source without a gain map falls back to SDR")
    func fallsBackToSDR() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = folder.appending(path: "source.heic")
        let output = folder.appending(path: "output.heic")
        let image = CIImage(color: CIColor(red: 0.35, green: 0.5, blue: 0.7))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
        try CIContext().writeHEIFRepresentation(
            of: image,
            to: source,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
            options: [:]
        )

        let verification = try ProRAWAppleHEICEncoder().encode(
            sourceURL: source,
            outputURL: output,
            quality: 0.90,
            resizeToApple24MP: false
        )

        #expect(verification.kind == .sdr)
        #expect(FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
        #expect(try ImageAnalyzer().analyze(url: output).gainMapSignals.hasGainMapSignal == false)
    }

    @Test("Configured parallel batch converts every source")
    func convertsConfiguredParallelBatch() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let outputFolder = folder.appending(path: "output")
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var sources: [URL] = []
        let fixtureEncoder = FullAppleHEICEncoder()
        for index in 0..<12 {
            let hdrSource = folder.appending(path: "source-\(index).exr")
            let source = folder.appending(path: "source-\(index).heic")
            try writeHDRFixture(to: hdrSource)
            _ = try fixtureEncoder.encode(
                hdrURL: hdrSource,
                sdrURL: nil,
                outputURL: source,
                quality: 0.95,
                colorSpaceKind: .displayP3,
                rgbGainMap: false
            )
            sources.append(source)
        }

        var request = ProRAWBatchConversionRequest()
        request.sources = sources
        request.outputFolder = outputFolder
        request.parallelConversions = 10

        let job = await ProRAWBatchConversionService().convert(request: request)

        #expect(job.outputURLs.count == sources.count)
        #expect(job.log.contains("Parallel conversions: 10 (configured: 10)"))
        #expect(job.log.contains("Gain map: conservée lorsqu’elle est présente"))
        if let output = job.outputURLs.first {
            let record = try ImageAnalyzer().analyze(url: output)
            #expect(record.gainMapSignals.hasISOAuxiliary)
            #expect(record.gainMapSignals.gainMapChannelCount == 1)
        }
    }

    @Test("Only DNG files are accepted and duplicates are removed")
    @MainActor
    func filtersSources() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let dng = folder.appending(path: "IMG_0001.DNG")
        let jpeg = folder.appending(path: "IMG_0001.jpg")
        FileManager.default.createFile(atPath: dng.path, contents: Data())
        FileManager.default.createFile(atPath: jpeg.path, contents: Data())

        let result = ProRAWBatchViewModel.expand([folder, dng])

        #expect(result == [dng.standardizedFileURL])
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
