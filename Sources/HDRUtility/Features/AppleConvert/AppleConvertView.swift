import SwiftUI

struct AppleConvertView: View {
    @Environment(AppState.self) private var appState
    @State private var model = AppleConvertViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            FileDropZone(
                title: "Drop HDR source and optional SDR base",
                subtitle: "The first file becomes the HDR master. The second file, if present, is used as a custom SDR base.",
                supportsMultiple: true,
                onReceiveURLs: model.handleDrop(urls:)
            )

            HStack(alignment: .top, spacing: 24) {
                AppleConvertForm(model: model) {
                    Task { @MainActor in
                        let job = await model.run()
                        appState.record(job: job)
                    }
                }
                .frame(maxWidth: 420)

                ConversionLogPanel(job: model.lastJob, emptyMessage: "Run an Apple export to see the execution log.")
            }
        }
        .padding(24)
        .navigationTitle("Apple Convert")
    }
}

private struct AppleConvertForm: View {
    @Bindable var model: AppleConvertViewModel
    let onRun: () -> Void

    var body: some View {
        Form {
            Section("Inputs") {
                LabeledContent("HDR Source", value: model.request.hdrSource?.lastPathComponent ?? "Missing")
                LabeledContent("SDR Base", value: model.request.sdrBase?.lastPathComponent ?? "Automatic")
                LabeledContent("Output Folder", value: model.request.outputFolder?.lastPathComponent ?? "Missing")
            }

            Section("Output") {
                Picker("Format", selection: $model.request.outputFormat) {
                    ForEach(AppleOutputFormat.allCases) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }
                Picker("Color Space", selection: $model.request.colorSpace) {
                    Text("Display P3").tag(ColorSpaceKind.displayP3)
                    Text("Rec.2020").tag(ColorSpaceKind.rec2020)
                    Text("sRGB").tag(ColorSpaceKind.sRGB)
                }
                Stepper("Bit Depth: \(model.request.bitDepth)", value: $model.request.bitDepth, in: 8...10, step: 2)
            }

            Section("Tone Map") {
                LabeledContent("Quality", value: model.request.quality.formatted(.number.precision(.fractionLength(2))))
                Slider(value: $model.request.quality, in: 0.6...1.0)
                LabeledContent("Ratio", value: model.request.toneMapRatio.formatted(.number.precision(.fractionLength(2))))
                Slider(value: $model.request.toneMapRatio, in: 1.0...3.0)
            }

            Button("Run Apple Export", action: onRun)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canRun)
        }
    }
}
