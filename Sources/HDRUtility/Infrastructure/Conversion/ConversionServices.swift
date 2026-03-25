import Foundation

struct AppleConversionRequest: Hashable {
    var hdrSource: URL?
    var sdrBase: URL?
    var outputFolder: URL?
    var quality: Double = 0.92
    var toneMapRatio: Double = 1.8
    var outputFormat: AppleOutputFormat = .heic
    var colorSpace: ColorSpaceKind = .displayP3
    var bitDepth: Int = 10
}

enum AppleOutputFormat: String, CaseIterable, Identifiable {
    case heic
    case jpeg

    var id: String { rawValue }
}

struct InstagramConversionRequest: Hashable {
    var hdrSource: URL?
    var sdrBase: URL?
    var outputFolder: URL?
    var quality: Double = 0.9
    var includeISOGainMapMetadata = true
}

protocol ConversionServicing {
    func convertApple(request: AppleConversionRequest) async -> ConversionJob
    func convertInstagram(request: InstagramConversionRequest) async -> ConversionJob
}

struct ConversionService: ConversionServicing {
    private let toolsLocator = EmbeddedToolsLocator()

    func convertApple(request: AppleConversionRequest) async -> ConversionJob {
        do {
            return try await AppleGainMapRunner().run(request: request, toolsDirectory: try toolsLocator.resolve())
        } catch {
            return failedJob(title: "Apple Gain Map Export", engine: .toGainMapHDR, error: error)
        }
    }

    func convertInstagram(request: InstagramConversionRequest) async -> ConversionJob {
        do {
            return try await UltraHDRRunner().run(request: request, toolsDirectory: try toolsLocator.resolve())
        } catch {
            return failedJob(title: "Instagram Gain Map Export", engine: .libUltraHDR, error: error)
        }
    }

    private func failedJob(title: String, engine: ConversionEngine, error: Error) -> ConversionJob {
        ConversionJob(
            title: title,
            engine: engine,
            status: .failed,
            log: [error.localizedDescription],
            outputURL: nil
        )
    }
}

struct EmbeddedToolsLocator {
    func resolve() throws -> URL {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appending(path: "EmbeddedTools"))
            candidates.append(resourceURL.appending(path: "../Resources/EmbeddedTools").standardizedFileURL)
        }

        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        candidates.append(contentsOf: searchPathCandidates(from: currentDirectory))

        if let bundleURL = Bundle.main.bundleURL as URL? {
            candidates.append(contentsOf: searchPathCandidates(from: bundleURL))
        }

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        candidates.append(sourceRoot.appending(path: "Resources/EmbeddedTools"))

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }

        throw EmbeddedToolsError.missingDirectory
    }

    private func searchPathCandidates(from startingURL: URL) -> [URL] {
        var candidates: [URL] = []
        var currentURL = startingURL.standardizedFileURL

        for _ in 0..<6 {
            candidates.append(currentURL.appending(path: "Resources/EmbeddedTools"))
            candidates.append(currentURL.appending(path: "HDRutility/Resources/EmbeddedTools"))
            currentURL.deleteLastPathComponent()
        }

        return candidates
    }
}

enum EmbeddedToolsError: LocalizedError {
    case missingDirectory

    var errorDescription: String? {
        "Embedded tools directory not found. Run Tools/package-vendors.sh after building vendor binaries."
    }
}
