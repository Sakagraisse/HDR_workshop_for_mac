import Foundation

struct HDRClassifier {
    func classify(
        container: ImageContainer,
        bitDepth: Int?,
        colorSpace: ColorSpaceKind?,
        metadata: [MetadataEntry],
        gainMapSignals: GainMapSignals = .empty
    ) -> (TransferFunction, HDRKind, GainMapInfo?, [DiagnosticItem], CompatibilityReport) {
        let metadataMap = Dictionary(
            metadata.map { ($0.key.lowercased(), $0.value.lowercased()) },
            uniquingKeysWith: { _, latest in latest }
        )
        let sourceMetadata = metadataMap.filter { !$0.key.hasPrefix("analyze.") }
        let transfer = inferTransfer(metadata: sourceMetadata, bitDepth: bitDepth)
        let gainMap = inferGainMap(
            container: container,
            metadata: sourceMetadata,
            signals: gainMapSignals
        )
        let hdrKind = inferHDRKind(transfer: transfer, gainMap: gainMap, metadata: sourceMetadata)
        let diagnostics = buildDiagnostics(
            container: container,
            hdrKind: hdrKind,
            gainMap: gainMap,
            signals: gainMapSignals,
            bitDepth: bitDepth,
            colorSpace: colorSpace
        )
        let compatibility = buildCompatibility(
            container: container,
            hdrKind: hdrKind,
            gainMap: gainMap,
            signals: gainMapSignals,
            diagnostics: diagnostics
        )
        return (transfer, hdrKind, gainMap, diagnostics, compatibility)
    }

