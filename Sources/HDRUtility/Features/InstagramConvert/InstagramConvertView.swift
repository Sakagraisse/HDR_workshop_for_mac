import AppKit
import SwiftUI

struct InstagramConvertView: View {
    @Environment(AppState.self) private var appState
    @State private var model = InstagramConvertViewModel()
    @State private var engineStatus: EngineStatus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let error = model.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }

                HStack(alignment: .top, spacing: 20) {
                    inputCard
                    settingsCard.frame(width: 420)
                }

                ConversionLogPanel(job: model.lastJob, emptyMessage: "Create an Instagram-ready JPEG and compliance report.")
                    .frame(minHeight: 240)
            }
            .padding(24)
        }
        .navigationTitle("Publication Instagram")
        .task {
            engineStatus = await ConversionService().inspectEngine(.libUltraHDR)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Instagram HDR Package")
                    .font(.largeTitle.bold())
                Text("Preserve a controlled SDR fallback while preparing a verified 1080 px JPEG gain-map package.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            EngineStatusBadge(status: engineStatus, fallbackName: "libultrahdr")
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Input", selection: $model.request.inputMode) {
                Text("Existing Gain Map").tag(InstagramInputMode.existingGainMap)
                Text("HDR + SDR Pair").tag(InstagramInputMode.hdrAndSDR)
            }
            .pickerStyle(.segmented)

            switch model.request.inputMode {
            case .existingGainMap:
                fileLine("Gain-map image", model.request.existingGainMap) {
                    if let url = chooseFile(title: "Choose a Gain-map Image") { model.setExisting(url) }
                }
                Text("JPEG, HEIC or AVIF with an embedded gain map.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .hdrAndSDR:
                fileLine("HDR final", model.request.hdrSource) {
                    model.setPair(hdr: chooseFile(title: "Choose HDR Final"), sdr: nil)
                }
                fileLine("SDR final", model.request.sdrBase) {
                    model.setPair(hdr: nil, sdr: chooseFile(title: "Choose SDR Final"))
                }
                Text("Both renditions must have identical dimensions and framing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            fileLine("Export folder", model.request.outputFolder) {
                model.request.outputFolder = chooseFolder()
            }

            Label("No automatic crop. Ratios outside 1.91:1–3:4 are rejected.", systemImage: "crop")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(model.isRunning ? "Packaging…" : "Create Instagram Package") {
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
            Text("Settings").font(.headline)

            if model.request.inputMode == .existingGainMap {
                Picker("Existing file policy", selection: $model.request.existingPolicy) {
                    Text("Automatic").tag(ExistingGainMapPolicy.automatic)
                    Text("Lossless").tag(ExistingGainMapPolicy.lossless)
                    Text("Normalized").tag(ExistingGainMapPolicy.normalized)
                }
            }

            LabeledContent("Maximum width", value: "1080 px")
            LabeledContent("File target", value: "< 8 MB")
            Stepper("Base quality: \(model.request.baseQuality)", value: $model.request.baseQuality, in: 85...100)
            Stepper("Gain map quality: \(model.request.gainMapQuality)", value: $model.request.gainMapQuality, in: 85...100)

            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("RGB gain map", isOn: $model.request.multiChannel)
                    Stepper("Gain map scale: 1/\(model.request.gainMapScale)", value: $model.request.gainMapScale, in: 1...4)
                    Picker("Color space", selection: $model.request.colorSpace) {
                        Text("Display P3").tag(ColorSpaceKind.displayP3)
                        Text("sRGB").tag(ColorSpaceKind.sRGB)
                        Text("Rec.2020").tag(ColorSpaceKind.rec2020)
                    }
                }
                .padding(.top, 10)
            }

            Text("Output: one JPEG plus a Markdown verification report.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .utilityCardStyle()
    }

    private func fileLine(_ title: String, _ url: URL?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                Text(url?.lastPathComponent ?? "Not selected")
                    .lineLimit(1)
                Spacer()
                Button("Choose", action: action)
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func chooseFile(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
