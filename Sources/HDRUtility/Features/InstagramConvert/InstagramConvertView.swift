import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InstagramConvertView: View {
    @Environment(AppState.self) private var appState
    @State private var model = InstagramConvertViewModel()
    @State private var outputPreviewMode: PreviewDynamicRangeMode = .hdr

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let errorMessage = model.errorMessage {
                    InstagramErrorBanner(message: errorMessage)
                }

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        inputsCard
                        destinationCard
                        sourcePreviewCard
                        outputPreviewCard
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    settingsCard
                        .frame(width: 340)
                }

                ConversionLogPanel(job: model.lastJob, emptyMessage: "Run an Instagram export to inspect the libultrahdr output and logs.")
            }
            .padding(24)
        }
        .navigationTitle("Instagram Convert")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Build Instagram Ultra HDR")
                    .font(.largeTitle.weight(.bold))
                Text("Pair one HDR master with one SDR fallback, tune libultrahdr output, then inspect the final image in HDR or SDR mode.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Choose HDR", action: chooseHDRFile)
                    .buttonStyle(.borderedProminent)
                Button("Choose SDR", action: chooseSDRFile)
                    .buttonStyle(.bordered)
                Button("Clear", role: .destructive, action: model.clearSession)
                    .buttonStyle(.bordered)
                    .disabled(model.request.hdrSource == nil && model.request.sdrBase == nil)
            }
        }
    }

    private var inputsCard: some View {
        HStack(alignment: .top, spacing: 18) {
            InstagramInputDropCard(
                title: "HDR Source",
                subtitle: "Drop the HDR master used for highlights and tone recovery.",
                role: "HDR",
                tint: .orange,
                url: model.request.hdrSource,
                isFilled: model.request.hdrSource != nil,
                onDrop: model.setHDRSource,
                onChoose: chooseHDRFile,
                onClear: model.clearHDRSource
            )

            InstagramInputDropCard(
                title: "SDR Base",
                subtitle: "Drop the SDR fallback that Instagram-compatible viewers will use.",
                role: "SDR",
                tint: .blue,
                url: model.request.sdrBase,
                isFilled: model.request.sdrBase != nil,
                onDrop: model.setSDRSource,
                onChoose: chooseSDRFile,
                onClear: model.clearSDRSource
            )
        }
        .padding(18)
        .cardStyle()
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export Destination")
                        .font(.headline)
                    Text("The final Ultra HDR JPEG will be written here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Choose Folder", action: chooseOutputFolder)
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(model.request.outputFolder?.path(percentEncoded: false) ?? "No export folder selected")
                    .foregroundStyle(model.request.outputFolder == nil ? .secondary : .primary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }

            if let outputName = model.outputFileName {
                Text("Output file: \(outputName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .cardStyle()
    }

    private var sourcePreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HDR Source Preview")
                        .font(.headline)
                    Text("Displayed with an HDR-capable image view when possible.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.request.hdrSource != nil {
                    TagBadge(title: "HDR", tint: .orange)
                }
            }

            InstagramDynamicRangePreview(
                url: model.request.hdrSource,
                preferredDynamicRange: .high,
                emptyTitle: "No HDR Source",
                emptyDescription: "Choose or drop the HDR input to preview it here."
            )
            .frame(height: 280)
        }
        .padding(18)
        .cardStyle()
    }

    private var outputPreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Final Output Viewer")
                        .font(.headline)
                    Text("Switch between HDR and SDR display intent to inspect the exported image.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Preview Mode", selection: $outputPreviewMode) {
                    ForEach(PreviewDynamicRangeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .disabled(model.lastJob?.outputURL == nil)
            }

            InstagramDynamicRangePreview(
                url: model.lastJob?.outputURL,
                preferredDynamicRange: outputPreviewMode.dynamicRange,
                emptyTitle: "No Output Yet",
                emptyDescription: "Run the Instagram export to inspect the generated file here."
            )
            .frame(height: 300)
        }
        .padding(18)
        .cardStyle()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("libultrahdr Settings")
                    .font(.headline)
                Text("Only the options currently supported by the bundled bridge are exposed here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            InstagramSettingBlock(
                title: "Compression Quality",
                help: """
                Controls JPEG compression quality in libultrahdr.

                Recommended: keep between 0.88 and 0.95 for production exports.
                """
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.request.quality.formatted(.number.precision(.fractionLength(2))))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(model.request.quality * 100))")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.request.quality, in: 0.6...1.0)
                }
            }

            InstagramSettingBlock(
                title: "ISO Gain Map Metadata",
                help: """
                Writes ISO 21496 gain map metadata in the output when enabled.

                Recommended: leave enabled unless you are testing compatibility edge cases.
                """
            ) {
                Toggle("Include ISO 21496 metadata", isOn: $model.request.includeISOGainMapMetadata)
                    .toggleStyle(.switch)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Readiness")
                    .font(.headline)

                InstagramStatusRow(
                    title: model.request.hdrSource == nil ? "Missing HDR source" : "HDR source ready",
                    isReady: model.request.hdrSource != nil
                )
                InstagramStatusRow(
                    title: model.request.sdrBase == nil ? "Missing SDR base" : "SDR base ready",
                    isReady: model.request.sdrBase != nil
                )
                InstagramStatusRow(
                    title: model.request.outputFolder == nil ? "Missing export folder" : "Export folder ready",
                    isReady: model.request.outputFolder != nil
                )
            }

            Button("Run Instagram Export", action: runExport)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canRun)
        }
        .padding(18)
        .cardStyle()
    }

    private func chooseHDRFile() {
        if let url = selectSingleImageFile(title: "Choose HDR Source") {
            model.setHDRSource(url)
        }
    }

    private func chooseSDRFile() {
        if let url = selectSingleImageFile(title: "Choose SDR Base") {
            model.setSDRSource(url)
        }
    }

    private func chooseOutputFolder() {
        if let url = selectFolder(title: "Choose Output Folder") {
            model.request.outputFolder = url
        }
    }

    private func runExport() {
        Task { @MainActor in
            let job = await model.run()
            appState.record(job: job)
        }
    }

    private func selectSingleImageFile(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.urls.first : nil
    }

    private func selectFolder(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.urls.first : nil
    }
}

