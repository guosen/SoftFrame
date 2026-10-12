import SwiftUI

@main
struct SoftFrameApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.purchases)
                .environmentObject(app.saver)
                .preferredColorScheme(.dark)
                .task { await app.start() }
        }
    }
}
