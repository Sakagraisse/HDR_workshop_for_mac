import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProRAWBatchView: View {
    @Environment(AppState.self) private var appState
    @State private var model = ProRAWBatchViewModel()

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
                ConversionLogPanel(
                    job: model.lastJob,
                    emptyMessage: "Convert Apple ProRAW/DNG files to recent Apple Adaptive HDR HEIC."
                )
                .frame(minHeight: 240)
            }
            .padding(24)
        }
        .navigationTitle("ProRAW → HEIC (Batch)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ProRAW → HEIC (Batch)").font(.largeTitle.bold())
            Text("Batch-develop Apple ProRAW files and export compact HEIC images with an SDR base and an ISO 21496-1 Adaptive HDR gain map.")
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
                            Label(url.lastPathComponent, systemImage: "camera.raw")
                                .lineLimit(1)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .frame(maxHeight: 340)
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
            Label("Adaptive HDR · ISO 21496-1", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text("HEIF is the container family; HEIC is the usual filename extension when HEVC compression is used. This exporter writes .heic.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: $model.request.quality, in: 0.60...1.0, step: 0.01) {
                Text("Compression quality")
            }
            LabeledContent("Compression quality", value: model.request.quality.formatted(.percent.precision(.fractionLength(0))))

            Picker("Base color space", selection: $model.request.colorSpace) {
                Text("Display P3 (recommended)").tag(ColorSpaceKind.displayP3)
                Text("sRGB").tag(ColorSpaceKind.sRGB)
            }

            Picker("Gain map", selection: $model.request.gainMapChannels) {
                Text("Monochrome (compatible)").tag(ISOHDRGainMapChannels.monochrome)
                Text("RGB (maximum fidelity)").tag(ISOHDRGainMapChannels.rgb)
            }

            TextField("Filename suffix", text: $model.request.outputSuffix)
                .textFieldStyle(.roundedBorder)

            Divider()
            Text("Core Image develops each DNG using Apple's current RAW decoder, creates the SDR rendition, then stores the recoverable HDR difference as a gain map. Every output is reopened and rejected if ImageIO does not recognize its ISO gain map.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .utilityCardStyle()
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
