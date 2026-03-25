import SwiftUI

struct ConversionLogPanel: View {
    let job: ConversionJob?
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Execution Log")
                .font(.headline)

            if let job {
                LabeledContent("Engine", value: job.engine.rawValue)
                LabeledContent("Status", value: job.status.rawValue.capitalized)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(job.log.enumerated()), id: \.offset) { entry in
                            Text(entry.element)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Job Yet", systemImage: "terminal", description: Text(emptyMessage))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
