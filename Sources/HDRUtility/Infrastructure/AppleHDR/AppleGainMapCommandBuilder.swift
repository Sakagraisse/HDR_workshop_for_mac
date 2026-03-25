import Foundation

struct AppleGainMapCommand {
    let executableURL: URL
    let arguments: [String]
}

struct AppleGainMapCommandBuilder {
    func build(
        request: AppleConversionRequest,
        toolsDirectory: URL
    ) throws -> AppleGainMapCommand {
        let executableURL = toolsDirectory.appending(path: "toGainMapHDR")
        guard let hdrSource = request.hdrSource else {
            throw AppleHDRIntegrationError.missingHDRSource
        }
        guard let outputFolder = request.outputFolder else {
            throw AppleHDRIntegrationError.missingOutputFolder
        }

        var arguments: [String] = [
            hdrSource.path(percentEncoded: false),
            outputFolder.path(percentEncoded: false),
            "-q", String(Int(request.quality * 100)),
            "-r", String(request.toneMapRatio),
            "-c", commandColorSpace(request.colorSpace),
            "-d", String(request.bitDepth)
        ]

        if let sdrBase = request.sdrBase {
            arguments.append(contentsOf: ["-b", sdrBase.path(percentEncoded: false)])
        }

        switch request.outputFormat {
        case .heic:
            arguments.append("-g")
        case .jpeg:
            arguments.append("-j")
        }

        return AppleGainMapCommand(executableURL: executableURL, arguments: arguments)
    }

    private func outputName(for sourceURL: URL, format: AppleOutputFormat) -> String {
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        return "\(stem)-apple.\(format == .heic ? "heic" : "jpg")"
    }

    private func commandColorSpace(_ colorSpace: ColorSpaceKind) -> String {
        switch colorSpace {
        case .displayP3:
            return "DisplayP3"
        case .rec2020:
            return "BT2020"
        case .sRGB, .extendedLinearSRGB, .unknown:
            return "sRGB"
        }
    }
}

enum AppleHDRIntegrationError: LocalizedError {
    case missingHDRSource
    case missingOutputFolder

    var errorDescription: String? {
        switch self {
        case .missingHDRSource:
            "Missing HDR source."
        case .missingOutputFolder:
            "Missing output folder."
        }
    }
}
