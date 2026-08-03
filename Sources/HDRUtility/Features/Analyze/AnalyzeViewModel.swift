import Foundation

@MainActor
@Observable
final class AnalyzeViewModel {
    var records: [HDRFileRecord] = []
    var selectedRecordID: HDRFileRecord.ID?
    var errorMessage: String?
    var searchText = ""
    var filter: AnalyzeFilter = .all

    private let analyzer = ImageAnalyzer()

    var filteredRecords: [HDRFileRecord] {
        records.filter(matchesFilters)
    }

    var selectedRecord: HDRFileRecord? {
        if let selectedRecordID,
           let record = records.first(where: { $0.id == selectedRecordID }) {
            return record
        }

        return filteredRecords.first
    }

    var fileCount: Int {
        records.count
    }

    var appleReadyCount: Int {
        records.filter(\.compatibility.appleReady).count
    }

    var instagramReadyCount: Int {
        records.filter(\.compatibility.instagramReady).count
    }

    var warningCount: Int {
        records.filter { $0.diagnostics.contains(where: { $0.severity == .warning }) }.count
    }

    var isoCount: Int {
        records.filter { $0.compatibility.gainMapFormats.iso21496.isDetected }.count
    }

    var ultraHDRCount: Int {
        records.filter { $0.compatibility.gainMapFormats.ultraHDRV1.isDetected }.count
    }

    var appleLegacyCount: Int {
        records.filter { $0.compatibility.gainMapFormats.appleLegacy.isDetected }.count
    }

    var rgbGainMapCount: Int {
        records.filter { $0.gainMap?.channelModel == .rgb }.count
    }

    var crossPlatformCount: Int {
        records.filter { $0.compatibility.gainMapFormats.crossPlatformVerified }.count
    }

    var problemCount: Int {
        records.filter(hasProblem).count
    }

