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

enum UltraHDRInputMode: String, CaseIterable, Identifiable {
    case hdrOnly
    case hdrAndSDR
    var id: String { rawValue }
}

enum UltraHDRPreset: String, CaseIterable, Identifiable {
    case bestQuality
    case realtime
    var id: String { rawValue }
}

struct UltraHDRConversionRequest: Hashable {
    var inputMode: UltraHDRInputMode = .hdrOnly
    var hdrSources: [URL] = []
    var sdrBase: URL?
    var outputFolder: URL?
    var baseQuality = 95
    var gainMapQuality = 95
    var gainMapScale = 1
    var multiChannel = true
    var preset: UltraHDRPreset = .bestQuality
    var colorSpace: ColorSpaceKind = .displayP3
}

struct FullAppleConversionRequest: Hashable {
    var inputMode: UltraHDRInputMode = .hdrOnly
    var hdrSources: [URL] = []
    var sdrBase: URL?
    var outputFolder: URL?
    var quality = 0.95
    var colorSpace: ColorSpaceKind = .displayP3
    var outputFormat: ISOHDROutputFormat = .jpeg
    var gainMapChannels: ISOHDRGainMapChannels = .monochrome

    mutating func restoreCompatibleJPEGDefaults() {
        quality = 0.95
        colorSpace = .displayP3
        outputFormat = .jpeg
        gainMapChannels = .monochrome
    }
}

struct ProRAWBatchConversionRequest: Hashable {
    var sources: [URL] = []
    var outputFolder: URL?
    var quality = 0.95
    var colorSpace: ColorSpaceKind = .displayP3
    var gainMapChannels: ISOHDRGainMapChannels = .monochrome
    var outputSuffix = "adaptive-hdr"
}

enum ISOHDROutputFormat: String, CaseIterable, Identifiable {
    case jpeg
    case heic

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }

    var label: String {
        switch self {
        case .jpeg: "JPEG — ISO + Ultra HDR"
        case .heic: "HEIC — ISO Ultra HDR"
        }
    }
}

enum ISOHDRGainMapChannels: String, CaseIterable, Identifiable {
    case monochrome
    case rgb

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monochrome: "Monochrome (compatible)"
        case .rgb: "RGB (3 channels)"
        }
    }

    var isRGB: Bool { self == .rgb }
}

enum InstagramInputMode: String, CaseIterable, Identifiable {
    case existingGainMap
    case hdrAndSDR
    var id: String { rawValue }
}

enum ExistingGainMapPolicy: String, CaseIterable, Identifiable {
    case automatic
    case lossless
    case normalized
    var id: String { rawValue }
}

struct InstagramPackageRequest: Hashable {
    var inputMode: InstagramInputMode = .existingGainMap
    var existingGainMap: URL?
    var hdrSource: URL?
    var sdrBase: URL?
    var outputFolder: URL?
    var existingPolicy: ExistingGainMapPolicy = .automatic
    var baseQuality = 95
    var gainMapQuality = 95
    var gainMapScale = 1
    var multiChannel = true
    var colorSpace: ColorSpaceKind = .displayP3
    var maxFileSize = 8_000_000
}

protocol ConversionServicing {
    func convertApple(request: AppleConversionRequest) async -> ConversionJob
    func convertUltraHDR(request: UltraHDRConversionRequest) async -> ConversionJob
    func convertFullApple(request: FullAppleConversionRequest) async -> ConversionJob
    func convertProRAWBatch(request: ProRAWBatchConversionRequest) async -> ConversionJob
    func packageForInstagram(request: InstagramPackageRequest) async -> ConversionJob
    func inspectEngine(_ engine: ConversionEngine) async -> EngineStatus
    func verifyOutput(url: URL) async throws -> UltraHDRInspection
}

struct ConversionService: ConversionServicing {
    private let toolsLocator = EmbeddedToolsLocator()
    private let bridgeClient = UltraHDRBridgeClient()

    func convertApple(request: AppleConversionRequest) async -> ConversionJob {
        do {
            return try await AppleGainMapRunner().run(request: request, toolsDirectory: try toolsLocator.resolve())
        } catch {
            return failedJob(title: "Apple Gain Map Export", engine: .toGainMapHDR, error: error)
        }
    }