private struct InstagramInputDropCard: View {
    let title: String
    let subtitle: String
    let role: String
    let tint: Color
    let url: URL?
    let isFilled: Bool
    let onDrop: (URL) -> Void
    let onChoose: () -> Void
    let onClear: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TagBadge(title: role, tint: tint)
            }

            VStack(spacing: 10) {
                Image(systemName: isFilled ? "checkmark.circle.fill" : "square.and.arrow.down")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(isFilled ? tint : .secondary)

                Text(url?.lastPathComponent ?? "Drop one image here")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(isFilled ? "Replace by dropping another file or using Choose." : "One file only. HDR and SDR are selected independently.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 190)
            .background(background)
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: handleDrop)

            HStack(spacing: 10) {
                Button("Choose", action: onChoose)
                    .buttonStyle(.bordered)
                Button("Clear", role: .destructive, action: onClear)
                    .buttonStyle(.bordered)
                    .disabled(url == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(isTargeted ? tint.opacity(0.14) : Color.secondary.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isTargeted ? tint.opacity(0.8) : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
            }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let droppedURL = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            DispatchQueue.main.async {
                onDrop(droppedURL)
            }
        }

        return true
    }
}

private struct InstagramSettingBlock<Content: View>: View {
    let title: String
    let help: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .help(help)
            content
        }
    }
}

private struct InstagramStatusRow: View {
    let title: String
    let isReady: Bool

    var body: some View {
        Label(title, systemImage: isReady ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(isReady ? .green : .secondary)
    }
}

private struct InstagramDynamicRangePreview: NSViewRepresentable {
    let url: URL?
    let preferredDynamicRange: NSImage.DynamicRange
    let emptyTitle: String
    let emptyDescription: String

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 20
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter

        let placeholder = NSTextField(wrappingLabelWithString: "")
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.alignment = .center
        placeholder.isBezeled = false
        placeholder.isEditable = false
        placeholder.drawsBackground = false
        placeholder.textColor = .secondaryLabelColor
        placeholder.maximumNumberOfLines = 3

        container.addSubview(imageView)
        container.addSubview(placeholder)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
            placeholder.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 32),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -32)
        ])

        context.coordinator.imageView = imageView
        context.coordinator.placeholder = placeholder
        update(container: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        update(container: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func update(container: NSView) {
        guard let imageView = container.subviews.compactMap({ $0 as? NSImageView }).first,
              let placeholder = container.subviews.compactMap({ $0 as? NSTextField }).first else {
            return
        }

        imageView.preferredImageDynamicRange = preferredDynamicRange

        if let url, let image = NSImage(contentsOf: url) {
            imageView.image = image
            placeholder.stringValue = ""
            placeholder.isHidden = true
        } else {
            imageView.image = nil
            placeholder.stringValue = "\(emptyTitle)\n\(emptyDescription)"
            placeholder.isHidden = false
        }
    }

    final class Coordinator {
        var imageView: NSImageView?
        var placeholder: NSTextField?
    }
}

private struct InstagramErrorBanner: View {
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

private enum PreviewDynamicRangeMode: String, CaseIterable, Identifiable {
    case hdr
    case sdr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hdr:
            "HDR"
        case .sdr:
            "SDR"
        }
    }

    var dynamicRange: NSImage.DynamicRange {
        switch self {
        case .hdr:
            .high
        case .sdr:
            .standard
        }
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
            .background(tint.opacity(0.14), in: Capsule())
    }
}

private extension View {
    func cardStyle() -> some View {
        background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