    func importFiles(urls: [URL], mode: AnalyzeImportMode) {
        let incomingURLs = urls.map(\.standardizedFileURL)
        guard incomingURLs.isEmpty == false else { return }

        var nextRecords = mode == .replace ? [] : records
        var failures: [String] = []

        for url in incomingURLs {
            do {
                let record = try analyzer.analyze(url: url)
                if let existingIndex = nextRecords.firstIndex(where: { $0.url.standardizedFileURL == url }) {
                    nextRecords[existingIndex] = record
                } else {
                    nextRecords.append(record)
                }
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        nextRecords.sort {
            $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
        }

        records = nextRecords
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        synchronizeSelection(preferredURLs: incomingURLs)

        Task {
            await enrichGainMapRecords(urls: incomingURLs)
        }
    }

    func clearSession() {
        records = []
        selectedRecordID = nil
        errorMessage = nil
        searchText = ""
        filter = .all
    }

    func selectRecord(_ record: HDRFileRecord) {
        selectedRecordID = record.id
    }

    private func synchronizeSelection(preferredURLs: [URL]) {
        if let matchingRecord = filteredRecords.first(where: { preferredURLs.contains($0.url.standardizedFileURL) }) {
            selectedRecordID = matchingRecord.id
            return
        }

        if let selectedRecordID,
           filteredRecords.contains(where: { $0.id == selectedRecordID }) {
            return
        }

        selectedRecordID = filteredRecords.first?.id
    }

    private func matchesFilters(_ record: HDRFileRecord) -> Bool {
        matchesSearch(record) && matchesFilter(record)
    }

    private func matchesSearch(_ record: HDRFileRecord) -> Bool {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else { return true }

        let query = trimmedQuery.lowercased()
        let haystack = [
            record.url.lastPathComponent,
            record.url.pathExtension,
            record.container.rawValue,
            record.hdrKind.rawValue,
            record.transferFunction.rawValue,
            record.compatibility.verdict.rawValue,
            record.colorSpace?.rawValue ?? "",
            record.compatibility.notes.joined(separator: " ")
        ]
            .joined(separator: " ")
            .lowercased()

        return haystack.contains(query)
    }

    private func matchesFilter(_ record: HDRFileRecord) -> Bool {
        switch filter {
        case .all:
            true
        case .ready:
            record.compatibility.appleReady || record.compatibility.instagramReady
        case .warnings:
            record.diagnostics.contains(where: { $0.severity == .warning })
        case .errors:
            hasProblem(record)
        case .gainMap:
            record.gainMap != nil
        case .iso:
            record.compatibility.gainMapFormats.iso21496.isDetected
        case .apple:
            record.compatibility.gainMapFormats.appleLegacy.isDetected
        case .ultraHDR:
            record.compatibility.gainMapFormats.ultraHDRV1.isDetected
        case .rgb:
            record.gainMap?.channelModel == .rgb
        }
    }

    private func hasProblem(_ record: HDRFileRecord) -> Bool {
        record.diagnostics.contains(where: { $0.severity == .error }) || [
            CompatibilityVerdict.likelyBrokenGainMap,
            .suspiciousSDRTagging
        ].contains(record.compatibility.verdict)
    }

    private func enrichGainMapRecords(urls: [URL]) async {
        let service = ConversionService()
        for url in urls {
            guard let index = records.firstIndex(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else {
                continue
            }
            guard let inspection = try? await service.verifyOutput(url: url), inspection.hasGainMap else {
                continue
            }

            let current = records[index]
            let hasApple = current.gainMapSignals.hasAppleAuxiliary ||
                current.gainMapSignals.hasAppleLegacyMarker || inspection.hasAppleAuxiliary ||
                inspection.hasAppleLegacyMarker || inspection.gainMapKind == "apple"
            let hasISO = current.gainMapSignals.hasISOAuxiliary ||
                current.gainMapSignals.hasISO21496Marker || inspection.hasISOAuxiliary || inspection.hasISO21496
            let hasUltraHDR = current.gainMapSignals.hasUltraHDRXMP || inspection.hasXMP
            let decoderVerified = inspection.ultraHDRDecoderVerified
            let channelModel: GainMapChannelModel = switch inspection.gainMapChannels {
            case 1: .monochrome
            case 3: .rgb
            default: .unknown
            }

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
            let hdrKind: HDRKind = switch kind {
            case .apple: .appleGainMap
            case .iso21496: .isoGainMap
            case .ultraHDR, .hybrid: .ultraHDR
            case .unknown: .hdrUnknown
            }
            let gainMap = GainMapInfo(
                kind: kind,
                size: inspection.gainMapWidth > 0 && inspection.gainMapHeight > 0
                    ? CGSize(width: inspection.gainMapWidth, height: inspection.gainMapHeight)
                    : nil,
                bitDepth: 8,
                channelModel: channelModel,
                layout: current.gainMap?.layout ?? .unknown,
                metadataSummary: [
                    MetadataEntry(key: "Gain map channels", value: channelModel.metadataLabel),
                    MetadataEntry(key: "Ultra HDR XMP", value: inspection.hasXMP ? "Present" : "Not detected"),
                    MetadataEntry(key: "ISO 21496-1", value: inspection.hasISO21496 ? "Present" : "Not detected"),
                    MetadataEntry(key: "SDR fallback", value: inspection.hasSDRFallback ? "Verified" : "Missing"),
                    MetadataEntry(key: "libultrahdr decode", value: decoderVerified ? "Verified" : "Not verified")
                ]
            )
            var diagnostics = current.diagnostics
            diagnostics.append(DiagnosticItem(
                severity: inspection.hasSDRFallback ? .info : .error,
                message: inspection.hasSDRFallback
                    ? "Embedded SDR fallback verified by libultrahdr."
                    : "Gain map found without a verified SDR fallback."
            ))

            let appleLegacyStatus: CompatibilityStatus = current.gainMapSignals.hasAppleAuxiliary || inspection.hasAppleAuxiliary
                ? .verified
                : ((current.gainMapSignals.hasAppleLegacyMarker || inspection.hasAppleLegacyMarker) ? .declared : .notDetected)
            let isoStatus: CompatibilityStatus = current.gainMapSignals.hasISOAuxiliary || inspection.hasISOAuxiliary || (hasISO && decoderVerified)
                ? .verified
                : (hasISO ? .declared : .notDetected)
            let ultraHDRStatus: CompatibilityStatus = hasUltraHDR && decoderVerified
                ? .verified
                : (hasUltraHDR ? .declared : .notDetected)
            let appleDecodeStatus: CompatibilityStatus = current.gainMapSignals.hasAppleAuxiliary ||
                current.gainMapSignals.hasISOAuxiliary || inspection.hasAppleAuxiliary || inspection.hasISOAuxiliary ||
                (current.gainMapSignals.nativeHDRHeadroom ?? 1) > 1.0001
                ? .verified
                : .notDetected
            let androidDecodeStatus: CompatibilityStatus = decoderVerified
                ? .verified
                : ((hasISO || hasUltraHDR) ? .declared : .notDetected)
            let formatCompatibility = GainMapFormatCompatibility(
                appleLegacy: appleLegacyStatus,
                iso21496: isoStatus,
                ultraHDRV1: ultraHDRStatus,
                appleDecode: appleDecodeStatus,
                androidDecode: androidDecodeStatus
            )

            let verdict: CompatibilityVerdict
            if formatCompatibility.crossPlatformVerified {
                verdict = .crossPlatformGainMap
            } else if appleDecodeStatus == .verified {
                verdict = .readyForApple
            } else if androidDecodeStatus == .verified {
                verdict = .readyForInstagram
            } else {
                verdict = .hdrLimitedCompatibility
            }

            var notes = [
                channelModel == .rgb
                    ? "RGB gain map with independent color ratios."
                    : (channelModel == .monochrome ? "Monochrome brightness-ratio gain map." : "Gain-map channel count could not be verified."),
                hasISO ? "ISO 21496-1 metadata detected." : "ISO 21496-1 metadata not detected.",
                hasUltraHDR ? "Ultra HDR v1 XMP/GContainer detected." : "Ultra HDR v1 metadata not detected."
            ]
            if formatCompatibility.crossPlatformVerified {
                notes.insert("Verified by both Apple ImageIO/Core Image and libultrahdr.", at: 0)
            }
            let compatibility = CompatibilityReport(
                appleReady: appleDecodeStatus == .verified,
                instagramReady: inspection.hasSDRFallback && androidDecodeStatus == .verified,
                sdrFallbackOK: inspection.hasSDRFallback,
                verdict: verdict,
                notes: notes,
                gainMapFormats: formatCompatibility
            )
            records[index] = HDRFileRecord(
                id: current.id,
                url: current.url,
                container: current.container,
                pixelSize: current.pixelSize,
                bitDepth: current.bitDepth,
                colorSpace: current.colorSpace,
                transferFunction: current.transferFunction,
                hdrKind: hdrKind,
                gainMap: gainMap,
                gainMapSignals: current.gainMapSignals,
                metadata: current.metadata + gainMap.metadataSummary,
                diagnostics: diagnostics,
                compatibility: compatibility
            )
        }
    }
}

enum AnalyzeImportMode {
    case replace
    case append
}

enum AnalyzeFilter: String, CaseIterable, Identifiable {
    case all
    case ready
    case warnings
    case errors
    case gainMap
    case iso
    case apple
    case ultraHDR
    case rgb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .ready:
            "Ready"
        case .warnings:
            "Warnings"
        case .errors:
            "Errors"
        case .gainMap:
            "Gain Map"
        case .iso:
            "ISO 21496"
        case .apple:
            "Apple"
        case .ultraHDR:
            "Ultra HDR"
        case .rgb:
            "RGB Map"
        }
    }
}

private extension CompatibilityStatus {
    var isDetected: Bool {
        self == .verified || self == .declared
    }
}

private extension GainMapChannelModel {
    var metadataLabel: String {
        switch self {
        case .monochrome: "Monochrome (1 channel)"
        case .rgb: "RGB (3 channels)"
        case .unknown: "Unknown"
        }
    }
}
