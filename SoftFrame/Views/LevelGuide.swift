import CoreMotion
import SwiftUI

@MainActor
final class LevelMonitor: ObservableObject {
    @Published var enabled = false
    @Published var roll: Double = 0
    private let motion = CMMotionManager()

    func setEnabled(_ on: Bool) {
        enabled = on
        guard motion.isDeviceMotionAvailable else { return }
        if on {
            motion.deviceMotionUpdateInterval = 0.05
            motion.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                self?.roll = motion?.attitude.roll ?? 0
            }
        } else {
            motion.stopDeviceMotionUpdates()
            roll = 0
        }
    }
}

struct LevelGuide: View {
    var roll: Double

    var body: some View {
        let level = abs(roll) < 0.03
        Rectangle()
            .fill(level ? Color(red: 0.96, green: 0.86, blue: 0.75) : Color.white.opacity(0.75))
            .frame(width: 140, height: 1)
            .rotationEffect(.radians(-roll))
            .shadow(radius: 2)
            .accessibilityLabel(level ? "已经水平" : "尚未水平")
    }
}

enum Theme {
    static let cream = Color(red: 0.96, green: 0.86, blue: 0.75)
    static let ink = Color(red: 0.08, green: 0.07, blue: 0.06)
}

func openSystemSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}
