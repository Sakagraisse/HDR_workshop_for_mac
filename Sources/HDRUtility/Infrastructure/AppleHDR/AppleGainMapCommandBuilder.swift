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

        if request.outputNameSuffix.isEmpty == false {
            arguments.append(contentsOf: ["-t", request.outputNameSuffix])
        }

        switch request.exportMode {
        case .appleGainMap:
            arguments.append("-g")
            arguments.append(contentsOf: ["-H", String(request.appleGainMapScale)])
        case .isoGainMap:
            if request.useMonochromeGainMap {
                arguments.append("-m")
            }
        case .sdrToneMapped:
            arguments.append("-s")
        case .hdrPQ:
            arguments.append("-p")
        case .hdrHLG:
            arguments.append("-h")
        }

        if request.outputFormat == .jpeg, request.exportMode.supportsJPEGContainer {
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

private extension AppleExportMode {
    var supportsJPEGContainer: Bool {
        switch self {
        case .appleGainMap, .isoGainMap, .sdrToneMapped:
            true
        case .hdrPQ, .hdrHLG:
            false
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
