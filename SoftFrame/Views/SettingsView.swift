import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPrivacy = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section("购买") {
                    LabeledContent("状态", value: purchases.isUnlocked ? "已解锁全部滤镜" : "免费四款")
                    Button("恢复购买") {
                        Task { await purchases.restore() }
                    }
                    if !purchases.isUnlocked {
                        Button("解锁全部滤镜") {
                            showPaywall = true
                        }
                    }
                    if let error = purchases.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                Section("画质") {
                    Text("拍摄的照片按取景范围、以相机可用的分辨率保存，优先使用 8 位 sRGB HEIF，失败时改为高质量 JPEG。从相册导入的照片保持原来的像素尺寸和方向。视频为 1080p。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("说明") {
                    Button("隐私政策") { showPrivacy = true }
                    Link("使用条款", destination: AppConfig.termsURL)
                    Button("意见反馈") { openFeedback() }
                }
                Section {
                    LabeledContent("版本", value: versionText)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                Button("完成") { dismiss() }
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacyPage()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func openFeedback() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let system = UIDevice.current.systemVersion
        let subject = "SoftFrame \(version) iOS \(system)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "SoftFrame"
        guard let url = URL(string: "mailto:\(AppConfig.feedbackEmail)?subject=\(subject)") else { return }
        UIApplication.shared.open(url)
    }
}

struct PrivacyPage: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(privacyText)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .navigationTitle("隐私政策")
            .toolbar {
                Button("关闭") { dismiss() }
            }
            .safeAreaInset(edge: .bottom) {
                Link("在浏览器中打开", destination: AppConfig.privacyPolicyURL)
                    .font(.footnote)
                    .padding()
            }
        }
    }

    private var privacyText: String {
        """
        SoftFrame 在这台手机上完成拍摄、肤色校正和调色。

        照片、视频和人脸检测结果不会上传。肤色处理结束后即释放，不会另存一份人脸数据。

        购买状态只通过 App Store 判断。本应用不要求账号，也不接入第三方统计。

        相机用于拍摄。麦克风只在你录制有声视频时使用，拒绝后仍可录无声视频。添加照片权限用于把成片写入系统相册，不修改原图。

        意见反馈会打开你的邮件应用，由你决定是否发送。
        """
    }
}
