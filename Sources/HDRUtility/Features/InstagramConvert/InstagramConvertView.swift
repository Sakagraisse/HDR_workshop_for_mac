import SwiftUI

struct InstagramConvertView: View {
    @Environment(AppState.self) private var appState
    @State private var model = InstagramConvertViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            FileDropZone(
                title: "Drop HDR and SDR files",
                subtitle: "Use a matched HDR master and SDR fallback to generate a JPEG gain map workflow.",
                supportsMultiple: true,
                onReceiveURLs: model.handleDrop(urls:)
            )

            HStack(alignment: .top, spacing: 24) {
                InstagramConvertForm(model: model) {
                    Task { @MainActor in
                        let job = await model.run()
                        appState.record(job: job)
                    }
                }
                .frame(maxWidth: 420)

                VStack(alignment: .leading, spacing: 16) {
                    CompatibilityPreview(model: model)
                    ConversionLogPanel(job: model.lastJob, emptyMessage: "Run an Instagram export to see the execution log.")
                }
            }
        }
        .padding(24)
        .navigationTitle("Instagram Convert")
    }
}

private struct InstagramConvertForm: View {
    @Bindable var model: InstagramConvertViewModel
    let onRun: () -> Void

    var body: some View {
        Form {
            Section("Inputs") {
                LabeledContent("HDR Source", value: model.request.hdrSource?.lastPathComponent ?? "Missing")
                LabeledContent("SDR Base", value: model.request.sdrBase?.lastPathComponent ?? "Missing")
                LabeledContent("Output Folder", value: model.request.outputFolder?.lastPathComponent ?? "Missing")
            }

            Section("Metadata") {
                Toggle("Include ISO 21496 metadata", isOn: $model.request.includeISOGainMapMetadata)
                LabeledContent("Quality", value: model.request.quality.formatted(.number.precision(.fractionLength(2))))
                Slider(value: $model.request.quality, in: 0.6...1.0)
            }

            Button("Run Instagram Export", action: onRun)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canRun)
        }
    }
}

private struct CompatibilityPreview: View {
    let model: InstagramConvertViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compatibility Checklist")
                .font(.headline)
            Label(model.request.hdrSource == nil ? "Missing HDR source" : "HDR source loaded", systemImage: model.request.hdrSource == nil ? "xmark.circle" : "checkmark.circle")
            Label(model.request.sdrBase == nil ? "Missing SDR fallback" : "SDR fallback loaded", systemImage: model.request.sdrBase == nil ? "xmark.circle" : "checkmark.circle")
            Label(model.request.includeISOGainMapMetadata ? "ISO metadata enabled" : "ISO metadata disabled", systemImage: model.request.includeISOGainMapMetadata ? "checkmark.circle" : "minus.circle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
