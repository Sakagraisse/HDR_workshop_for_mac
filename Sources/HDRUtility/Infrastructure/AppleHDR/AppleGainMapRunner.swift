import Foundation

struct AppleGainMapRunner {
    private let processRunner = ProcessRunner()
    private let commandBuilder = AppleGainMapCommandBuilder()

    func run(request: AppleConversionRequest, toolsDirectory: URL) async throws -> ConversionJob {
        let command = try commandBuilder.build(request: request, toolsDirectory: toolsDirectory)
        let result = try await processRunner.run(executableURL: command.executableURL, arguments: command.arguments)
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

        let extensionName = request.outputFormat == .heic ? "heic" : "jpg"
        let fileName = "\(hdrSource.deletingPathExtension().lastPathComponent)-apple.\(extensionName)"
        return outputFolder.appending(path: fileName)
    }
}
