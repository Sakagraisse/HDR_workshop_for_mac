import HDRUtilityKit
import SwiftUI

@main
struct HDRUtilityApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowResizability(.contentSize)

        Settings {
            ThirdPartyLicensesView()
        }
    }
}
