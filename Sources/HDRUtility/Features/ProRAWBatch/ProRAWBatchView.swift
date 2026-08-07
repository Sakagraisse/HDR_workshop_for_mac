import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProRAWBatchView: View {
    @Environment(AppState.self) private var appState
    @State private var model = ProRAWBatchViewModel()
    @State private var showsTechnicalDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red).padding().utilityCardStyle()
                }
                HStack(alignment: .top, spacing: 20) {
                    sourcesCard
                    settingsCard.frame(width: 420)
                }
                DisclosureGroup("Technical details", isExpanded: $showsTechnicalDetails) {
                    ConversionLogPanel(
                        job: model.lastJob,
                        emptyMessage: "Convert Apple ProRAW/DNG files to Apple-compatible HEIC."
                    )
                    .frame(minHeight: 240)
                    .padding(.top, 10)
                }
                .font(.headline)
                .padding(18)
                .utilityCardStyle()
            }
            .padding(24)
        }
        .navigationTitle("ProRAW → HEIC (Batch)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ProRAW → HEIC (Batch)").font(.largeTitle.bold())
            Text("Convert Apple ProRAW files in parallel, preserving HDR gain maps when present and falling back cleanly to SDR when absent.")
                .foregroundStyle(.secondary)
        }
    }

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(model.request.sources.count) ProRAW/DNG file\(model.request.sources.count == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
                Button("Choose Files or Folder") { model.addSources(chooseSources()) }
                Button("Clear", action: model.clear)
                    .disabled(model.request.sources.isEmpty)
            }

            if model.request.sources.isEmpty {
                FileDropZone(
                    title: "Drop ProRAW files or a folder",
                    subtitle: "The folder is scanned recursively for .dng files.",
                    supportsMultiple: true,
                    onReceiveURLs: model.addSources
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.request.sources, id: \.self) { url in
                            HStack(spacing: 10) {
                                statusIndicator(for: model.itemStates[url] ?? .pending)
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                                Text(statusLabel(for: model.itemStates[url] ?? .pending))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(statusColor(for: model.itemStates[url] ?? .pending))
                            }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .frame(maxHeight: 340)

                HStack(spacing: 18) {
                    Label("\(model.hdrCount) HDR", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("\(model.sdrCount) SDR", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.yellow)
                    Label("\(model.failedCount) failed", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Spacer()
                    Text("\(model.remainingCount) remaining")
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))
            }

            Divider()
            HStack {
                Text(model.request.outputFolder?.path(percentEncoded: false) ?? "No export folder")
                    .lineLimit(1)
                Spacer()
                Button("Choose Folder") { model.request.outputFolder = chooseFolder() }
            }

            Button(model.isRunning ? "Converting…" : "Convert Batch to HEIC") {
                Task { @MainActor in
                    let job = await model.run()
                    appState.record(job: job)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRun)
        }
        .padding(18)
        .utilityCardStyle()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Apple HEIC Settings").font(.headline)
            Label("Apple ImageIO", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)

            LabeledContent("Output", value: "HEIC · Apple HDR or SDR")
            Text("ImageIO preserves Apple's HDR gain map when present. ProRAW files without a gain map are exported automatically as SDR HEIC.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Gain map", value: "Preserved when present")

            Toggle("Reduce 48 MP to Apple 24 MP", isOn: $model.request.resizeToApple24MP)
            Text("Caps the long edge at 5712 px (5712×4284 for 4:3). ImageIO scales the SDR image and Apple gain map together; smaller photos are not enlarged.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: $model.request.quality, in: 0.60...1.0, step: 0.01) {
                Text("Compression quality")
            }
            LabeledContent("Compression quality", value: model.request.quality.formatted(.percent.precision(.fractionLength(0))))

            Picker("Parallel conversions", selection: $model.request.parallelConversions) {
                ForEach(ProRAWBatchConversionRequest.parallelConversionChoices, id: \.self) { count in
                    Text("\(count) files").tag(count)
                }
            }
            .pickerStyle(.menu)

            Text("Higher values can improve large batches, but require more unified memory while ProRAW files are being developed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Filename suffix", text: $model.request.outputSuffix)
                .textFieldStyle(.roundedBorder)

            Divider()
            Text("Each worker uses Apple's direct ImageIO path. No HDR reconstruction, manual headroom or custom tone mapping is applied; SDR is the automatic fallback.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .utilityCardStyle()
    }

    @ViewBuilder
    private func statusIndicator(for state: ProRAWBatchItemState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .processing:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .hdr:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .sdr:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.yellow)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func statusLabel(for state: ProRAWBatchItemState) -> String {
        switch state {
        case .pending: "Pending"
        case .processing: "Converting"
        case .hdr: "HDR"
        case .sdr: "SDR"
        case .failed: "Failed"
        }
    }

    private func statusColor(for state: ProRAWBatchItemState) -> Color {
        switch state {
        case .hdr: .green
        case .sdr: .yellow
        case .failed: .red
        case .pending, .processing: .secondary
        }
    }

    private func chooseSources() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.rawImage]
        return panel.runModal() == .OK ? panel.urls : []
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
