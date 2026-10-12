import Foundation

enum AppConfig {
    static let productID = "softframe.unlock"
    static let bundleDisplayName = "SoftFrame"
    static let feedbackEmail = "feedback@softframe.app"
    static let privacyPolicyURL = URL(string: "https://softframe.app/privacy")!
    static let termsURL = URL(string: "https://softframe.app/terms")!
    static let maxBatchCount = 20
    static let maxInFlightCaptures = 5
    static let maxVideoSeconds: Double = 60
    static let minVideoSeconds: Double = 1
    static let reviewSaveThreshold = 10
}
