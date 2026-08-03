import SwiftUI

public struct ThirdPartyLicensesView: View {
    public init() {}

    public var body: some View {
        TabView {
            LicenseTextView(
                title: "toGainMapHDR",
                resourceName: "toGainMapHDR-LICENSE",
                resourceExtension: "txt"
            )
            .tabItem { Text("toGainMapHDR") }

            LicenseTextView(
                title: "libultrahdr",
                resourceName: "libultrahdr-NOTICE",
                resourceExtension: "txt"
            )
            .tabItem { Text("libultrahdr") }
        }
        .frame(width: 720, height: 520)
        .padding()
    }
}

private struct LicenseTextView: View {
    let title: String
    let resourceName: String
    let resourceExtension: String

    private var text: String {
        let candidates = [
            Bundle.module.url(forResource: resourceName, withExtension: resourceExtension, subdirectory: "ThirdPartyLicenses"),
            Bundle.module.url(forResource: resourceName, withExtension: resourceExtension)
        ]
        guard let url = candidates.compactMap({ $0 }).first,
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "License resource unavailable."
        }
        return contents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
