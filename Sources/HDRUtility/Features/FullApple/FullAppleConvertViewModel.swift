import Foundation

@MainActor
@Observable
final class FullAppleConvertViewModel {
    var request = FullAppleConversionRequest()
    var lastJob: ConversionJob?
    var isRunning = false
    var errorMessage: String?

    var canRun: Bool {
        guard request.hdrSources.isEmpty == false, request.outputFolder != nil, !isRunning else { return false }
        return request.inputMode == .hdrOnly || (request.hdrSources.count == 1 && request.sdrBase != nil)
    }

    func addHDRSources(_ urls: [URL]) {
        request.hdrSources = Array(Set(request.hdrSources + urls)).sorted { $0.lastPathComponent < $1.lastPathComponent }
        request.outputFolder = request.outputFolder ?? urls.first?.deletingLastPathComponent()
        if request.hdrSources.count > 1 {
            request.inputMode = .hdrOnly
            request.sdrBase = nil
        }
    }

    func restoreCompatibleJPEGDefaults() {
        request.restoreCompatibleJPEGDefaults()
    }

    func run() async -> ConversionJob {
        isRunning = true
        defer { isRunning = false }
        let job = await ConversionService().convertFullApple(request: request)
        lastJob = job
        errorMessage = job.status == .failed ? job.log.joined(separator: "\n") : nil
        return job
    }
}
