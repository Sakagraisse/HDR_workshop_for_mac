import Foundation

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
        }
    }

    private func hasProblem(_ record: HDRFileRecord) -> Bool {
        record.diagnostics.contains(where: { $0.severity == .error }) || [
            CompatibilityVerdict.likelyBrokenGainMap,
            .suspiciousSDRTagging
        ].contains(record.compatibility.verdict)
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
        }
    }
}
