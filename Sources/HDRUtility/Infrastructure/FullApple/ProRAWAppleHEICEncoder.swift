import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ProRAWHEICVerification: Sendable {
    let width: Int
    let height: Int
    let detail: String
    let kind: ProRAWHEICOutputKind
}

enum ProRAWHEICOutputKind: Hashable, Sendable {
    case hdr
    case sdr
}

struct ProRAWAppleHEICEncoder: Sendable {
    private static let apple24MPMaxPixelSize = 5712

    func encode(
        sourceURL: URL,
        outputURL: URL,
        quality: Double,
        resizeToApple24MP: Bool
    ) throws -> ProRAWHEICVerification {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw ProRAWAppleHEICEncoderError.unableToOpen(sourceURL.lastPathComponent)
        }
        _ = try inspectImageSource(source)
        let encodedData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            encodedData as CFMutableData,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw ProRAWAppleHEICEncoderError.unableToCreateDestination
        }

        let boundedQuality = min(max(quality, 0), 1)
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: boundedQuality,
            kCGImageDestinationPreserveGainMap: true
        ]
        if resizeToApple24MP {
            properties[kCGImageDestinationImageMaxPixelSize] = Self.apple24MPMaxPixelSize
        }
        CGImageDestinationAddImageFromSource(
            destination,
            source,
            0,
            properties as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else {
            throw ProRAWAppleHEICEncoderError.encodingFailed
        }
        guard encodedData.length > 0 else {
            throw ProRAWAppleHEICEncoderError.emptyEncodedData
        }
        guard let encodedSource = CGImageSourceCreateWithData(encodedData as CFData, nil) else {
            throw ProRAWAppleHEICEncoderError.invalidEncodedData
        }
        let verification = try inspectImageSource(encodedSource)

        do {
            try (encodedData as Data).write(to: outputURL)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw ProRAWAppleHEICEncoderError.unableToWrite(
                outputURL.lastPathComponent,
                error.localizedDescription
            )
        }
        return verification
    }

    private func inspectImageSource(_ source: CGImageSource) throws -> ProRAWHEICVerification {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else {
            throw ProRAWAppleHEICEncoderError.invalidSource
        }

        let appleAuxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source,
            0,
            kCGImageAuxiliaryDataTypeHDRGainMap
        )
        let isoAuxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source,
            0,
            kCGImageAuxiliaryDataTypeISOGainMap
        )

        let hasGainMap = appleAuxiliary != nil || isoAuxiliary != nil
        let detail: String
        if appleAuxiliary != nil {
            detail = "HDR · gain map Apple conservée"
        } else if isoAuxiliary != nil {
            detail = "HDR · gain map ISO conservée"
        } else {
            detail = "SDR · aucune gain map dans le ProRAW"
        }

        return ProRAWHEICVerification(
            width: width,
            height: height,
            detail: detail,
            kind: hasGainMap ? .hdr : .sdr
        )
    }
}

enum ProRAWAppleHEICEncoderError: LocalizedError {
    case unableToOpen(String)
    case unableToCreateDestination
    case encodingFailed
    case emptyEncodedData
    case invalidEncodedData
    case unableToWrite(String, String)
    case invalidSource

    var errorDescription: String? {
        switch self {
        case .unableToOpen(let name): "ImageIO cannot open \(name)."
        case .unableToCreateDestination: "ImageIO cannot create the HEIC destination."
        case .encodingFailed: "Apple HEIC encoding failed."
        case .emptyEncodedData: "Apple HEIC encoding returned no data."
        case .invalidEncodedData: "ImageIO could not read the encoded HEIC data."
        case .unableToWrite(let name, let reason): "Could not write \(name): \(reason)"
        case .invalidSource: "ImageIO could not read the ProRAW dimensions."
        }
    }
}