    private func inferTransfer(metadata: [String: String], bitDepth: Int?) -> TransferFunction {
        let joined = joinedMetadata(metadata)
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

    private func inferGainMap(
        container: ImageContainer,
        metadata: [String: String],
        signals: GainMapSignals
    ) -> GainMapInfo? {
        let joined = joinedMetadata(metadata)
        let hasUltraHDR = signals.hasUltraHDRXMP || signals.hasGContainer ||
            joined.contains("hdrgm:version") || joined.contains("gcontainer")
        let hasISO = signals.hasISOAuxiliary || signals.hasISO21496Marker ||
            joined.contains("iso 21496") || joined.contains("21496-1")
        let hasApple = signals.hasAppleAuxiliary || signals.hasAppleLegacyMarker ||
            (joined.contains("apple") && joined.contains("gain"))

        guard hasUltraHDR || hasISO || hasApple else { return nil }

        let kind: GainMapKind
        if hasISO && hasUltraHDR {
            kind = .hybrid
        } else if hasUltraHDR {
            kind = .ultraHDR
        } else if hasISO {
            kind = .iso21496
        } else if hasApple {
            kind = .apple
        } else {
            kind = .unknown
        }

        let layout: GainMapLayout = switch container {
        case .jpeg: .jpegMPF
        case .heic, .avif: .heifAuxiliary
        default: .unknown
        }
        let channelModel: GainMapChannelModel = switch signals.gainMapChannelCount {
        case 1: .monochrome
        case 3: .rgb
        default: .unknown
        }

        var summary: [MetadataEntry] = []
        if hasApple { summary.append(MetadataEntry(key: "Apple legacy gain map", value: "Detected")) }
        if hasISO { summary.append(MetadataEntry(key: "ISO 21496-1", value: "Detected")) }
        if hasUltraHDR { summary.append(MetadataEntry(key: "Ultra HDR XMP", value: "Detected")) }
        summary.append(MetadataEntry(key: "Container layout", value: layout.rawValue))

        return GainMapInfo(
            kind: kind,
            size: signals.gainMapSize,
            bitDepth: 8,
            channelModel: channelModel,
            layout: layout,
            metadataSummary: summary
        )
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
            case .ultraHDR, .hybrid:
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
        container: ImageContainer,
        hdrKind: HDRKind,
        gainMap: GainMapInfo?,
        signals: GainMapSignals,
        bitDepth: Int?,
        colorSpace: ColorSpaceKind?
    ) -> [DiagnosticItem] {
        var items: [DiagnosticItem] = []

        if let bitDepth, bitDepth < 8 {
            items.append(DiagnosticItem(severity: .error, message: "Bit depth is unexpectedly low."))
        }

        if [.pqHDR, .hlgHDR, .hdrUnknown].contains(hdrKind), colorSpace == .sRGB {
            items.append(DiagnosticItem(severity: .warning, message: "Direct HDR tagging with an sRGB color space is suspicious."))
        }

        if gainMap != nil {
            items.append(DiagnosticItem(severity: .info, message: "An SDR base plus gain map was detected."))
        }

        if signals.hasGainMapSignal, container == .jpeg, !signals.hasMPF {
            items.append(DiagnosticItem(severity: .error, message: "JPEG gain-map markers were found, but no MPF index was detected."))
        }

        if signals.hasUltraHDRXMP, !signals.hasGContainer {
            items.append(DiagnosticItem(severity: .warning, message: "Ultra HDR XMP was found without a GContainer directory."))
        }

        if signals.hasISO21496Marker, !signals.hasISOAuxiliary {
            items.append(DiagnosticItem(
                severity: .info,
                message: "ISO 21496-1 is declared in the file but has not yet been accepted by ImageIO."
            ))
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
        signals: GainMapSignals,
        diagnostics: [DiagnosticItem]
    ) -> CompatibilityReport {
        let hasWarnings = diagnostics.contains(where: { $0.severity != .info })
        let hasGainMap = gainMap != nil
        let nativeHeadroom = signals.nativeHDRHeadroom ?? 1
        let appleDeclared = signals.hasAppleAuxiliary || signals.hasAppleLegacyMarker || gainMap?.kind == .apple
        let isoDeclared = signals.hasISOAuxiliary || signals.hasISO21496Marker ||
            gainMap?.kind == .iso21496 || gainMap?.kind == .hybrid
        let ultraHDRDeclared = signals.hasUltraHDRXMP ||
            gainMap?.kind == .ultraHDR || gainMap?.kind == .hybrid

        let appleLegacy: CompatibilityStatus = signals.hasAppleAuxiliary
            ? .verified
            : appleDeclared ? .declared : .notDetected
        let iso21496: CompatibilityStatus = signals.hasISOAuxiliary
            ? .verified
            : isoDeclared ? .declared : .notDetected
        let ultraHDRV1: CompatibilityStatus = ultraHDRDeclared && signals.hasGContainer
            ? .declared
            : (ultraHDRDeclared ? .declared : .notDetected)
        let appleDecode: CompatibilityStatus = hasGainMap
            ? ((signals.hasAppleAuxiliary || signals.hasISOAuxiliary || nativeHeadroom > 1.0001) ? .verified : .notDetected)
            : .notApplicable
        let androidDecode: CompatibilityStatus = hasGainMap && (ultraHDRDeclared || isoDeclared)
            ? .declared
            : (hasGainMap ? .notDetected : .notApplicable)

        let formatCompatibility = GainMapFormatCompatibility(
            appleLegacy: appleLegacy,
            iso21496: iso21496,
            ultraHDRV1: ultraHDRV1,
            appleDecode: appleDecode,
            androidDecode: androidDecode
        )

        let appleReady = appleDecode == .verified ||
            (container == .heic && [.pqHDR, .hlgHDR].contains(hdrKind))
        let instagramReady = hasGainMap && (ultraHDRV1 != .notDetected || iso21496 != .notDetected)
        let sdrFallbackOK = hasGainMap || hdrKind == .sdr

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
        if gainMap?.kind == .hybrid {
            notes.append("Both ISO 21496-1 and Ultra HDR v1 metadata are present.")
        }
        if appleDecode == .verified {
            notes.append("Apple ImageIO/Core Image accepts the gain map.")
        }
        if androidDecode == .declared {
            notes.append("Android/Ultra HDR compatibility is declared; decoder verification is pending.")
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
            notes: notes,
            gainMapFormats: formatCompatibility
        )
    }

    private func joinedMetadata(_ metadata: [String: String]) -> String {
        metadata.map(\.key).joined(separator: " ") + " " + metadata.map(\.value).joined(separator: " ")
    }
}
