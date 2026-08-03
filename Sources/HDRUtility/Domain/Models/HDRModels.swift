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
    let gainMapSignals: GainMapSignals
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
        gainMapSignals: GainMapSignals = .empty,
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
        self.gainMapSignals = gainMapSignals
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
    let channelModel: GainMapChannelModel
    let layout: GainMapLayout
    let metadataSummary: [MetadataEntry]

    init(
        kind: GainMapKind,
        size: CGSize?,
        bitDepth: Int?,
        channelModel: GainMapChannelModel = .unknown,
        layout: GainMapLayout = .unknown,
        metadataSummary: [MetadataEntry]
    ) {
        self.kind = kind
        self.size = size
        self.bitDepth = bitDepth
        self.channelModel = channelModel
        self.layout = layout
        self.metadataSummary = metadataSummary
    }
}

enum GainMapKind: String, Hashable {
    case apple
    case iso21496
    case ultraHDR
    case hybrid
    case unknown
}

enum GainMapChannelModel: String, Hashable {
    case monochrome
    case rgb
    case unknown
}

enum GainMapLayout: String, Hashable {
    case jpegMPF
    case heifAuxiliary
    case unknown
}

struct GainMapSignals: Hashable {
    let hasAppleAuxiliary: Bool
    let hasISOAuxiliary: Bool
    let hasAppleLegacyMarker: Bool
    let hasISO21496Marker: Bool
    let hasUltraHDRXMP: Bool
    let hasGContainer: Bool
    let hasMPF: Bool
    let nativeHDRHeadroom: Double?
    let gainMapChannelCount: Int?
    let gainMapSize: CGSize?

    static let empty = GainMapSignals(
        hasAppleAuxiliary: false,
        hasISOAuxiliary: false,
        hasAppleLegacyMarker: false,
        hasISO21496Marker: false,
        hasUltraHDRXMP: false,
        hasGContainer: false,
        hasMPF: false,
        nativeHDRHeadroom: nil,
        gainMapChannelCount: nil,
        gainMapSize: nil
    )

    var hasGainMapSignal: Bool {
        hasAppleAuxiliary || hasISOAuxiliary || hasAppleLegacyMarker ||
            hasISO21496Marker || hasUltraHDRXMP || hasGContainer
    }
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
    let gainMapFormats: GainMapFormatCompatibility

    init(
        appleReady: Bool,
        instagramReady: Bool,
        sdrFallbackOK: Bool,
        verdict: CompatibilityVerdict,
        notes: [String],
        gainMapFormats: GainMapFormatCompatibility = .empty
    ) {
        self.appleReady = appleReady
        self.instagramReady = instagramReady
        self.sdrFallbackOK = sdrFallbackOK
        self.verdict = verdict
        self.notes = notes
        self.gainMapFormats = gainMapFormats
    }
}

enum CompatibilityStatus: String, Hashable {
    case verified
    case declared
    case notDetected
    case notApplicable
}

struct GainMapFormatCompatibility: Hashable {
    let appleLegacy: CompatibilityStatus
    let iso21496: CompatibilityStatus
    let ultraHDRV1: CompatibilityStatus
    let appleDecode: CompatibilityStatus
    let androidDecode: CompatibilityStatus

    static let empty = GainMapFormatCompatibility(
        appleLegacy: .notDetected,
        iso21496: .notDetected,
        ultraHDRV1: .notDetected,
        appleDecode: .notApplicable,
        androidDecode: .notApplicable
    )

    var crossPlatformVerified: Bool {
        appleDecode == .verified && androidDecode == .verified
    }
}

enum CompatibilityVerdict: String, Hashable {
    case crossPlatformGainMap
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
    let outputURLs: [URL]

    var outputURL: URL? { outputURLs.first }

    init(
        id: UUID = UUID(),
        title: String,
        engine: ConversionEngine,
        createdAt: Date = .now,
        status: JobStatus,
        log: [String],
        outputURL: URL? = nil,
        outputURLs: [URL] = []
    ) {
        self.id = id
        self.title = title
        self.engine = engine
        self.createdAt = createdAt
        self.status = status
        self.log = log
        self.outputURLs = outputURLs.isEmpty ? outputURL.map { [$0] } ?? [] : outputURLs
    }
}

enum ConversionEngine: String, Hashable {
    case toGainMapHDR
    case libUltraHDR
    case fullApple
}

enum JobStatus: String, Hashable {
    case idle
    case running
    case succeeded
    case failed
}

struct EngineStatus: Hashable {
    let engine: ConversionEngine
    let displayName: String
    let version: String
    let isAvailable: Bool
    let isHealthy: Bool
    let message: String
}

struct UltraHDRInspection: Hashable {
    let width: Int
    let height: Int
    let hasGainMap: Bool
    let isHDRSignal: Bool
    let contentHeadroom: Double
    let gainMapKind: String
    let gainMapWidth: Int
    let gainMapHeight: Int
    let multiChannel: Bool
    let gainMapChannels: Int
    let hasXMP: Bool
    let hasISO21496: Bool
    let hasAppleAuxiliary: Bool
    let hasISOAuxiliary: Bool
    let hasAppleLegacyMarker: Bool
    let hasGContainer: Bool
    let hasMPF: Bool
    let ultraHDRDecoderVerified: Bool
    let hasSDRFallback: Bool
}
