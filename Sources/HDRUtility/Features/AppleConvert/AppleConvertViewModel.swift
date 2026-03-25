import Foundation

@MainActor
@Observable
final class AppleConvertViewModel {
    var request = AppleConversionRequest()
    var lastJob: ConversionJob?

    var canRun: Bool {
        request.hdrSource != nil && request.outputFolder != nil
    }

    func handleDrop(urls: [URL]) {
        if let first = urls.first {
            request.hdrSource = first
        }
        if urls.count > 1 {
            request.sdrBase = urls[1]
        }
        request.outputFolder = urls.first?.deletingLastPathComponent()
    }

    func run() async -> ConversionJob {
        let request = self.request
        let job = await ConversionService().convertApple(request: request)
        lastJob = job
        return job
    }
}
