import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        TabView {
            CameraScreen()
                .tabItem { Label("拍摄", systemImage: "camera") }
            AlbumScreen()
                .tabItem { Label("相册", systemImage: "photo.on.rectangle") }
        }
        .tint(Theme.cream)
        .sheet(isPresented: $app.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: paywallPresented) {
            PaywallView()
        }
        .onChange(of: app.purchases.isUnlocked) { _, _ in
            app.unlockChanged()
        }
    }

    private var paywallPresented: Binding<Bool> {
        Binding(
            get: { app.purchases.paywallFilterID != nil },
            set: { show in
                if !show {
                    app.purchases.paywallFilterID = nil
                }
            }
        )
    }
}

struct BannerOverlay: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.72))
                .clipShape(Capsule())
                .padding(.top, 8)
                .accessibilityLabel(text)
        }
    }
}
