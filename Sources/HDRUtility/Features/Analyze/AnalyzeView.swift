import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AnalyzeView: View {
    @State private var model = AnalyzeViewModel()
    @State private var isFileImporterPresented = false
    @State private var importMode: AnalyzeImportMode = .append
    @State private var detailTab: AnalyzeDetailTab = .summary
    @State private var metadataSearchText = ""
    @State private var isRecordsDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let errorMessage = model.errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                content
            }
            .padding(24)
        }
        .navigationTitle("Analyze")
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: handleImportResult
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Analyze HDR Assets")
                    .font(.largeTitle.weight(.bold))
                Text("Inspect container, HDR tagging, gain maps and compatibility before conversion.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Add Files", action: presentAddImporter)
                    .buttonStyle(.borderedProminent)
                Button("Clear Session", role: .destructive, action: model.clearSession)
                    .buttonStyle(.bordered)
                    .disabled(model.records.isEmpty)
            }
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 20) {
            recordsPanel
                .frame(width: 360)

            if let selectedRecord = model.selectedRecord {
                inspectorPanel(record: selectedRecord)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else if model.records.isEmpty {
                ContentUnavailableView(
                    "Drop Files To Start",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Add one or more image files from Finder to inspect their HDR metadata and compatibility.")
                )
                .frame(maxWidth: .infinity, minHeight: 520)
                .cardStyle()
            } else {
                ContentUnavailableView(
                    "No Matching File",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Adjust the search or filter to inspect a file.")
                )
                .frame(maxWidth: .infinity, minHeight: 520)
                .cardStyle()
            }
        }
    }

    private var recordsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            RecordsDropHint(isEmpty: model.records.isEmpty, isTargeted: isRecordsDropTargeted)

            HStack(spacing: 10) {
                TextField("Search name, format, profile", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.records.isEmpty)

                Picker("Filter", selection: $model.filter) {
                    ForEach(AnalyzeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .disabled(model.records.isEmpty)
            }

            Text("\(model.filteredRecords.count) visible")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Drop files directly in this panel at any time.")
                        .font(.headline)
                    Text("Single-file and multi-file drops are supported. Once imported, click any item to update the preview on the right.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
            } else if model.filteredRecords.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("No files match the current search and filter.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.filteredRecords) { record in
                            AnalyzeRecordRow(
                                record: record,
                                isSelected: model.selectedRecord?.id == record.id,
                                action: {
                                    model.selectRecord(record)
                                    detailTab = .summary
                                    metadataSearchText = ""
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(18)
        .cardStyle()
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isRecordsDropTargeted ? Color.accentColor.opacity(0.65) : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isRecordsDropTargeted, perform: handleDroppedProviders)
    }

    private func inspectorPanel(record: HDRFileRecord) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PreviewCard(record: record)

            VerdictSummaryCard(record: record)

            QuickFactsCard(record: record)

            VStack(alignment: .leading, spacing: 12) {
                Picker("Detail", selection: $detailTab) {
                    ForEach(AnalyzeDetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch detailTab {
                case .summary:
                    SummaryDetailCard(record: record)
                case .diagnostics:
                    DiagnosticsCard(record: record)
                case .metadata:
                    MetadataCard(record: record, searchText: $metadataSearchText)
                }
            }
            .padding(18)
            .cardStyle()
        }
    }

    private func presentAddImporter() {
        importMode = .append
        isFileImporterPresented = true
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            model.importFiles(urls: urls, mode: importMode)
        case let .failure(error):
            model.errorMessage = error.localizedDescription
        }
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let collector = DroppedURLCollector()

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                continue
            }

            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collector.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            let collected = collector.snapshot()
            guard collected.isEmpty == false else { return }
            let mode: AnalyzeImportMode = model.records.isEmpty ? .replace : .append
            model.importFiles(urls: collected, mode: mode)
        }

        return true
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}


private struct RecordsDropHint: View {
    let isEmpty: Bool
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isEmpty ? "square.and.arrow.down" : "plus.square.dashed")
                .font(.system(size: isEmpty ? 28 : 18, weight: .medium))
            Text(isEmpty ? "Drop image files here" : "Drop more files anywhere in this list")
                .font(isEmpty ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
            Text("JPEG, HEIC, AVIF, TIFF, EXR and gain map candidates are supported.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: isEmpty ? 180 : 92)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
                }
        }
    }
}

private final class DroppedURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        let snapshot = urls
        lock.unlock()
        return snapshot
    }
}

private struct AnalyzeRecordRow: View {
    let record: HDRFileRecord
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                FileGlyph(record: record)

