import Foundation

@MainActor
@Observable
final class InstagramConvertViewModel {
    var request = InstagramPackageRequest()
    var lastJob: ConversionJob?
    var isRunning = false
    var errorMessage: String?

    var canRun: Bool {
        guard request.outputFolder != nil, !isRunning else { return false }
        switch request.inputMode {
        case .existingGainMap:
            return request.existingGainMap != nil
        case .hdrAndSDR:
            return request.hdrSource != nil && request.sdrBase != nil
        }
    }

    func setExisting(_ url: URL) {
        request.existingGainMap = url
        request.inputMode = .existingGainMap
        request.outputFolder = request.outputFolder ?? url.deletingLastPathComponent()
    }

    func setPair(hdr: URL?, sdr: URL?) {
        request.hdrSource = hdr ?? request.hdrSource
        request.sdrBase = sdr ?? request.sdrBase
        request.inputMode = .hdrAndSDR
        request.outputFolder = request.outputFolder ?? hdr?.deletingLastPathComponent() ?? sdr?.deletingLastPathComponent()
    }

    func run() async -> ConversionJob {
        isRunning = true
        defer { isRunning = false }
        let job = await ConversionService().packageForInstagram(request: request)
        lastJob = job
        errorMessage = job.status == .failed ? job.log.joined(separator: "\n") : nil
        return job
    }
}
