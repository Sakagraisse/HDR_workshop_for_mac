import Foundation

@MainActor
@Observable
final class AppleConvertViewModel {
    var records: [HDRFileRecord] = []
    var request = AppleConversionRequest()
    var lastJob: ConversionJob?
    var importedFolderURL: URL?
    var isRunning = false
    var errorMessage: String?

    private let analyzer = ImageAnalyzer()

    var sourceURLs: [URL] {
        records.map(\.url)
    }

    var canRun: Bool {
        sourceURLs.isEmpty == false && request.outputFolder != nil && exportWarning == nil && isRunning == false
    }

    var importedFolderName: String? {
        importedFolderURL?.lastPathComponent
    }

    var exportWarning: String? {
        guard let outputFolder = request.outputFolder else {
            return "Choose an export folder before running the Apple conversion."
        }

        if sourceURLs.contains(where: { $0.deletingLastPathComponent().standardizedFileURL == outputFolder.standardizedFileURL }) {
            return "Do not export into the source folder. Choose a separate destination to avoid overwriting or mixing generated files with the originals."
        }

        if let importedFolderURL, importedFolderURL.standardizedFileURL == outputFolder.standardizedFileURL {
            return "The selected export folder matches the imported source folder. Pick another destination to protect the original files."
        }

        let existingOutputs = sourceURLs.compactMap { expectedOutputURL(for: $0) }.filter {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }

        if existingOutputs.isEmpty == false {
            return "One or more export filenames already exist in the destination folder. Change the folder or move existing outputs before running the export."
        }

        return nil
    }

    func handleDrop(urls: [URL]) {
        let resolved = expandDroppedURLs(urls)
        importFiles(urls: resolved.files, importedFolder: resolved.folder)
    }

    func importFiles(urls: [URL], importedFolder: URL?) {
        let incomingURLs = urls.map(\.standardizedFileURL)
        guard incomingURLs.isEmpty == false else { return }

        var nextRecords = records
        var failures: [String] = []

        for url in incomingURLs {
            do {
                let record = try analyzer.analyze(url: url)
                if let existingIndex = nextRecords.firstIndex(where: { $0.url.standardizedFileURL == url }) {
                    nextRecords[existingIndex] = record
                } else {
                    nextRecords.append(record)
                }
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        nextRecords.sort {
            $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
        }

        records = nextRecords
        importedFolderURL = importedFolder ?? importedFolderURL
        request.hdrSource = sourceURLs.first
        request.sdrBase = nil
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    func setOutputFolder(_ url: URL) {
        request.outputFolder = url
    }

    func setExportMode(_ mode: AppleExportMode) {
        request.exportMode = mode
        if mode.supportsJPEGContainer == false {
            request.outputFormat = .heic
        }
    }

    func clearSources() {
        records = []
        importedFolderURL = nil
        request.hdrSource = nil
        request.sdrBase = nil
        errorMessage = nil
    }

    func reset() {
        records = []
        request = AppleConversionRequest()
        importedFolderURL = nil
        lastJob = nil
        isRunning = false
        errorMessage = nil
    }

    func run() async -> ConversionJob {
        guard canRun else {
            let job = ConversionJob(
                title: "Apple Gain Map Batch Export",
                engine: .toGainMapHDR,
                status: .failed,
                log: [exportWarning ?? "Missing source files or export folder."],
                outputURL: nil
            )
            lastJob = job
            return job
        }

        isRunning = true
        defer { isRunning = false }

        let service = ConversionService()
        var logs = ["Batch size: \(sourceURLs.count)"]
        var succeeded = 0
        var failed = 0
        var lastOutputURL: URL?

        for sourceURL in sourceURLs {
            var itemRequest = request
            itemRequest.hdrSource = sourceURL
            if sourceURLs.count > 1 {
                itemRequest.sdrBase = nil
            }

            let job = await service.convertApple(request: itemRequest)
            lastOutputURL = job.outputURL ?? lastOutputURL

            switch job.status {
            case .succeeded:
                succeeded += 1
            case .failed:
                failed += 1
            case .idle, .running:
                break
            }

            logs.append("")
            logs.append("Source: \(sourceURL.lastPathComponent)")
            logs.append(contentsOf: job.log)
        }

        let status: JobStatus = failed == 0 ? .succeeded : (succeeded == 0 ? .failed : .succeeded)
        let summary = ConversionJob(
            title: "Apple Gain Map Batch Export",
            engine: .toGainMapHDR,
            status: status,
            log: [
                "Completed \(sourceURLs.count) file(s)",
                "Succeeded: \(succeeded)",
                "Failed: \(failed)"
            ] + logs,
            outputURL: lastOutputURL
        )

        lastJob = summary
        return summary
    }

    private func expectedOutputURL(for sourceURL: URL) -> URL? {
        guard let outputFolder = request.outputFolder else {
            return nil
        }

        let extensionName = request.outputFormat == .jpeg && request.exportMode.supportsJPEGContainer ? "jpg" : "heic"
        let suffix = request.outputNameSuffix.isEmpty ? "apple" : request.outputNameSuffix
        return outputFolder.appending(path: "\(sourceURL.deletingPathExtension().lastPathComponent)-\(suffix).\(extensionName)")
    }

    private func expandDroppedURLs(_ urls: [URL]) -> (files: [URL], folder: URL?) {
        let fileManager = FileManager.default
        var files: [URL] = []
        var importedFolder: URL?

        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                importedFolder = url
                files.append(contentsOf: supportedFiles(in: url))
            } else if Self.supportedExtensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }

        let uniqueFiles = Array(Set(files.map(\.standardizedFileURL))).sorted {
            $0.path(percentEncoded: false).localizedCaseInsensitiveCompare($1.path(percentEncoded: false)) == .orderedAscending
        }
        return (uniqueFiles, importedFolder)
    }

    private func supportedFiles(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) else {
                continue
            }
            files.append(fileURL)
        }
        return files
    }

    private static let supportedExtensions: Set<String> = [
        "avif",
        "exr",
        "heic",
        "heif",
        "jpeg",
        "jpg",
        "tif",
        "tiff"
    ]
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
