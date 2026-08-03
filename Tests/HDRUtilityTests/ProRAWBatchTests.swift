import Foundation
import Testing
@testable import HDRUtilityKit

@Suite("ProRAW batch selection")
struct ProRAWBatchTests {
    @Test("Only DNG files are accepted and duplicates are removed")
    @MainActor
    func filtersSources() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let dng = folder.appending(path: "IMG_0001.DNG")
        let jpeg = folder.appending(path: "IMG_0001.jpg")
        FileManager.default.createFile(atPath: dng.path, contents: Data())
        FileManager.default.createFile(atPath: jpeg.path, contents: Data())

        let result = ProRAWBatchViewModel.expand([folder, dng])

        #expect(result == [dng.standardizedFileURL])
    }
}
