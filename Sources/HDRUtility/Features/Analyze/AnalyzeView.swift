import SwiftUI

struct AnalyzeView: View {
    @State private var model = AnalyzeViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                FileDropZone(
                    title: "Drop image files",
                    subtitle: "Inspect JPEG, HEIC, AVIF, TIFF, EXR and gain map candidates.",
                    supportsMultiple: true,
                    onReceiveURLs: model.analyzeFiles(urls:)
                )

                SummaryPanel(records: model.records)
                    .frame(width: 280)
            }

            if let errorMessage = model.errorMessage {
                ContentUnavailableView("Analysis Failed", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                Table(model.records, selection: $model.selection) {
                    TableColumn("File") { record in
                        Text(record.url.lastPathComponent)
                    }
                    TableColumn("Container") { record in
                        Text(record.container.rawValue.uppercased())
                    }
                    TableColumn("HDR") { record in
                        Text(record.hdrKind.rawValue)
                    }
                    TableColumn("Transfer") { record in
                        Text(record.transferFunction.rawValue.uppercased())
                    }
                    TableColumn("Verdict") { record in
                        Text(record.compatibility.verdict.rawValue)
                    }
                }
            }

            if let selected = model.selectedRecord {
                RecordDetailView(record: selected)
                    .frame(maxHeight: 280)
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.right", description: Text("Select a file to inspect metadata, diagnostics and compatibility."))
                    .frame(maxWidth: .infinity, maxHeight: 280)
            }
        }
        .padding(24)
        .navigationTitle("Analyze")
    }
}

private struct SummaryPanel: View {
    let records: [HDRFileRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session")
                .font(.headline)
            LabeledContent("Files", value: "\(records.count)")
            LabeledContent("Apple-ready", value: "\(records.filter(\.compatibility.appleReady).count)")
            LabeledContent("Instagram-ready", value: "\(records.filter(\.compatibility.instagramReady).count)")
            LabeledContent("Gain maps", value: "\(records.filter { $0.gainMap != nil }.count)")
            Spacer()
        }
        .padding(18)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RecordDetailView: View {
    let record: HDRFileRecord

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(record.url.lastPathComponent)
                    .font(.headline)
                LabeledContent("Container", value: record.container.rawValue.uppercased())
                LabeledContent("Bit Depth", value: record.bitDepth.map(String.init) ?? "Unknown")
                LabeledContent("Color Space", value: record.colorSpace?.rawValue ?? "Unknown")
                LabeledContent("HDR Kind", value: record.hdrKind.rawValue)
                LabeledContent("Verdict", value: record.compatibility.verdict.rawValue)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Diagnostics")
                    .font(.headline)
                ForEach(record.diagnostics) { item in
                    Label(item.message, systemImage: icon(for: item.severity))
                        .foregroundStyle(color(for: item.severity))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Metadata")
                    .font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(record.metadata.prefix(14)) { entry in
                            Text("\(entry.key): \(entry.value)")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func icon(for severity: DiagnosticSeverity) -> String {
        switch severity {
        case .info:
            "info.circle"
        case .warning:
            "exclamationmark.triangle"
        case .error:
            "xmark.octagon"
        }
    }

    private func color(for severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .info:
            .primary
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}
