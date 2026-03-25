import Foundation

@MainActor
@Observable
final class InstagramConvertViewModel {
    var request = InstagramConversionRequest()
    var lastJob: ConversionJob?

    var canRun: Bool {
        request.hdrSource != nil && request.sdrBase != nil && request.outputFolder != nil
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
        let job = await ConversionService().convertInstagram(request: request)
        lastJob = job
        return job
    }
}
