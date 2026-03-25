import Foundation

struct HDRClassifier {
    func classify(
        container: ImageContainer,
        bitDepth: Int?,
        colorSpace: ColorSpaceKind?,
        metadata: [MetadataEntry]
    ) -> (TransferFunction, HDRKind, GainMapInfo?, [DiagnosticItem], CompatibilityReport) {
        let metadataMap = Dictionary(uniqueKeysWithValues: metadata.map { ($0.key.lowercased(), $0.value.lowercased()) })
        let transfer = inferTransfer(metadata: metadataMap, bitDepth: bitDepth)
        let gainMap = inferGainMap(metadata: metadataMap)
        let hdrKind = inferHDRKind(transfer: transfer, gainMap: gainMap, metadata: metadataMap)
        let diagnostics = buildDiagnostics(hdrKind: hdrKind, gainMap: gainMap, bitDepth: bitDepth, colorSpace: colorSpace)
        let compatibility = buildCompatibility(container: container, hdrKind: hdrKind, gainMap: gainMap, diagnostics: diagnostics)
        return (transfer, hdrKind, gainMap, diagnostics, compatibility)
    }

    private func inferTransfer(metadata: [String: String], bitDepth: Int?) -> TransferFunction {
        let joined = metadata.map(\.key).joined(separator: " ") + " " + metadata.map(\.value).joined(separator: " ")
        if joined.contains("pq") || joined.contains("smpte2084") {
            return .pq
        }
        if joined.contains("hlg") || joined.contains("arib-std-b67") {
            return .hlg
        }
        if joined.contains("linear") {
            return .linear
        }
        if let bitDepth, bitDepth > 8 {
            return .unknown
        }
        return .sdr
    }

    private func inferGainMap(metadata: [String: String]) -> GainMapInfo? {
        let joined = metadata.map(\.key).joined(separator: " ") + " " + metadata.map(\.value).joined(separator: " ")
        if joined.contains("hdrgm:version") || joined.contains("gcontainer") {
            return GainMapInfo(kind: .ultraHDR, size: nil, bitDepth: 8, metadataSummary: [
                MetadataEntry(key: "Detected", value: "Ultra HDR / GContainer markers")
            ])
        }
        if joined.contains("iso 21496") || joined.contains("21496-1") {
            return GainMapInfo(kind: .iso21496, size: nil, bitDepth: 8, metadataSummary: [
                MetadataEntry(key: "Detected", value: "ISO 21496-1 markers")
            ])
        }
        if joined.contains("apple") && joined.contains("gain") {
            return GainMapInfo(kind: .apple, size: nil, bitDepth: 8, metadataSummary: [
                MetadataEntry(key: "Detected", value: "Apple gain map markers")
            ])
        }
        return nil
    }

    private func inferHDRKind(
        transfer: TransferFunction,
        gainMap: GainMapInfo?,
        metadata: [String: String]
    ) -> HDRKind {
        if let gainMap {
            switch gainMap.kind {
            case .apple:
                return .appleGainMap
            case .iso21496:
                return .isoGainMap
            case .ultraHDR:
                return .ultraHDR
            case .unknown:
                return .hdrUnknown
            }
        }
        switch transfer {
        case .pq:
            return .pqHDR
        case .hlg:
            return .hlgHDR
        case .sdr:
            if metadata.keys.contains(where: { $0.contains("hdr") }) {
                return .hdrUnknown
            }
            return .sdr
        case .linear, .unknown:
            return .hdrUnknown
        }
    }

    private func buildDiagnostics(
        hdrKind: HDRKind,
        gainMap: GainMapInfo?,
        bitDepth: Int?,
        colorSpace: ColorSpaceKind?
    ) -> [DiagnosticItem] {
        var items: [DiagnosticItem] = []

        if let bitDepth, bitDepth < 8 {
            items.append(DiagnosticItem(severity: .error, message: "Bit depth is unexpectedly low."))
        }

        if hdrKind != .sdr, colorSpace == .sRGB {
            items.append(DiagnosticItem(severity: .warning, message: "HDR tagging with sRGB color space is suspicious."))
        }

        if gainMap != nil, bitDepth == 8 {
            items.append(DiagnosticItem(severity: .info, message: "Gain map metadata found. Validate SDR fallback visually."))
        }

        if items.isEmpty {
            items.append(DiagnosticItem(severity: .info, message: "No obvious structural issues detected."))
        }

        return items
    }

    private func buildCompatibility(
        container: ImageContainer,
        hdrKind: HDRKind,
        gainMap: GainMapInfo?,
        diagnostics: [DiagnosticItem]
    ) -> CompatibilityReport {
        let hasWarnings = diagnostics.contains(where: { $0.severity != .info })
        let appleReady = hdrKind == .appleGainMap || (container == .heic && hdrKind == .pqHDR)
        let instagramReady = hdrKind == .ultraHDR || hdrKind == .isoGainMap
        let sdrFallbackOK = gainMap != nil || hdrKind == .sdr

        let verdict: CompatibilityVerdict
        if hasWarnings, hdrKind != .sdr {
            verdict = .hdrLimitedCompatibility
        } else if appleReady {
            verdict = .readyForApple
        } else if instagramReady {
            verdict = .readyForInstagram
        } else if hdrKind == .sdr {
            verdict = .standardSDR
        } else {
            verdict = .likelyBrokenGainMap
        }

        var notes: [String] = []
        if appleReady {
            notes.append("Likely suitable for Apple ecosystem workflows.")
        }
        if instagramReady {
            notes.append("Likely suitable for JPEG gain map workflows.")
        }
        if !sdrFallbackOK {
            notes.append("No SDR fallback could be inferred.")
        }
        if notes.isEmpty {
            notes.append("Manual validation recommended.")
        }

        return CompatibilityReport(
            appleReady: appleReady,
            instagramReady: instagramReady,
            sdrFallbackOK: sdrFallbackOK,
            verdict: verdict,
            notes: notes
        )
    }
}
