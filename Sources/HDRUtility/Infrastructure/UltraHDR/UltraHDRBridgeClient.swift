import Foundation

enum UltraHDRBridgeError: LocalizedError {
    case invalidResponse
    case missingInputs
    case missingOutputFolder

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from ultrahdr_bridge."
        case .missingInputs:
            "Missing HDR or SDR input."
        case .missingOutputFolder:
            "Missing output folder."
        }
    }
}

struct UltraHDRBridgeClient {
    private let processRunner = ProcessRunner()

    func run(request: InstagramConversionRequest, toolsDirectory: URL) async throws -> ConversionJob {
        guard let hdrSource = request.hdrSource, let sdrBase = request.sdrBase else {
            throw UltraHDRBridgeError.missingInputs
        }
        guard let outputFolder = request.outputFolder else {
            throw UltraHDRBridgeError.missingOutputFolder
        }

        let outputURL = outputFolder.appending(path: "\(hdrSource.deletingPathExtension().lastPathComponent)-instagram.jpg")
        let payload = UltraHDRBridgeRequest(
            mode: "encode",
            hdrInput: hdrSource.path(percentEncoded: false),
            sdrInput: sdrBase.path(percentEncoded: false),
            output: outputURL.path(percentEncoded: false),
            quality: Int(request.quality * 100),
            writeISO: request.includeISOGainMapMetadata
        )

        let executableURL = toolsDirectory.appending(path: "ultrahdr_bridge")
        let data = try JSONEncoder().encode(payload)
        let tempURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("json")
        try data.write(to: tempURL)

        let result = try await processRunner.run(
            executableURL: executableURL,
            arguments: ["--request", tempURL.path(percentEncoded: false)]
        )

        try? FileManager.default.removeItem(at: tempURL)

        let response = try decodeResponse(from: result)

        return ConversionJob(
            title: "Instagram Gain Map Export",
            engine: .libUltraHDR,
            status: response.success ? .succeeded : .failed,
            log: response.messages,
            outputURL: response.output.map(URL.init(fileURLWithPath:))
        )
    }

    private func decodeResponse(from result: ProcessResult) throws -> UltraHDRBridgeResponse {
        let text = result.standardOutput.isEmpty ? result.standardError : result.standardOutput
        guard let data = text.data(using: .utf8) else {
            throw UltraHDRBridgeError.invalidResponse
        }
        return try JSONDecoder().decode(UltraHDRBridgeResponse.self, from: data)
    }
}
