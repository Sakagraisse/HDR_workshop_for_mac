import Foundation
import Testing
@testable import HDRUtilityKit

struct HDRClassifierTests {
    @Test func detectsUltraHDRMarkers() {
        let classifier = HDRClassifier()
        let metadata = [
            MetadataEntry(key: "XMP.hdrgm:Version", value: "1.0"),
            MetadataEntry(key: "XMP.Container", value: "GContainer")
        ]

        let result = classifier.classify(
            container: .jpeg,
            bitDepth: 8,
            colorSpace: .displayP3,
            metadata: metadata
        )

        #expect(result.1 == .ultraHDR)
        #expect(result.2?.kind == .ultraHDR)
        #expect(result.4.instagramReady)
    }

    @Test func flagsSuspiciousHDRInSRGB() {
        let classifier = HDRClassifier()
        let metadata = [
            MetadataEntry(key: "Transfer", value: "PQ")
        ]

        let result = classifier.classify(
            container: .jpeg,
            bitDepth: 10,
            colorSpace: .sRGB,
            metadata: metadata
        )

        #expect(result.1 == .pqHDR)
        #expect(result.3.contains(where: { $0.severity == .warning }))
    }

    @Test func classifiesDualTaggedRGBGainMapWithoutConfusingItWithAppleLegacy() {
        let signals = GainMapSignals(
            hasAppleAuxiliary: false,
            hasISOAuxiliary: false,
            hasAppleLegacyMarker: false,
            hasISO21496Marker: true,
            hasUltraHDRXMP: true,
            hasGContainer: true,
            hasMPF: true,
            nativeHDRHeadroom: 1,
            gainMapChannelCount: 3,
            gainMapSize: CGSize(width: 500, height: 500)
        )

        let result = HDRClassifier().classify(
            container: .jpeg,
            bitDepth: 8,
            colorSpace: .sRGB,
            metadata: [],
            gainMapSignals: signals
        )

        #expect(result.2?.kind == .hybrid)
        #expect(result.2?.channelModel == .rgb)
        #expect(result.4.gainMapFormats.appleLegacy == .notDetected)
        #expect(result.4.gainMapFormats.iso21496 == .declared)
        #expect(result.4.gainMapFormats.ultraHDRV1 == .declared)
        #expect(result.4.instagramReady)
        #expect(!result.3.contains(where: { $0.severity == .warning }))
    }

    @Test func imageAnalyzerSeparatesNativeAppleISOAndDualTaggedJPEG() throws {
        let assets = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "TestAssets/HDRTestPatterns")
        let analyzer = ImageAnalyzer()

        let apple = try analyzer.analyze(
            url: assets.appending(path: "master-linear-srgb-half-right-4x-apple-gainmap.heic")
        )
        #expect(apple.gainMapSignals.hasAppleAuxiliary)
        #expect(!apple.gainMapSignals.hasISOAuxiliary)
        #expect(apple.gainMap?.kind == .apple)
        #expect(apple.gainMap?.channelModel == .monochrome)

        let iso = try analyzer.analyze(
            url: assets.appending(path: "master-linear-srgb-half-right-4x-iso-gainmap.heic")
        )
        #expect(!iso.gainMapSignals.hasAppleAuxiliary)
        #expect(iso.gainMapSignals.hasISOAuxiliary)
        #expect(iso.gainMap?.kind == .iso21496)
        #expect(iso.gainMap?.channelModel == .rgb)

        let dualTagged = try analyzer.analyze(
            url: assets.appending(path: "ultrahdr-half-right-plus2stops.jpg")
        )
        #expect(dualTagged.gainMapSignals.hasISOAuxiliary)
        #expect(dualTagged.gainMapSignals.hasUltraHDRXMP)
        #expect(dualTagged.gainMapSignals.hasGContainer)
        #expect(dualTagged.gainMap?.kind == .hybrid)
        #expect(dualTagged.gainMap?.channelModel == .monochrome)
    }
}

struct ConversionModelTests {
    @Test func conversionJobKeepsPrimaryAndAdditionalOutputs() {
        let first = URL(fileURLWithPath: "/tmp/output.jpg")
        let second = URL(fileURLWithPath: "/tmp/output.report.md")
        let job = ConversionJob(
            title: "Instagram",
            engine: .libUltraHDR,
            status: .succeeded,
            log: [],
            outputURLs: [first, second]
        )

        #expect(job.outputURL == first)
        #expect(job.outputURLs == [first, second])
    }

    @Test func instagramRatioValidationUsesOfficialBounds() {
        #expect(UltraHDRBridgeClient.isInstagramRatioSupported(0.75))
        #expect(UltraHDRBridgeClient.isInstagramRatioSupported(1.0))
        #expect(UltraHDRBridgeClient.isInstagramRatioSupported(1.91))
        #expect(!UltraHDRBridgeClient.isInstagramRatioSupported(0.749))
        #expect(!UltraHDRBridgeClient.isInstagramRatioSupported(1.911))
    }

    @Test func appleCommandIncludesCustomSDRBase() throws {
        let tools = URL(fileURLWithPath: "/tmp/tools")
        let hdr = URL(fileURLWithPath: "/tmp/hdr.tiff")
        let sdr = URL(fileURLWithPath: "/tmp/sdr.jpg")
        var request = AppleConversionRequest()
        request.hdrSource = hdr
        request.sdrBase = sdr
        request.outputFolder = URL(fileURLWithPath: "/tmp/output")

        let command = try AppleGainMapCommandBuilder().build(request: request, toolsDirectory: tools)
        #expect(command.arguments.contains("-b"))
        #expect(command.arguments.contains(sdr.path))
    }

    @Test func bridgeProtocolIsVersioned() throws {
        let request = UltraHDRBridgeRequest(operation: .inspect, input: "/tmp/image.jpg")
        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["protocolVersion"] as? Int == 1)
        #expect(json["operation"] as? String == "inspect")
    }
}
