import Foundation

struct AppleConversionRequest: Hashable {
    var hdrSource: URL?
    var sdrBase: URL?
    var outputFolder: URL?
    var quality: Double = 0.92
    var toneMapRatio: Double = 1.8
    var exportMode: AppleExportMode = .appleGainMap
    var outputFormat: AppleOutputFormat = .heic
    var colorSpace: ColorSpaceKind = .displayP3
    var bitDepth: Int = 10
    var outputNameSuffix = "apple"
    var appleGainMapScale: Double = 1.0
    var useMonochromeGainMap = false
}

enum AppleOutputFormat: String, CaseIterable, Identifiable {
    case heic
    case jpeg

    var id: String { rawValue }
}

enum AppleExportMode: String, CaseIterable, Identifiable {
    case appleGainMap
    case isoGainMap
    case sdrToneMapped
    case hdrPQ
    case hdrHLG

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
        let bundleToolsURL = try bundledToolsDirectory()
        let stagedDirectory = fileManager.temporaryDirectory
            .appending(path: "HDRUtility")
            .appending(path: "EmbeddedTools")

        try stageBundledTools(from: bundleToolsURL, to: stagedDirectory, fileManager: fileManager)
        return stagedDirectory
    }

    private func bundledToolsDirectory() throws -> URL {
        let candidates = [
            Bundle.module.resourceURL?.appending(path: "EmbeddedTools"),
            Bundle.main.resourceURL?.appending(path: "EmbeddedTools"),
            Bundle.main.resourceURL?.appending(path: "../Resources/EmbeddedTools").standardizedFileURL
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            return candidate
        }

        throw EmbeddedToolsError.missingDirectory
    }

    private func stageBundledTools(from sourceDirectory: URL, to destinationDirectory: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let resourceURLs = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: nil
        )

        for resourceURL in resourceURLs {
            var destinationURL = destinationDirectory.appending(path: resourceURL.lastPathComponent)

            if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.copyItem(at: resourceURL, to: destinationURL)

            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? destinationURL.setResourceValues(values)

            if !resourceURL.hasDirectoryPath {
                try ensureExecutableBitIfNeeded(for: destinationURL, fileManager: fileManager)
            }
        }
    }

    private func ensureExecutableBitIfNeeded(for fileURL: URL, fileManager: FileManager) throws {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
        guard let permissions = attributes[.posixPermissions] as? NSNumber else {
            return
        }

        let mode = permissions.uint16Value
        let executableMask: UInt16 = 0o111
        guard mode & executableMask == 0 else {
            return
        }

        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int(mode | 0o755))],
            ofItemAtPath: fileURL.path(percentEncoded: false)
        )
    }
}

enum EmbeddedToolsError: LocalizedError {
    case missingDirectory

    var errorDescription: String? {
        "Embedded tools directory not found. Run Tools/package-vendors.sh after building vendor binaries."
    }
}
