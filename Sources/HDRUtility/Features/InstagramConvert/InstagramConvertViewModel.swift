import Foundation

@MainActor
@Observable
final class InstagramConvertViewModel {
    var request = InstagramConversionRequest()
    var lastJob: ConversionJob?
    var errorMessage: String?

    var canRun: Bool {
        request.hdrSource != nil && request.sdrBase != nil && request.outputFolder != nil
    }

    var outputFileName: String? {
        guard let hdrSource = request.hdrSource else { return nil }
        return "\(hdrSource.deletingPathExtension().lastPathComponent)-instagram.jpg"
    }

    func setHDRSource(_ url: URL) {
        request.hdrSource = url
        if request.outputFolder == nil {
            request.outputFolder = url.deletingLastPathComponent()
        }
        errorMessage = nil
    }

    func setSDRSource(_ url: URL) {
        request.sdrBase = url
        if request.outputFolder == nil {
            request.outputFolder = url.deletingLastPathComponent()
        }
        errorMessage = nil
    }

    func clearHDRSource() {
        request.hdrSource = nil
    }

    func clearSDRSource() {
        request.sdrBase = nil
    }

    func clearSession() {
        request = InstagramConversionRequest()
        lastJob = nil
        errorMessage = nil
    }

    func run() async -> ConversionJob {
        let request = self.request
        let job = await ConversionService().convertInstagram(request: request)
        lastJob = job
        errorMessage = job.status == .failed ? job.log.first : nil
        return job
    }
}
