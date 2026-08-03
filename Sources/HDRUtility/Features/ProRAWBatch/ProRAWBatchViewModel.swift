import Foundation

@MainActor
@Observable
final class ProRAWBatchViewModel {
    var request = ProRAWBatchConversionRequest()
    var lastJob: ConversionJob?
    var isRunning = false
    var errorMessage: String?

    var canRun: Bool {
        request.sources.isEmpty == false && request.outputFolder != nil && isRunning == false
    }

    func addSources(_ urls: [URL]) {
        let expanded = Self.expand(urls)
        request.sources = Array(Set(request.sources + expanded)).sorted {
            $0.path(percentEncoded: false).localizedCaseInsensitiveCompare($1.path(percentEncoded: false)) == .orderedAscending
        }
        request.outputFolder = request.outputFolder ?? expanded.first?.deletingLastPathComponent()
        errorMessage = expanded.isEmpty ? "No .dng file was found in the selection." : nil
    }

    func clear() {
        request.sources = []
        errorMessage = nil
    }

    func run() async -> ConversionJob {
        isRunning = true
        defer { isRunning = false }
        let job = await ConversionService().convertProRAWBatch(request: request)
        lastJob = job
        errorMessage = job.status == .failed ? job.log.joined(separator: "\n") : nil
        return job
    }

    static func expand(_ urls: [URL]) -> [URL] {
        let fileManager = FileManager.default
        var files: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "dng" {
                    files.append(fileURL.standardizedFileURL)
                }
            } else if url.pathExtension.lowercased() == "dng" {
                files.append(url.standardizedFileURL)
            }
        }
        return Array(Set(files)).sorted {
            $0.path(percentEncoded: false).localizedCaseInsensitiveCompare($1.path(percentEncoded: false)) == .orderedAscending
        }
    }
}
