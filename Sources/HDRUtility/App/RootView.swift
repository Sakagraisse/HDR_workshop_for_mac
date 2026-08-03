import SwiftUI

public struct RootView: View {
    @State private var selection: AppSection? = .analyze

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("HDR Utility")
        } detail: {
            Group {
                switch selection ?? .analyze {
                case .analyze:
                    AnalyzeView()
                case .appleConvert:
                    AppleConvertView()
                case .ultraHDRConvert:
                    UltraHDRConvertView()
                case .fullApple:
                    FullAppleConvertView()
                case .proRAWBatch:
                    ProRAWBatchView()
                case .instagramConvert:
                    InstagramConvertView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    BuildBadge()
                }
            }
        }
    }
}

private struct BuildBadge: View {
    var body: some View {
        Text("MVP")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case analyze
    case appleConvert
    case ultraHDRConvert
    case fullApple
    case proRAWBatch
    case instagramConvert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .analyze:
            "Analyze"
        case .appleConvert:
            "Apple HDR"
        case .ultraHDRConvert:
            "Ultra HDR Android"
        case .fullApple:
            "ISOHDR"
        case .proRAWBatch:
            "ProRAW → HEIC (Batch)"
        case .instagramConvert:
            "Publication Instagram"
        }
    }

    var systemImage: String {
        switch self {
        case .analyze:
            "waveform.path.ecg.rectangle"
        case .appleConvert:
            "apple.logo"
        case .ultraHDRConvert:
            "iphone.gen3.radiowaves.left.and.right"
        case .fullApple:
            "rectangle.stack.badge.plus"
        case .proRAWBatch:
            "camera.badge.ellipsis"
        case .instagramConvert:
            "camera.aperture"
        }
    }
}
