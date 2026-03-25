import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppleConvertView: View {
    @Environment(AppState.self) private var appState
    @State private var model = AppleConvertViewModel()
    @State private var isListDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        sourcesCard
                        destinationCard
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    settingsCard
                        .frame(maxWidth: 420)
                }

                ConversionLogPanel(
                    job: model.lastJob,
                    emptyMessage: "Export one or more HDR files to see the Apple conversion result."
                )
                .frame(minHeight: 260)
            }
            .padding(24)
        }
        .navigationTitle("Apple Convert")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Apple Gain Map Export")
                    .font(.largeTitle.weight(.bold))
                Text("Drop image files or a folder, tune the export on the right, then write converted outputs to a separate destination.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Choose Files or Folder", action: chooseSources)
                    .buttonStyle(.borderedProminent)
                Button("Choose Export Folder", action: chooseExportFolder)
                    .buttonStyle(.bordered)
                Button("Reset", role: .destructive, action: model.reset)
                    .buttonStyle(.bordered)
                    .disabled(model.sourceURLs.isEmpty && model.request.outputFolder == nil)
            }
        }
    }

    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sources")
                    .font(.headline)
                Text("Drop one or more HDR image files, or a folder containing supported files. Existing ISO gain map files can be used directly as single inputs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = model.errorMessage {
                WarningBanner(message: errorMessage)
            }

            if model.sourceURLs.isEmpty {
                FileDropZone(
                    title: "Drop files or a folder",
                    subtitle: "Supports HEIC, JPEG, AVIF, TIFF and EXR sources.",
                    supportsMultiple: true,
                    onReceiveURLs: model.handleDrop(urls:)
                )
            }

            HStack(spacing: 10) {
                Text("\(model.sourceURLs.count) file\(model.sourceURLs.count == 1 ? "" : "s")")
                    .font(.headline)
                if let importedFolderName = model.importedFolderName {
                    SourceBadge(title: importedFolderName, tint: .secondary)
                }
                Spacer()
                if model.sourceURLs.isEmpty == false {
                    Button("Clear Sources", action: model.clearSources)
                        .buttonStyle(.bordered)
                }
            }

            if model.sourceURLs.isEmpty {
                ContentUnavailableView(
                    "No Sources Selected",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Add files or a folder to prepare the Apple export batch.")
                )
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.records) { record in
                            SourceRow(record: record)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 340)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isListDropTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    isListDropTargeted ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.12),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 8])
                                )
                        }
                }
                .onDrop(of: [UTType.fileURL], isTargeted: $isListDropTargeted, perform: handleDroppedProviders)
            }
        }
        .padding(18)
        .cardStyle()
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Destination")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Export Folder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(model.request.outputFolder?.path(percentEncoded: false) ?? "No export folder selected")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let warning = model.exportWarning {
                WarningBanner(message: warning)
            } else {
                Label("Choose a destination folder separate from the originals.", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Choose Export Folder", action: chooseExportFolder)
                    .buttonStyle(.bordered)

                Button(model.isRunning ? "Exporting..." : "Export Apple Gain Map") {
                    Task { @MainActor in
                        let job = await model.run()
                        appState.record(job: job)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canRun)
            }
        }
        .padding(18)
        .cardStyle()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                Text("High Priority")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                settingBlock(
                    title: "Export Mode",
                    help: """
                    Chooses the conversion target.

                    Recommended:
                    Apple Gain Map for Apple-friendly exports.
                    ISO Gain Map for a more interoperable gain map workflow.
                    """
                ) {
                    Picker("", selection: Binding(
                        get: { model.request.exportMode },
                        set: { model.setExportMode($0) }
                    )) {
                        ForEach(AppleExportMode.allCases) { mode in
                            Text(mode.displayLabel).tag(mode)
                        }
                    }
                    .labelsHidden()
                }

                settingBlock(
                    title: "Container",
                    help: """
                    Chooses the output container when the selected mode supports it.

                    Recommended:
                    HEIC for Apple Gain Map.
                    JPEG only when you specifically need a JPEG output and the mode allows it.
                    """
                ) {
                    Picker("", selection: $model.request.outputFormat) {
                        ForEach(model.request.exportMode.supportedFormats) { format in
                            Text(format.displayLabel).tag(format)
                        }
                    }
                    .labelsHidden()
                }

                settingBlock(
                    title: "Compression Quality",
                    help: """
                    Controls image compression quality.

                    Higher values preserve more detail but increase output size.
                    Recommended:
                    Around 0.90 to 0.95 for general use.
                    """
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.request.quality.formatted(.number.precision(.fractionLength(2))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $model.request.quality, in: 0.6...1.0)
                    }
                }

                settingBlock(
                    title: "Tone Map Ratio",
                    help: """
                    Controls how strongly the SDR base is compressed from the HDR source.

                    Lower values preserve more highlight detail.
                    Higher values create a stronger SDR roll-off.
                    Recommended:
                    Start around 1.8 and adjust only if highlights look too flat or too aggressive.
                    """
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.request.toneMapRatio.formatted(.number.precision(.fractionLength(2))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $model.request.toneMapRatio, in: 1.0...3.0)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("Recommended")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                settingBlock(
                    title: "Color Space",
                    help: """
                    Sets the output color space.

                    Recommended:
                    Display P3 for Apple-oriented workflows.
                    Rec.2020 only when you need a wider HDR-oriented target.
                    sRGB for maximum compatibility.
                    """
                ) {
                    Picker("", selection: $model.request.colorSpace) {
                        Text("Display P3").tag(ColorSpaceKind.displayP3)
                        Text("Rec.2020").tag(ColorSpaceKind.rec2020)
                        Text("sRGB").tag(ColorSpaceKind.sRGB)
                    }
                    .labelsHidden()
                }

                settingBlock(
                    title: "Bit Depth",
                    help: """
                    Sets the output bit depth.

                    Recommended:
                    10-bit for HDR-oriented outputs when supported.
                    8-bit for broader compatibility or SDR-focused outputs.
                    """
                ) {
                    Stepper(value: $model.request.bitDepth, in: 8...10, step: 2) {
                        Text("\(model.request.bitDepth)-bit")
                    }
                }

                settingBlock(
                    title: "Output Suffix",
                    help: """
                    Appends a suffix to generated filenames.

                    Recommended:
                    Keep a clear suffix such as apple, iso, pq or hlg to avoid confusion with the originals.
                    """
                ) {
                    TextField("apple", text: $model.request.outputNameSuffix)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("Advanced")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                settingBlock(
                    title: "Custom SDR Base",
                    help: """
                    Overrides the automatically generated SDR base with a file you provide.

                    Recommended:
                    Leave empty unless you already have a validated SDR fallback that should be paired with every export in this batch.
                    """
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.request.sdrBase?.lastPathComponent ?? "Automatic")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        HStack(spacing: 8) {
                            Button("Choose Base", action: chooseCustomSDRBase)
                                .buttonStyle(.bordered)
                            Button("Clear", action: { model.request.sdrBase = nil })
                                .buttonStyle(.bordered)
                                .disabled(model.request.sdrBase == nil)
                        }
                        if model.records.count > 1 {
                            Text("Custom SDR Base is only available when exporting a single source file.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(model.records.count > 1)
                }

                settingBlock(
                    title: "Apple Gain Map Scale",
                    help: """
                    Sets the Apple gain map scale value used with Apple Gain Map mode.

                    Higher values can reduce gain map size but may slightly reduce highlight fidelity.
                    Recommended:
                    Keep 1.0 unless you are optimizing file size and have visually validated the result.
                    """
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.request.appleGainMapScale.formatted(.number.precision(.fractionLength(2))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $model.request.appleGainMapScale, in: 1.0...2.0)
                    }
                    .disabled(model.request.exportMode != .appleGainMap)
                }

                settingBlock(
                    title: "Monochrome ISO Gain Map",
                    help: """
                    Uses a monochrome gain map for ISO gain map exports.

                    Recommended:
                    Leave disabled unless you specifically need a monochrome ISO gain map workflow.
                    """
                ) {
                    Toggle("Use monochrome gain map", isOn: $model.request.useMonochromeGainMap)
                        .disabled(model.request.exportMode != .isoGainMap)
                }
            }
        }
        .padding(18)
        .cardStyle()
    }

    @ViewBuilder
    private func settingBlock<Content: View>(title: String, help: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .help(help)
            content()
        }
    }

    private func chooseSources() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.title = "Choose Files or a Folder"
        panel.prompt = "Add Sources"

        guard panel.runModal() == .OK else { return }
        model.handleDrop(urls: panel.urls)
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
            model.handleDrop(urls: collected)
        }

        return true
    }

    private func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.resolvesAliases = true
        panel.title = "Choose Export Folder"
        panel.prompt = "Select Destination"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setOutputFolder(url)
    }

    private func chooseCustomSDRBase() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.title = "Choose SDR Base Image"
        panel.prompt = "Select Base"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.request.sdrBase = url
    }
}

