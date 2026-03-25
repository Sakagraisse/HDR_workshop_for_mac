import Foundation

struct UltraHDRBridgeRequest: Codable, Hashable {
    let mode: String
    let hdrInput: String
    let sdrInput: String
    let output: String
    let quality: Int
    let writeISO: Bool
}

struct UltraHDRBridgeResponse: Codable, Hashable {
    let success: Bool
    let output: String?
    let messages: [String]
}
