import Foundation

struct ProRAWBatchConversionService {
    func convert(
        request: ProRAWBatchConversionRequest,
        onProgress: (@Sendable (ProRAWBatchProgressUpdate) async -> Void)? = nil
    ) async -> ConversionJob {
        guard let outputFolder = request.outputFolder else {
            return failed("Missing output folder.")
        }
        guard request.sources.isEmpty == false else {
            return failed("No ProRAW/DNG source selected.")
        }

        let requestedParallelism = min(max(request.parallelConversions, 2), 20)
        let workItems = plannedWorkItems(
            sources: request.sources,
            outputFolder: outputFolder,
            suffix: request.outputSuffix
        )
        let effectiveParallelism = min(requestedParallelism, workItems.count)
        let quality = request.quality
        let resizeToApple24MP = request.resizeToApple24MP
        let workQueue = BatchWorkQueue(items: workItems)

        var log = [
            "Format: HEIC direct · Apple HDR ou repli SDR",
            "Runtime: Apple ImageIO",
            "Gain map: conservée lorsqu’elle est présente",
            "Resolution: \(resizeToApple24MP ? "Apple 24 MP maximum (5712 px)" : "Original")",
            "Batch size: \(request.sources.count)",
            "Parallel conversions: \(effectiveParallelism) (configured: \(requestedParallelism))"
        ]

        let results = await withTaskGroup(of: [BatchItemResult].self, returning: [BatchItemResult].self) { group in
            var collected: [BatchItemResult] = []

            for _ in 0..<effectiveParallelism {
                group.addTask {
                    let encoder = ProRAWAppleHEICEncoder()
                    var workerResults: [BatchItemResult] = []
                    while let workItem = await workQueue.next() {
                        await onProgress?(
                            ProRAWBatchProgressUpdate(source: workItem.source, state: .processing)
                        )
                        let result = convertWorkItem(
                            workItem,
                            encoder: encoder,
                            quality: quality,
                            resizeToApple24MP: resizeToApple24MP
                        )
                        workerResults.append(result)
                        await onProgress?(
                            ProRAWBatchProgressUpdate(source: workItem.source, state: result.itemState)
                        )
                    }
                    return workerResults
                }
            }

            for await workerResults in group {
                collected.append(contentsOf: workerResults)
            }

            return collected.sorted { $0.index < $1.index }
        }

        let outputs = results.compactMap { $0.outputURL }
        let failures = results.count - outputs.count
        let hdrCount = results.count { $0.verification?.kind == .hdr }
        let sdrCount = results.count { $0.verification?.kind == .sdr }
        log.append("HDR: \(hdrCount) · SDR: \(sdrCount) · Failed: \(failures)")
        for result in results {
            if let verification = result.verification, let outputURL = result.outputURL {
                let dimensions = "\(verification.width)×\(verification.height)"
                log.append(
                    "✓ \(result.source.lastPathComponent) → \(outputURL.lastPathComponent) · " +
                    "\(dimensions) · \(verification.detail)"
                )
            } else {
                log.append("✗ \(result.source.lastPathComponent): \(result.errorDescription ?? "Unknown conversion error.")")
            }
        }

        return ConversionJob(
            title: "ProRAW → HEIC Batch",
            engine: .fullApple,
            status: outputs.isEmpty ? .failed : .succeeded,
            log: log,
            outputURLs: outputs
        )
    }

    private func failed(_ message: String) -> ConversionJob {
        ConversionJob(
            title: "ProRAW → HEIC Batch",
            engine: .fullApple,
            status: .failed,
            log: [message]
        )
    }

    private func plannedWorkItems(sources: [URL], outputFolder: URL, suffix: String) -> [BatchWorkItem] {
        var reservedPaths: Set<String> = []
        return sources.enumerated().map { index, source in
            let output = uniqueOutputURL(
                folder: outputFolder,
                stem: source.deletingPathExtension().lastPathComponent,
                suffix: suffix,
                reservedPaths: &reservedPaths
            )
            reservedPaths.insert(output.path(percentEncoded: false))
            return BatchWorkItem(index: index, source: source, output: output)
        }
    }

    private func uniqueOutputURL(
        folder: URL,
        stem: String,
        suffix: String,
        reservedPaths: inout Set<String>
    ) -> URL {
        let cleanSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = cleanSuffix.isEmpty ? stem : "\(stem)-\(cleanSuffix)"
        var candidate = folder.appending(path: "\(baseName).heic")
        var version = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) ||
            reservedPaths.contains(candidate.path(percentEncoded: false)) {
            candidate = folder.appending(path: "\(baseName)-\(version).heic")
            version += 1
        }
        return candidate
    }
}

private struct BatchWorkItem: Sendable {
    let index: Int
    let source: URL
    let output: URL
}

private actor BatchWorkQueue {
    private let items: [BatchWorkItem]
    private var nextIndex = 0

    init(items: [BatchWorkItem]) {
        self.items = items
    }

    func next() -> BatchWorkItem? {
        guard nextIndex < items.count else { return nil }
        defer { nextIndex += 1 }
        return items[nextIndex]
    }
}

private struct BatchItemResult: Sendable {
    let index: Int
    let source: URL
    let outputURL: URL?
    let verification: ProRAWHEICVerification?
    let errorDescription: String?

    var itemState: ProRAWBatchItemState {
        if let verification {
            return verification.kind == .hdr ? .hdr : .sdr
        }
        return .failed
    }
}

private func convertWorkItem(
    _ workItem: BatchWorkItem,
    encoder: ProRAWAppleHEICEncoder,
    quality: Double,
    resizeToApple24MP: Bool
) -> BatchItemResult {
    autoreleasepool {
        do {
            let verification = try encoder.encode(
                sourceURL: workItem.source,
                outputURL: workItem.output,
                quality: quality,
                resizeToApple24MP: resizeToApple24MP
            )
            return BatchItemResult(
                index: workItem.index,
                source: workItem.source,
                outputURL: workItem.output,
                verification: verification,
                errorDescription: nil
            )
        } catch {
            return BatchItemResult(
                index: workItem.index,
                source: workItem.source,
                outputURL: nil,
                verification: nil,
                errorDescription: error.localizedDescription
            )
        }
    }
}
