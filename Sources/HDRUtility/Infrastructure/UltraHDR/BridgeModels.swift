import Foundation

enum UltraHDRBridgeOperation: String, Codable {
    case inspect
    case verify
    case encodeHDR
    case encodePair
    case normalizeExisting
}

struct UltraHDRBridgeRequest: Codable, Hashable {
    let protocolVersion: Int
    let operation: UltraHDRBridgeOperation
    var input: String?
    var hdrInput: String?
    var sdrInput: String?
    var output: String?
    var baseQuality: Int?
    var gainMapQuality: Int?
    var gainMapScale: Int?
    var multiChannel: Bool?
    var preset: String?
    var colorGamut: String?
    var maxWidth: Int?

    init(
        operation: UltraHDRBridgeOperation,
        input: String? = nil,
        hdrInput: String? = nil,
        sdrInput: String? = nil,
        output: String? = nil,
        baseQuality: Int? = nil,
        gainMapQuality: Int? = nil,
        gainMapScale: Int? = nil,
        multiChannel: Bool? = nil,
        preset: String? = nil,
        colorGamut: String? = nil,
        maxWidth: Int? = nil
    ) {
        protocolVersion = 1
        self.operation = operation
        self.input = input
        self.hdrInput = hdrInput
        self.sdrInput = sdrInput
        self.output = output
        self.baseQuality = baseQuality
        self.gainMapQuality = gainMapQuality
        self.gainMapScale = gainMapScale
        self.multiChannel = multiChannel
        self.preset = preset
        self.colorGamut = colorGamut
        self.maxWidth = maxWidth
    }
}

struct UltraHDRBridgeResponse: Codable, Hashable {
    let protocolVersion: Int?
    let success: Bool
    let operation: String?
    let engineVersion: String?
    let input: String?
    let output: String?
    let width: Int?
    let height: Int?
    let hasGainMap: Bool?
    let isHDRSignal: Bool?
    let contentHeadroom: Double?
    let gainMapKind: String?
    let gainMapWidth: Int?
    let gainMapHeight: Int?
    let multiChannel: Bool?
    let gainMapChannels: Int?
    let hasXMP: Bool?
    let hasISO21496: Bool?
    let hasAppleAuxiliary: Bool?
    let hasISOAuxiliary: Bool?
    let hasAppleLegacyMarker: Bool?
    let hasGContainer: Bool?
    let hasMPF: Bool?
    let ultraHDRDecoderVerified: Bool?
    let hasSDRFallback: Bool?
    let baseQuality: Int?
    let gainMapQuality: Int?
    let messages: [String]

    var inspection: UltraHDRInspection {
        UltraHDRInspection(
            width: width ?? 0,
            height: height ?? 0,
            hasGainMap: hasGainMap ?? false,
            isHDRSignal: isHDRSignal ?? false,
            contentHeadroom: contentHeadroom ?? 0,
            gainMapKind: gainMapKind ?? "none",
            gainMapWidth: gainMapWidth ?? 0,
            gainMapHeight: gainMapHeight ?? 0,
            multiChannel: multiChannel ?? false,
            gainMapChannels: gainMapChannels ?? (multiChannel == true ? 3 : 0),
            hasXMP: hasXMP ?? false,
            hasISO21496: hasISO21496 ?? false,
            hasAppleAuxiliary: hasAppleAuxiliary ?? false,
            hasISOAuxiliary: hasISOAuxiliary ?? false,
            hasAppleLegacyMarker: hasAppleLegacyMarker ?? false,
            hasGContainer: hasGContainer ?? false,
            hasMPF: hasMPF ?? false,
            ultraHDRDecoderVerified: ultraHDRDecoderVerified ?? false,
            hasSDRFallback: hasSDRFallback ?? false
        )
    }
}
