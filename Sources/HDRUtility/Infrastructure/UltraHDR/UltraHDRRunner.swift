import Foundation

struct UltraHDRRunner {
    private let client = UltraHDRBridgeClient()

    func run(request: InstagramConversionRequest, toolsDirectory: URL) async throws -> ConversionJob {
        try await client.run(request: request, toolsDirectory: toolsDirectory)
    }
}
