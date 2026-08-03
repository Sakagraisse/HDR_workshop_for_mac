import Foundation

struct ProRAWBatchConversionService {
    func convert(request: ProRAWBatchConversionRequest) async -> ConversionJob {
        guard let outputFolder = request.outputFolder else {
            return failed("Missing output folder.")
        }
        guard request.sources.isEmpty == false else {
            return failed("No ProRAW/DNG source selected.")
        }

        var outputs: [URL] = []
        var failures = 0
        var log = [
            "Format: HEIC Adaptive HDR (ISO 21496-1)",
            "Runtime: Core Image + ImageIO",
            "Batch size: \(request.sources.count)"
        ]

        for source in request.sources {
            let output = uniqueOutputURL(
                folder: outputFolder,
                stem: source.deletingPathExtension().lastPathComponent,
                suffix: request.outputSuffix
            )
            do {
                let verification = try FullAppleHEICEncoder().encode(
                    hdrURL: source,
                    sdrURL: nil,
                    outputURL: output,
                    quality: request.quality,
                    colorSpaceKind: request.colorSpace,
                    rgbGainMap: request.gainMapChannels.isRGB
                )
                outputs.append(output)
                log.append(
                    "✓ \(source.lastPathComponent) → \(output.lastPathComponent) · " +
                    "\(verification.width)×\(verification.height) · headroom " +
                    verification.contentHeadroom.formatted(.number.precision(.fractionLength(2))) +
                    "× · \(verification.gainMapChannels)-channel ISO gain map"
                )
            } catch {
                failures += 1
                log.append("✗ \(source.lastPathComponent): \(error.localizedDescription)")
            }
        }

        log.insert("Succeeded: \(outputs.count) · Failed: \(failures)", at: 3)
        return ConversionJob(
            title: "ProRAW → HEIC Batch",
            engine: .fullApple,
            status: outputs.isEmpty ? .failed : .succeeded,
            log: log,
            outputURLs: outputs
        )
    }

    private func failed(_ message: String) -> ConversionJob {
        ConversionJob(
            title: "ProRAW → HEIC Batch",
            engine: .fullApple,
            status: .failed,
            log: [message]
        )
    }

    private func uniqueOutputURL(folder: URL, stem: String, suffix: String) -> URL {
        let cleanSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = cleanSuffix.isEmpty ? stem : "\(stem)-\(cleanSuffix)"
        var candidate = folder.appending(path: "\(baseName).heic")
        var version = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = folder.appending(path: "\(baseName)-\(version).heic")
            version += 1
        }
        return candidate
    }
}
