import SwiftUI
import UniformTypeIdentifiers

struct FileDropZone: View {
    let title: String
    let subtitle: String
    let supportsMultiple: Bool
    let onReceiveURLs: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 28, weight: .medium))
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isTargeted ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(isTargeted ? .blue : .secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [8, 8]))
                }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            loadURLs(from: providers)
        }
    }

    private func loadURLs(from providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let collector = FileDropURLCollector()

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
            let urls = supportsMultiple ? collected : Array(collected.prefix(1))
            onReceiveURLs(urls)
        }

        return true
    }
}

private final class FileDropURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}
