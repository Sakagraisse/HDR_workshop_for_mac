import CoreGraphics
import Foundation

struct HDRFileRecord: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let container: ImageContainer
    let pixelSize: CGSize?
    let bitDepth: Int?
    let colorSpace: ColorSpaceKind?
    let transferFunction: TransferFunction
    let hdrKind: HDRKind
    let gainMap: GainMapInfo?
    let metadata: [MetadataEntry]
    let diagnostics: [DiagnosticItem]
    let compatibility: CompatibilityReport

    init(
        id: UUID = UUID(),
        url: URL,
        container: ImageContainer,
        pixelSize: CGSize?,
        bitDepth: Int?,
        colorSpace: ColorSpaceKind?,
        transferFunction: TransferFunction,
        hdrKind: HDRKind,
        gainMap: GainMapInfo?,
        metadata: [MetadataEntry],
        diagnostics: [DiagnosticItem],
        compatibility: CompatibilityReport
    ) {
        self.id = id
        self.url = url
        self.container = container
        self.pixelSize = pixelSize
        self.bitDepth = bitDepth
        self.colorSpace = colorSpace
        self.transferFunction = transferFunction
        self.hdrKind = hdrKind
        self.gainMap = gainMap
        self.metadata = metadata
        self.diagnostics = diagnostics
        self.compatibility = compatibility
    }
}

enum ImageContainer: String, CaseIterable, Hashable {
    case jpeg
    case heic
    case avif
    case png
    case tiff
    case exr
    case jxl
    case unknown
}

enum ColorSpaceKind: String, Hashable {
    case sRGB
    case displayP3
    case rec2020
    case extendedLinearSRGB
    case unknown
}

enum TransferFunction: String, Hashable {
    case sdr
    case pq
    case hlg
    case linear
    case unknown
}

enum HDRKind: String, Hashable {
    case sdr
    case appleGainMap
    case isoGainMap
    case ultraHDR
    case pqHDR
    case hlgHDR
    case hdrUnknown
}

struct GainMapInfo: Hashable {
    let kind: GainMapKind
    let size: CGSize?
    let bitDepth: Int?
    let metadataSummary: [MetadataEntry]
}

enum GainMapKind: String, Hashable {
    case apple
    case iso21496
    case ultraHDR
    case unknown
}

struct MetadataEntry: Hashable, Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

struct DiagnosticItem: Hashable, Identifiable {
    let id = UUID()
    let severity: DiagnosticSeverity
    let message: String
}

enum DiagnosticSeverity: String, Hashable {
    case info
    case warning
    case error
}

struct CompatibilityReport: Hashable {
    let appleReady: Bool
    let instagramReady: Bool
    let sdrFallbackOK: Bool
    let verdict: CompatibilityVerdict
    let notes: [String]
}

enum CompatibilityVerdict: String, Hashable {
    case readyForApple
    case readyForInstagram
    case hdrLimitedCompatibility
    case likelyBrokenGainMap
    case suspiciousSDRTagging
    case standardSDR
}

struct ConversionJob: Identifiable, Hashable {
    let id: UUID
    let title: String
    let engine: ConversionEngine
    let createdAt: Date
    let status: JobStatus
    let log: [String]
    let outputURL: URL?

    init(
        id: UUID = UUID(),
        title: String,
        engine: ConversionEngine,
        createdAt: Date = .now,
        status: JobStatus,
        log: [String],
        outputURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.engine = engine
        self.createdAt = createdAt
        self.status = status
        self.log = log
        self.outputURL = outputURL
    }
}

enum ConversionEngine: String, Hashable {
    case toGainMapHDR
    case libUltraHDR
}

enum JobStatus: String, Hashable {
    case idle
    case running
    case succeeded
    case failed
}
