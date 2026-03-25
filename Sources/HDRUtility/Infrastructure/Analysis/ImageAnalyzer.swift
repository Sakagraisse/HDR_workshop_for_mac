import CoreGraphics
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
        let metadata = flattenMetadata(properties)
        let container = inferContainer(url: url, source: source)
        let bitDepth = inferBitDepth(properties: properties)
        let colorSpace = inferColorSpace(properties: properties, metadata: metadata)
        let pixelSize = inferSize(properties: properties)
        let result = classifier.classify(
            container: container,
            bitDepth: bitDepth,
            colorSpace: colorSpace,
            metadata: metadata
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