    func convertUltraHDR(request: UltraHDRConversionRequest) async -> ConversionJob {
        do {
            return try await bridgeClient.convertUltraHDR(request: request, toolsDirectory: try toolsLocator.resolve())
        } catch {
            return failedJob(title: "Ultra HDR Android Export", engine: .libUltraHDR, error: error)
        }
    }

    func convertFullApple(request: FullAppleConversionRequest) async -> ConversionJob {
        do {
            return try await FullAppleConversionService().convert(request: request)
        } catch {
            return failedJob(title: "ISOHDR Export", engine: .fullApple, error: error)
        }
    }

    func convertProRAWBatch(request: ProRAWBatchConversionRequest) async -> ConversionJob {
        await ProRAWBatchConversionService().convert(request: request)
    }

    func packageForInstagram(request: InstagramPackageRequest) async -> ConversionJob {
        do {
            return try await bridgeClient.packageForInstagram(request: request, toolsDirectory: try toolsLocator.resolve())
        } catch {
            return failedJob(title: "Instagram Package", engine: .libUltraHDR, error: error)
        }
    }

    func inspectEngine(_ engine: ConversionEngine) async -> EngineStatus {
        if engine == .fullApple {
            return EngineStatus(
                engine: .fullApple,
                displayName: "ISOHDR · Apple frameworks",
                version: ProcessInfo.processInfo.operatingSystemVersionString,
                isAvailable: true,
                isHealthy: true,
                message: "Foundation, Core Image and ImageIO are ready."
            )
        }
        do {
            let toolsDirectory = try toolsLocator.resolve()
            let executableName: String
            switch engine {
            case .toGainMapHDR: executableName = "toGainMapHDR"
            case .libUltraHDR: executableName = "ultrahdr_bridge"
            case .fullApple: preconditionFailure("Handled above")
            }
            let executable = toolsDirectory.appending(path: executableName)
            guard FileManager.default.isExecutableFile(atPath: executable.path(percentEncoded: false)) else {
                return EngineStatus(engine: engine, displayName: engine.displayName, version: "—", isAvailable: false, isHealthy: false, message: "Embedded executable missing.")
            }
            let arguments = engine == .toGainMapHDR ? ["-help"] : ["--version"]
            let result = try await ProcessRunner().run(executableURL: executable, arguments: arguments)
            let output = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let version = engine == .toGainMapHDR ? "3.1" : parsedBridgeVersion(output)
            return EngineStatus(
                engine: engine,
                displayName: engine.displayName,
                version: version,
                isAvailable: true,
                isHealthy: result.terminationStatus == 0 || engine == .toGainMapHDR,
                message: result.terminationStatus == 0 || engine == .toGainMapHDR ? "Embedded engine ready." : output
            )
        } catch {
            return EngineStatus(engine: engine, displayName: engine.displayName, version: "—", isAvailable: false, isHealthy: false, message: error.localizedDescription)
        }
    }

    func verifyOutput(url: URL) async throws -> UltraHDRInspection {
        try await bridgeClient.inspect(url: url, toolsDirectory: try toolsLocator.resolve())
    }

    private func parsedBridgeVersion(_ output: String) -> String {
        output.components(separatedBy: "libultrahdr ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "1.4.0"
    }

    private func failedJob(title: String, engine: ConversionEngine, error: Error) -> ConversionJob {
        ConversionJob(title: title, engine: engine, status: .failed, log: [error.localizedDescription])
    }
}

extension ConversionEngine {
    var displayName: String {
        switch self {
        case .toGainMapHDR: "toGainMapHDR"
        case .libUltraHDR: "libultrahdr"
        case .fullApple: "Apple frameworks"
        }
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
        for resourceURL in try fileManager.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil) {
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
        guard let permissions = attributes[.posixPermissions] as? NSNumber else { return }
        let mode = permissions.uint16Value
        guard mode & 0o111 == 0 else { return }
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: Int(mode | 0o755))], ofItemAtPath: fileURL.path(percentEncoded: false))
    }
}

enum EmbeddedToolsError: LocalizedError {
    case missingDirectory
    var errorDescription: String? {
        "Embedded tools directory not found. Run Tools/package-vendors.sh after building vendor binaries."
    }
}
