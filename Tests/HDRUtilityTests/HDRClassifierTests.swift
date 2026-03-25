import Testing
@testable import HDRUtilityKit

struct HDRClassifierTests {
    @Test func detectsUltraHDRMarkers() {
        let classifier = HDRClassifier()
        let metadata = [
            MetadataEntry(key: "XMP.hdrgm:Version", value: "1.0"),
            MetadataEntry(key: "XMP.Container", value: "GContainer")
        ]

        let result = classifier.classify(
            container: .jpeg,
            bitDepth: 8,
            colorSpace: .displayP3,
            metadata: metadata
        )

        #expect(result.1 == .ultraHDR)
        #expect(result.2?.kind == .ultraHDR)
        #expect(result.4.instagramReady)
    }

    @Test func flagsSuspiciousHDRInSRGB() {
        let classifier = HDRClassifier()
        let metadata = [
            MetadataEntry(key: "Transfer", value: "PQ")
        ]

        let result = classifier.classify(
            container: .jpeg,
            bitDepth: 10,
            colorSpace: .sRGB,
            metadata: metadata
        )

        #expect(result.1 == .pqHDR)
        #expect(result.3.contains(where: { $0.severity == .warning }))
    }
}
