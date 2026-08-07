import CoreGraphics
import CoreImage
import Foundation
import ImageIO

struct ISOHDRHEICVerification: Equatable, Sendable {
    let width: Int
    let height: Int
    let gainMapChannels: Int
    let contentHeadroom: Double
    let hasISOAuxiliary: Bool
}

final class FullAppleHEICEncoder {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func encode(
        hdrURL: URL,
        sdrURL: URL?,
        outputURL: URL,
        quality: Double,
        colorSpaceKind: ColorSpaceKind,
        rgbGainMap: Bool
    ) throws -> ISOHDRHEICVerification {
        guard let hdrImage = loadHDRImage(from: hdrURL) else {
            throw FullAppleEncoderError.unableToLoad(hdrURL.lastPathComponent)
        }
        let sourceHeadroom = hdrImage.contentHeadroom > 1.000_1
            ? Double(hdrImage.contentHeadroom)
            : measuredHeadroom(hdrImage)
        guard sourceHeadroom > 1.000_1 else {
            throw FullAppleEncoderError.sourceIsNotHDR(hdrURL.lastPathComponent)
        }
        let signaledHDRImage: CIImage
        if hdrImage.contentHeadroom > 1.000_1 {
            signaledHDRImage = hdrImage
        } else if #available(macOS 16.0, *) {
            signaledHDRImage = hdrImage.settingContentHeadroom(Float(sourceHeadroom))
        } else {
            signaledHDRImage = hdrImage
        }

        let sdrImage: CIImage
        if let sdrURL {
            guard let customSDR = CIImage(
                contentsOf: sdrURL,
                options: [.applyOrientationProperty: true]
            ) else {
                throw FullAppleEncoderError.unableToLoad(sdrURL.lastPathComponent)
            }
            guard CGRectIntegral(customSDR.extent).size == CGRectIntegral(hdrImage.extent).size else {
                throw FullAppleEncoderError.mismatchedDimensions
            }
            sdrImage = customSDR
        } else {
            sdrImage = signaledHDRImage.applyingFilter(
                "CIToneMapHeadroom",
                parameters: [
                    "inputSourceHeadroom": sourceHeadroom,
                    "inputTargetHeadroom": 1.0
                ]
            )
        }

        return try writeAdaptiveHDR(
            sdrImage: sdrImage,
            hdrImage: signaledHDRImage,
            outputURL: outputURL,
            quality: quality,
            colorSpaceKind: colorSpaceKind,
            rgbGainMap: rgbGainMap
        )
    }

    private func writeAdaptiveHDR(
        sdrImage: CIImage,
        hdrImage: CIImage,
        outputURL: URL,
        quality: Double,
        colorSpaceKind: ColorSpaceKind,
        rgbGainMap: Bool
    ) throws -> ISOHDRHEICVerification {
        let temporaryURL = outputURL.deletingLastPathComponent()
            .appending(path: ".isohdr-\(UUID().uuidString).tmp.heic")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): min(max(quality, 0), 1),
            .hdrImage: hdrImage,
            .hdrGainMapAsRGB: rgbGainMap
        ]
        do {
            try context.writeHEIFRepresentation(
                of: sdrImage,
                to: temporaryURL,
                format: .RGBA8,
                colorSpace: outputColorSpace(colorSpaceKind),
                options: options
            )
        } catch {
            throw FullAppleEncoderError.appleEncodingFailed(error.localizedDescription)
        }

        let verification = try verify(
            url: temporaryURL,
            expectedRGB: rgbGainMap,
            fallbackSize: hdrImage.extent.size
        )
        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        return verification
    }

    private func loadHDRImage(from url: URL) -> CIImage? {
        return CIImage(
            contentsOf: url,
            options: [.applyOrientationProperty: true, .expandToHDR: true]
        )
    }

    private func verify(
        url: URL,
        expectedRGB: Bool,
        fallbackSize: CGSize
    ) throws -> ISOHDRHEICVerification {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw FullAppleEncoderError.verificationFailed("ImageIO could not reopen the HEIC output.")
        }
        let isoAuxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source,
            0,
            kCGImageAuxiliaryDataTypeISOGainMap
        )
        guard let isoAuxiliary else {
            throw FullAppleEncoderError.verificationFailed("ImageIO did not recognize an ISO 21496-1 gain map in the HEIC output.")
        }

        let channels = auxiliaryChannelCount(isoAuxiliary)
        let expectedChannels = expectedRGB ? 3 : 1
        guard channels == expectedChannels else {
            throw FullAppleEncoderError.verificationFailed(
                "Expected a \(expectedChannels)-channel gain map, but ImageIO reported \(channels)."
            )
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? Int(fallbackSize.width)
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? Int(fallbackSize.height)
        guard let expandedImage = CIImage(contentsOf: url, options: [.expandToHDR: true]),
              expandedImage.contentHeadroom > 1.000_1 else {
            throw FullAppleEncoderError.verificationFailed("Core Image did not recognize the HEIC output as HDR.")
        }

        return ISOHDRHEICVerification(
            width: width,
            height: height,
            gainMapChannels: channels,
            contentHeadroom: Double(expandedImage.contentHeadroom),
            hasISOAuxiliary: true
        )
    }

    private func auxiliaryChannelCount(_ auxiliary: CFDictionary) -> Int {
        let dictionary = auxiliary as NSDictionary
        let description = dictionary[kCGImageAuxiliaryDataInfoDataDescription as String] as? NSDictionary
        let pixelFormat = description?["PixelFormat"] as? NSNumber
        let metadata = String(describing: dictionary[kCGImageAuxiliaryDataInfoMetadata as String] ?? "")

        if metadata.contains("HDRToneMap:[1]") || metadata.contains("HDRToneMap:[2]") {
            return 3
        }
        if pixelFormat?.uint32Value == 0x4C30_3038 { // 'L008'
            return 1
        }
        return 3
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
