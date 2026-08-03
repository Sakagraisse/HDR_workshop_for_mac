import Foundation

struct FullAppleConversionService {
    func convert(request: FullAppleConversionRequest) async throws -> ConversionJob {
        guard let outputFolder = request.outputFolder else { throw FullAppleEncoderError.missingOutputFolder }
        guard request.hdrSources.isEmpty == false else { throw FullAppleEncoderError.missingInputs }
        if request.inputMode == .hdrAndSDR,
           request.hdrSources.count != 1 || request.sdrBase == nil {
            throw FullAppleEncoderError.missingInputs
        }

        var outputs: [URL] = []
        var log = [
            "Runtime: Foundation + Core Image + ImageIO only",
            "Batch size: \(request.hdrSources.count)"
        ]
        for hdrURL in request.hdrSources {
            let outputURL = uniqueOutputURL(
                folder: outputFolder,
                stem: hdrURL.deletingPathExtension().lastPathComponent,
                format: request.outputFormat
            )
            let channelDescription = request.gainMapChannels.isRGB ? "RGB" : "monochrome"

            switch request.outputFormat {
            case .jpeg:
                let verification = try FullAppleJPEGEncoder().encode(
                    hdrURL: hdrURL,
                    sdrURL: request.sdrBase,
                    outputURL: outputURL,
                    quality: request.quality,
                    colorSpaceKind: request.colorSpace,
                    rgbGainMap: request.gainMapChannels.isRGB
                )
                log.append(
                    "\(hdrURL.lastPathComponent): JPEG ISO + Ultra HDR v1, \(channelDescription) gain map, valid GContainer/MPF, no Apple legacy marker. " +
                    "Primary \(verification.primaryLength) bytes; gain map \(verification.gainMapLength) bytes."
                )
            case .heic:
                let verification = try FullAppleHEICEncoder().encode(
                    hdrURL: hdrURL,
                    sdrURL: request.sdrBase,
                    outputURL: outputURL,
                    quality: request.quality,
                    colorSpaceKind: request.colorSpace,
                    rgbGainMap: request.gainMapChannels.isRGB
                )
                log.append(
                    "\(hdrURL.lastPathComponent): HEIC Ultra HDR with ISO 21496-1 \(channelDescription) gain map, " +
                    "\(verification.width)×\(verification.height), headroom \(verification.contentHeadroom.formatted(.number.precision(.fractionLength(2))))."
                )
            }
            outputs.append(outputURL)
        }

        return ConversionJob(
            title: "ISOHDR Export",
            engine: .fullApple,
            status: .succeeded,
            log: log,
            outputURLs: outputs
        )
    }

    private func uniqueOutputURL(folder: URL, stem: String, format: ISOHDROutputFormat) -> URL {
        let fileManager = FileManager.default
        var candidate = folder.appending(path: "\(stem)-isohdr.\(format.fileExtension)")
        var version = 2
        while fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = folder.appending(path: "\(stem)-isohdr-\(version).\(format.fileExtension)")
            version += 1
        }
        return candidate
    }
}
