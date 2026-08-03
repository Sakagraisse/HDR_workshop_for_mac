import SwiftUI

struct EngineStatusBadge: View {
    let status: EngineStatus?
    let fallbackName: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(status?.isHealthy == true ? Color.green : status == nil ? Color.secondary : Color.red)
                .frame(width: 8, height: 8)
            Text(status.map { "\($0.displayName) \($0.version)" } ?? "\(fallbackName) checking…")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
        .help(status?.message ?? "Checking embedded engine.")
    }
}