                VStack(alignment: .leading, spacing: 8) {
                    Text(record.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(record.specificationLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        TagBadge(title: record.hdrKind.displayLabel, tint: .blue)
                        TagBadge(title: record.compatibility.verdict.displayLabel, tint: record.compatibility.verdict.tintColor)
                        if record.diagnostics.contains(where: { $0.severity == .warning }) {
                            TagBadge(title: "Warning", tint: .orange)
                        }
                        if record.diagnostics.contains(where: { $0.severity == .error }) {
                            TagBadge(title: "Error", tint: .red)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
        }
        .buttonStyle(.plain)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1.5)
            }
    }
}

private struct FileGlyph: View {
    let record: HDRFileRecord

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(record.compatibility.verdict.tintColor.opacity(0.14))
            .frame(width: 52, height: 52)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: record.container.symbolName)
                        .font(.headline)
                    Text(record.container.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .foregroundStyle(record.compatibility.verdict.tintColor)
            }
    }
}

private struct PreviewCard: View {
    let record: HDRFileRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                PreviewImageView(url: record.url)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)

                VStack(alignment: .leading, spacing: 12) {
                    TagBadge(title: record.hdrStatusLabel, tint: .blue)
                    TagBadge(title: record.hdrKind.displayLabel, tint: .indigo)
                    if let gainMap = record.gainMap {
                        TagBadge(title: gainMap.kind.displayLabel, tint: .mint)
                    }

                    Button("Open") {
                        NSWorkspace.shared.open(record.url)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([record.url])
                    }
                    .buttonStyle(.bordered)

                    Button("Copy Metadata") {
                        let payload = record.metadata
                            .map { "\($0.key): \($0.value)" }
                            .joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(payload, forType: .string)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(width: 180, alignment: .topLeading)
            }
        }
        .padding(18)
        .cardStyle()
    }
}

private struct PreviewImageView: View {
    let url: URL

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.black.opacity(0.88), .gray.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(20)
            } else {
                ContentUnavailableView(
                    "Preview Unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("The file can still be inspected through metadata and diagnostics.")
                )
            }
        }
        .task(id: url) {
            image = NSImage(contentsOf: url)
        }
    }
}

private struct VerdictSummaryCard: View {
    let record: HDRFileRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.compatibility.verdict.displayLabel)
                        .font(.title3.weight(.bold))
                    Text(record.recommendation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TagBadge(title: record.compatibility.verdict.statusLabel, tint: record.compatibility.verdict.tintColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Why this verdict")
                    .font(.headline)
                ForEach(record.primaryReasons, id: \.self) { reason in
                    Label(reason, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .cardStyle()
    }
}

private struct QuickFactsCard: View {
    let record: HDRFileRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Facts")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                FactCell(title: "Container", value: record.container.rawValue.uppercased())
                FactCell(title: "Resolution", value: record.pixelSizeText)
                FactCell(title: "Bit Depth", value: record.bitDepthText)
                FactCell(title: "Color Space", value: record.colorSpaceText)
                FactCell(title: "Transfer", value: record.transferFunction.displayLabel)
                FactCell(title: "HDR Kind", value: record.hdrKind.displayLabel)
                FactCell(title: "Gain Map", value: record.gainMap?.kind.displayLabel ?? "None")
                FactCell(title: "SDR Fallback", value: record.compatibility.sdrFallbackOK ? "OK" : "Unknown")
            }
        }
        .padding(18)
        .cardStyle()
    }
}

