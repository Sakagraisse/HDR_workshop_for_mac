import Foundation

@Observable
final class AnalyzeViewModel {
    var records: [HDRFileRecord] = []
    var selection: Set<HDRFileRecord.ID> = []
    var errorMessage: String?

    private let analyzer = ImageAnalyzer()

    var selectedRecord: HDRFileRecord? {
        guard let id = selection.first else { return nil }
        return records.first(where: { $0.id == id })
    }

    func analyzeFiles(urls: [URL]) {
        do {
            let newRecords = try urls.map(analyzer.analyze(url:))
            records = newRecords
            selection = []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
