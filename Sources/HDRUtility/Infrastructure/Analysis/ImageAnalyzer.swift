import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageAnalyzer {
    private let classifier = HDRClassifier()

    func analyze(url: URL) throws -> HDRFileRecord {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw AnalyzerError.unreadableFile(url.lastPathComponent)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let signals = inspectGainMapSignals(url: url, source: source)
        let metadata = flattenMetadata(properties) + signalMetadata(signals)
        let container = inferContainer(url: url, source: source)
        let bitDepth = inferBitDepth(properties: properties)
        let colorSpace = inferColorSpace(properties: properties, metadata: metadata)
        let pixelSize = inferSize(properties: properties)
        let result = classifier.classify(
            container: container,
            bitDepth: bitDepth,
            colorSpace: colorSpace,
            metadata: metadata,
            gainMapSignals: signals
        )

        return HDRFileRecord(
            url: url,
            container: container,
            pixelSize: pixelSize,
            bitDepth: bitDepth,
            colorSpace: colorSpace,
            transferFunction: result.0,
            hdrKind: result.1,
            gainMap: result.2,
            gainMapSignals: signals,
            metadata: metadata,
            diagnostics: result.3,
            compatibility: result.4
        )
    }

    private func inferContainer(url: URL, source: CGImageSource) -> ImageContainer {
        if let type = CGImageSourceGetType(source) as String?,
           let utType = UTType(type) {
            if utType.conforms(to: .jpeg) {
                return .jpeg
            }
            if utType.identifier == "public.heic" || utType.identifier == "public.heif" {
                return .heic
            }
            if utType.identifier == "public.avif" {
                return .avif
            }
            if utType.conforms(to: .png) {
                return .png
            }
            if utType.conforms(to: .tiff) {
                return .tiff
            }
        }

        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return .jpeg
        case "heic", "heif":
            return .heic
        case "avif":
            return .avif
        case "png":
            return .png
        case "tif", "tiff":
            return .tiff
        case "exr":
            return .exr
        case "jxl":
            return .jxl
        default:
            return .unknown
        }
    }

    private func inferBitDepth(properties: [CFString: Any]) -> Int? {
        if let depth = properties[kCGImagePropertyDepth] as? Int {
            return depth
        }
        return nil
    }

    private func inferColorSpace(properties: [CFString: Any], metadata: [MetadataEntry]) -> ColorSpaceKind? {
        if let profileName = properties[kCGImagePropertyProfileName] as? String {
            return matchColorSpace(profileName)
        }

        if let matched = metadata.first(where: { $0.key.lowercased().contains("profile") || $0.key.lowercased().contains("color") }) {
            return matchColorSpace(matched.value)
        }

        return nil
    }

    private func matchColorSpace(_ value: String) -> ColorSpaceKind {
        let lowered = value.lowercased()
        if lowered.contains("display p3") {
            return .displayP3
        }
        if lowered.contains("2020") || lowered.contains("rec.2020") || lowered.contains("bt.2020") {
            return .rec2020
        }
        if lowered.contains("extended linear srgb") {
            return .extendedLinearSRGB
        }
        if lowered.contains("srgb") {
            return .sRGB
        }
        return .unknown
    }

    private func inferSize(properties: [CFString: Any]) -> CGSize? {
        guard
            let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
            let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
        else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private func flattenMetadata(_ properties: [CFString: Any]) -> [MetadataEntry] {
        var items: [MetadataEntry] = []

        for (key, value) in properties.sorted(by: { lhs, rhs in
            (lhs.key as String) < (rhs.key as String)
        }) {
            let keyString = key as String
            if let nested = value as? [CFString: Any] {
                for (nestedKey, nestedValue) in nested.sorted(by: { lhs, rhs in
                    (lhs.key as String) < (rhs.key as String)
                }) {
                    items.append(MetadataEntry(key: "\(keyString).\(nestedKey)", value: String(describing: nestedValue)))
                }
            } else {
                items.append(MetadataEntry(key: keyString, value: String(describing: value)))
            }
        }

        return items
    }

    private func inspectGainMapSignals(url: URL, source: CGImageSource) -> GainMapSignals {
        let data = (try? Data(contentsOf: url, options: .mappedIfSafe)) ?? Data()
        let appleAuxiliaryInfo = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source,
            0,
            kCGImageAuxiliaryDataTypeHDRGainMap
        )
        let isoAuxiliaryInfo = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source,
            0,
            kCGImageAuxiliaryDataTypeISOGainMap
        )
        let auxiliaryInfo = isoAuxiliaryInfo ?? appleAuxiliaryInfo
        let expandedImage = CIImage(contentsOf: url, options: [.expandToHDR: true])

        return GainMapSignals(
            hasAppleAuxiliary: appleAuxiliaryInfo != nil,
            hasISOAuxiliary: isoAuxiliaryInfo != nil,
            hasAppleLegacyMarker: containsASCII("urn:com:apple:photo:2020:aux:hdrgainmap", in: data),
            hasISO21496Marker: containsASCII("urn:iso:std:iso:ts:21496:-1", in: data),
            hasUltraHDRXMP: containsASCII("hdrgm:Version", in: data) || containsASCII("hdrgm:version", in: data),
            hasGContainer: containsASCII("Container:Directory", in: data) ||
                containsASCII("http://ns.google.com/photos/1.0/container/", in: data),
            hasMPF: data.range(of: Data([0x4D, 0x50, 0x46, 0x00])) != nil,
            nativeHDRHeadroom: expandedImage.map { Double($0.contentHeadroom) },
            gainMapChannelCount: auxiliaryInfo.flatMap(auxiliaryChannelCount),
            gainMapSize: auxiliaryInfo.flatMap(auxiliarySize)
        )
    }

    private func auxiliaryChannelCount(_ auxiliary: CFDictionary) -> Int? {
        let dictionary = auxiliary as NSDictionary
        let description = dictionary[kCGImageAuxiliaryDataInfoDataDescription as String] as? NSDictionary
        let pixelFormat = description?["PixelFormat"] as? NSNumber
        let metadata = String(describing: dictionary[kCGImageAuxiliaryDataInfoMetadata as String] ?? "")

        if metadata.contains("HDRToneMap:[1]") || metadata.contains("HDRToneMap:[2]") {
            return 3
        }
        if pixelFormat?.uint32Value == 0x4C30_3038 { // 'L008' / one-component 8-bit
            return 1
        }
        return pixelFormat == nil ? nil : 3
    }

    private func auxiliarySize(_ auxiliary: CFDictionary) -> CGSize? {
        let dictionary = auxiliary as NSDictionary
        guard let description = dictionary[kCGImageAuxiliaryDataInfoDataDescription as String] as? NSDictionary,
              let width = description["Width"] as? NSNumber,
              let height = description["Height"] as? NSNumber else {
            return nil
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private func containsASCII(_ value: String, in data: Data) -> Bool {
        data.range(of: Data(value.utf8)) != nil
    }

    private func signalMetadata(_ signals: GainMapSignals) -> [MetadataEntry] {
        var entries = [
            MetadataEntry(key: "Analyze.Apple legacy auxiliary", value: signals.hasAppleAuxiliary ? "Recognized by ImageIO" : "Not detected"),
            MetadataEntry(key: "Analyze.ISO 21496-1 auxiliary", value: signals.hasISOAuxiliary ? "Recognized by ImageIO" : "Not detected"),
            MetadataEntry(key: "Analyze.ISO 21496-1 marker", value: signals.hasISO21496Marker ? "Present" : "Not detected"),
            MetadataEntry(key: "Analyze.Ultra HDR XMP", value: signals.hasUltraHDRXMP ? "Present" : "Not detected"),
            MetadataEntry(key: "Analyze.GContainer", value: signals.hasGContainer ? "Present" : "Not detected"),
            MetadataEntry(key: "Analyze.MPF", value: signals.hasMPF ? "Present" : "Not detected")
        ]
        if let headroom = signals.nativeHDRHeadroom {
            entries.append(MetadataEntry(
                key: "Analyze.Core Image HDR headroom",
                value: headroom.formatted(.number.precision(.fractionLength(3)))
            ))
        }
        return entries
    }
}

enum AnalyzerError: LocalizedError {
    case unreadableFile(String)

    var errorDescription: String? {
        switch self {
        case let .unreadableFile(name):
            "Unable to read image data for \(name)."
        }
    }
}