private struct FactCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SummaryDetailCard: View {
    let record: HDRFileRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.displayName)
                .font(.headline)
            Text(record.specificationLine)
                .foregroundStyle(.secondary)

            if record.compatibility.notes.isEmpty {
                Text("No additional compatibility notes were reported.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(record.compatibility.notes, id: \.self) { note in
                    Label(note, systemImage: "text.badge.checkmark")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiagnosticsCard: View {
    let record: HDRFileRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if record.diagnostics.isEmpty {
                ContentUnavailableView(
                    "No Issues Detected",
                    systemImage: "checkmark.seal",
                    description: Text("This file did not emit warnings or errors during analysis.")
                )
            } else {
                ForEach(record.diagnostics) { diagnostic in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: diagnostic.severity.symbolName)
                            .foregroundStyle(diagnostic.severity.tintColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(diagnostic.severity.displayLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(diagnostic.severity.tintColor)
                            Text(diagnostic.message)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(diagnostic.severity.tintColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetadataCard: View {
    let record: HDRFileRecord
    @Binding var searchText: String

    private var filteredMetadata: [MetadataEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.isEmpty == false else { return record.metadata }

        return record.metadata.filter {
            $0.key.lowercased().contains(query) || $0.value.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search metadata", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredMetadata) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.key)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(entry.value)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .frame(minHeight: 180)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TagBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private enum AnalyzeDetailTab: String, CaseIterable, Identifiable {
    case summary
    case diagnostics
    case metadata

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary:
            "Summary"
        case .diagnostics:
            "Diagnostics"
        case .metadata:
            "Metadata"
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private extension HDRFileRecord {
    var displayName: String {
        url.lastPathComponent
    }

    var specificationLine: String {
        [
            container.rawValue.uppercased(),
            bitDepthText,
            colorSpaceText,
            pixelSizeText
        ]
            .joined(separator: " • ")
    }

    var bitDepthText: String {
        bitDepth.map { "\($0)-bit" } ?? "Unknown"
    }

    var colorSpaceText: String {
        colorSpace?.displayLabel ?? "Unknown"
    }

    var pixelSizeText: String {
        guard let pixelSize else { return "Unknown" }
        return "\(Int(pixelSize.width))×\(Int(pixelSize.height))"
    }

    var hdrStatusLabel: String {
        hdrKind == .sdr ? "SDR" : "HDR Detected"
    }

    var primaryReasons: [String] {
        let notes = compatibility.notes.filter { $0.isEmpty == false }
        if notes.isEmpty == false {
            return Array(notes.prefix(4))
        }

        let diagnostics = diagnostics.map(\.message)
        if diagnostics.isEmpty == false {
            return Array(diagnostics.prefix(4))
        }

        return ["No specific compatibility issues were reported."]
    }

    var recommendation: String {
        switch compatibility.verdict {
        case .readyForApple:
            "Ready for the Apple pipeline."
        case .readyForInstagram:
            "Good candidate for the Instagram export path."
        case .hdrLimitedCompatibility:
            "Review metadata before conversion or distribution."
        case .likelyBrokenGainMap:
            "The gain map likely needs regeneration or repair."
        case .suspiciousSDRTagging:
            "The tagging looks inconsistent and should be verified."
        case .standardSDR:
            "Treat this file as SDR unless you have an external HDR source." 
        }
    }
}

private extension ImageContainer {
    var symbolName: String {
        switch self {
        case .jpeg, .heic, .avif, .png, .tiff, .exr, .jxl:
            "photo"
        case .unknown:
            "questionmark.square.dashed"
        }
    }
}

private extension CompatibilityVerdict {
    var displayLabel: String {
        switch self {
        case .readyForApple:
            "Ready for Apple"
        case .readyForInstagram:
            "Ready for Instagram"
        case .hdrLimitedCompatibility:
            "Limited HDR Compatibility"
        case .likelyBrokenGainMap:
            "Likely Broken Gain Map"
        case .suspiciousSDRTagging:
            "Suspicious SDR Tagging"
        case .standardSDR:
            "Standard SDR"
        }
    }

    var statusLabel: String {
        switch self {
        case .readyForApple, .readyForInstagram:
            "Ready"
        case .hdrLimitedCompatibility:
            "Limited"
        case .likelyBrokenGainMap, .suspiciousSDRTagging:
            "Problem"
        case .standardSDR:
            "SDR"
        }
    }

    var tintColor: Color {
        switch self {
        case .readyForApple:
            .green
        case .readyForInstagram:
            .mint
        case .hdrLimitedCompatibility:
            .orange
        case .likelyBrokenGainMap, .suspiciousSDRTagging:
            .red
        case .standardSDR:
            .gray
        }
    }
}

private extension HDRKind {
    var displayLabel: String {
        switch self {
        case .sdr:
            "SDR"
        case .appleGainMap:
            "Apple Gain Map"
        case .isoGainMap:
            "ISO Gain Map"
        case .ultraHDR:
            "Ultra HDR"
        case .pqHDR:
            "PQ HDR"
        case .hlgHDR:
            "HLG HDR"
        case .hdrUnknown:
            "Unknown HDR"
        }
    }
}

private extension GainMapKind {
    var displayLabel: String {
        switch self {
        case .apple:
            "Apple Gain Map"
        case .iso21496:
            "ISO 21496"
        case .ultraHDR:
            "Ultra HDR"
        case .unknown:
            "Unknown Gain Map"
        }
    }
}

private extension TransferFunction {
    var displayLabel: String {
        rawValue.uppercased()
    }
}

private extension ColorSpaceKind {
    var displayLabel: String {
        switch self {
        case .sRGB:
            "sRGB"
        case .displayP3:
            "Display P3"
        case .rec2020:
            "Rec. 2020"
        case .extendedLinearSRGB:
            "Extended Linear sRGB"
        case .unknown:
            "Unknown"
        }
    }
}

private extension DiagnosticSeverity {
    var symbolName: String {
        switch self {
        case .info:
            "info.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.octagon.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .info:
            .blue
        case .warning:
            .orange
        case .error:
            .red
        }
    }

    var displayLabel: String {
        rawValue.capitalized
    }
}
