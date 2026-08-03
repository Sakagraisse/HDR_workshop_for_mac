import AppKit
import SwiftUI

struct FullAppleConvertView: View {
    @Environment(AppState.self) private var appState
    @State private var model = FullAppleConvertViewModel()
    @State private var engineStatus: EngineStatus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red).padding().utilityCardStyle()
                }
                HStack(alignment: .top, spacing: 20) {
                    inputsCard
                    settingsCard.frame(width: 420)
                }
                ConversionLogPanel(
                    job: model.lastJob,
                    emptyMessage: "Create an ISOHDR JPEG or HEIC using Apple frameworks only."
                )
                .frame(minHeight: 240)
            }
            .padding(24)
        }
        .navigationTitle("ISOHDR")
        .task { engineStatus = await ConversionService().inspectEngine(.fullApple) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ISOHDR").font(.largeTitle.bold())
                Text("Create standards-based gain-map HDR in JPEG or HEIC with Foundation, Core Image and ImageIO only.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            EngineStatusBadge(status: engineStatus, fallbackName: "Apple frameworks")
        }
    }

    private var inputsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Mode", selection: $model.request.inputMode) {
                Text("HDR source(s)").tag(UltraHDRInputMode.hdrOnly)
                Text("HDR + custom SDR").tag(UltraHDRInputMode.hdrAndSDR)
            }
            .pickerStyle(.segmented)
            .disabled(model.request.hdrSources.count > 1)

            HStack {
                Text("\(model.request.hdrSources.count) HDR source\(model.request.hdrSources.count == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
                Button("Choose HDR Files") { model.addHDRSources(chooseFiles()) }
                Button("Clear") {
                    model.request.hdrSources = []
                    model.request.sdrBase = nil
                }
                .disabled(model.request.hdrSources.isEmpty)
            }

            ForEach(model.request.hdrSources, id: \.self) { url in
                Label(url.lastPathComponent, systemImage: "photo")
                    .lineLimit(1)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }

            if model.request.inputMode == .hdrAndSDR {
                HStack {
                    Text(model.request.sdrBase?.lastPathComponent ?? "No SDR fallback selected")
                    Spacer()
                    Button("Choose SDR") { model.request.sdrBase = chooseFiles(multiple: false).first }
                }
            }

            Divider()
            HStack {
                Text(model.request.outputFolder?.path(percentEncoded: false) ?? "No export folder")
                    .lineLimit(1)
                Spacer()
                Button("Choose Folder") { model.request.outputFolder = chooseFolder() }
            }

            Button(model.isRunning ? "Exporting…" : "Export ISOHDR " + model.request.outputFormat.fileExtension.uppercased()) {
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
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button("Compatible JPEG defaults") {
                    model.restoreCompatibleJPEGDefaults()
                }
                .controlSize(.small)
            }

            Picker("Output format", selection: $model.request.outputFormat) {
                ForEach(ISOHDROutputFormat.allCases) { format in
                    Text(format.label).tag(format)
                }
            }

            Picker("Gain map", selection: $model.request.gainMapChannels) {
                ForEach(ISOHDRGainMapChannels.allCases) { channels in
                    Text(channels.label).tag(channels)
                }
            }

            if model.request.outputFormat == .jpeg {
                Label("ISO 21496-1 + Ultra HDR v1 XMP/GContainer + MPF", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Label("HEIC Ultra HDR uses the native ISO 21496-1 auxiliary image", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Google JPEG XMP, GContainer and MPF do not apply to HEIC. Android support requires Android 16 or later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Runtime", value: "Apple frameworks only")
            Slider(value: $model.request.quality, in: 0.60...1.0, step: 0.01) {
                Text("Compression quality")
            }
            LabeledContent("Compression quality", value: model.request.quality.formatted(.percent.precision(.fractionLength(0))))
            Picker("Base color space", selection: $model.request.colorSpace) {
                Text("Display P3").tag(ColorSpaceKind.displayP3)
                Text("sRGB").tag(ColorSpaceKind.sRGB)
            }
            Text(model.request.inputMode == .hdrOnly
                 ? "Core Image tone-maps the HDR source to an SDR headroom of 1.0 before deriving the gain map."
                 : "The selected SDR rendition is used as the backward-compatible base image.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text(model.request.outputFormat == .jpeg
                 ? "JPEG exports are rejected unless ISO and Ultra HDR metadata, GContainer and MPF are valid, with no Apple legacy marker."
                 : "HEIC exports are rejected unless ImageIO recognizes an ISO gain map and no Apple legacy auxiliary image is present.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .utilityCardStyle()
    }

    private func chooseFiles(multiple: Bool = true) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = multiple
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
