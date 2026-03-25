import Foundation

struct AppleGainMapRunner {
    private let processRunner = ProcessRunner()
    private let commandBuilder = AppleGainMapCommandBuilder()

    func run(request: AppleConversionRequest, toolsDirectory: URL) async throws -> ConversionJob {
        let command = try commandBuilder.build(request: request, toolsDirectory: toolsDirectory)
        let result = try await processRunner.run(
            executableURL: command.executableURL,
            arguments: command.arguments,
            currentDirectoryURL: toolsDirectory
        )
        let outputURL = expectedOutputURL(for: request)

        return ConversionJob(
            title: "Apple Gain Map Export",
            engine: .toGainMapHDR,
            status: result.terminationStatus == 0 ? .succeeded : .failed,
            log: command.arguments + [result.combinedOutput].filter { !$0.isEmpty },
            outputURL: outputURL
        )
    }

    private func expectedOutputURL(for request: AppleConversionRequest) -> URL? {
        guard let outputFolder = request.outputFolder, let hdrSource = request.hdrSource else {
            return nil
        }

        let extensionName = request.outputFormat == .jpeg && request.exportMode.supportsJPEGContainer ? "jpg" : "heic"
        let suffix = request.outputNameSuffix.isEmpty ? "apple" : request.outputNameSuffix
        let fileName = "\(hdrSource.deletingPathExtension().lastPathComponent)-\(suffix).\(extensionName)"
        return outputFolder.appending(path: fileName)
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
