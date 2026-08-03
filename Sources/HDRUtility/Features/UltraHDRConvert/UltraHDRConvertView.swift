import AppKit
import SwiftUI

struct UltraHDRConvertView: View {
    @Environment(AppState.self) private var appState
    @State private var model = UltraHDRConvertViewModel()
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
                ConversionLogPanel(job: model.lastJob, emptyMessage: "Export HDR sources as Android-compatible Ultra HDR JPEG files.")
                    .frame(minHeight: 240)
            }
            .padding(24)
        }
        .navigationTitle("Ultra HDR Android")
        .task {
            engineStatus = await ConversionService().inspectEngine(.libUltraHDR)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ultra HDR for Android").font(.largeTitle.bold())
                Text("Convert HDR masters to backward-compatible JPEGs, automatically or with your own SDR rendition.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            EngineStatusBadge(status: engineStatus, fallbackName: "libultrahdr")
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
                Button("Choose HDR Files") {
                    model.addHDRSources(chooseFiles())
                }
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
                    Button("Choose SDR") {
                        model.request.sdrBase = chooseFiles(multiple: false).first
                    }
                }
            }

            Divider()
            HStack {
                Text(model.request.outputFolder?.path(percentEncoded: false) ?? "No export folder")
                    .lineLimit(1)
                Spacer()
                Button("Choose Folder") { model.request.outputFolder = chooseFolder() }
            }

            Button(model.isRunning ? "Exporting…" : "Export Ultra HDR") {
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
            LabeledContent("Output", value: "JPEG Ultra HDR")
            Stepper("Base quality: \(model.request.baseQuality)", value: $model.request.baseQuality, in: 60...100)
            Stepper("Gain map quality: \(model.request.gainMapQuality)", value: $model.request.gainMapQuality, in: 60...100)
            Picker("Preset", selection: $model.request.preset) {
                Text("Best quality").tag(UltraHDRPreset.bestQuality)
                Text("Realtime").tag(UltraHDRPreset.realtime)
            }
            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("RGB gain map", isOn: $model.request.multiChannel)
                    Stepper("Gain map scale: 1/\(model.request.gainMapScale)", value: $model.request.gainMapScale, in: 1...8)
                    Picker("Color space", selection: $model.request.colorSpace) {
                        Text("Display P3").tag(ColorSpaceKind.displayP3)
                        Text("sRGB").tag(ColorSpaceKind.sRGB)
                        Text("Rec.2020").tag(ColorSpaceKind.rec2020)
                    }
                }
                .padding(.top, 10)
            }
            Text(model.request.inputMode == .hdrOnly
                 ? "The SDR fallback is generated by libultrahdr."
                 : "The selected SDR file is preserved as the creative fallback.")
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