private struct SourceRow: View {
    let record: HDRFileRecord

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SourceThumbnail(url: record.url)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text(record.specificationLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    SignalBadge(title: "SDR", isActive: record.hasEmbeddedSDR)
                    SignalBadge(title: "HDR", isActive: record.isHDRSignal)
                    SignalBadge(title: "Gain Map", isActive: record.gainMap != nil)
                }
                Text(record.url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SourceThumbnail: View {
    let url: URL

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.12))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        }
        .task(id: url) {
            image = NSImage(contentsOf: url)
        }
    }
}

private struct SignalBadge: View {
    let title: String
    let isActive: Bool

    var body: some View {
        Label(title, systemImage: isActive ? "checkmark.circle.fill" : "circle")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isActive ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isActive ? Color.green : Color.secondary).opacity(0.10), in: Capsule())
    }
}

private struct SourceBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint == .secondary ? .secondary : tint)
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

private struct WarningBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension View {
    func cardStyle() -> some View {
        background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private extension AppleExportMode {
    var displayLabel: String {
        switch self {
        case .appleGainMap:
            "Apple Gain Map"
        case .isoGainMap:
            "ISO Gain Map"
        case .sdrToneMapped:
            "SDR Tone-Mapped"
        case .hdrPQ:
            "HEIC HDR PQ"
        case .hdrHLG:
            "HEIC HDR HLG"
        }
    }

    var supportedFormats: [AppleOutputFormat] {
        switch self {
        case .appleGainMap, .isoGainMap, .sdrToneMapped:
            AppleOutputFormat.allCases
        case .hdrPQ, .hdrHLG:
            [.heic]
        }
    }
}

private extension AppleOutputFormat {
    var displayLabel: String {
        rawValue.uppercased()
    }
}

private extension HDRFileRecord {
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

    var isHDRSignal: Bool {
        switch hdrKind {
        case .appleGainMap, .isoGainMap, .ultraHDR, .pqHDR, .hlgHDR, .hdrUnknown:
            true
        case .sdr:
            false
        }
    }

    var hasEmbeddedSDR: Bool {
        gainMap != nil
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
