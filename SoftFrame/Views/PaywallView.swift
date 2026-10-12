import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var samples: [String: UIImage] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("一次购买，永久使用")
                        .font(.title2.weight(.semibold))
                    Text("包含之后更新加入的滤镜。肤色、批量和已有的四款免费滤镜不收费。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(FilterCatalog.paid) { filter in
                            VStack(alignment: .leading, spacing: 6) {
                                sample(for: filter)
                                Text(filter.name)
                                    .font(.headline)
                                Text(filter.blurb)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button {
                        Task { await purchases.purchase() }
                    } label: {
                        Text(buttonTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.cream)
                    .foregroundStyle(Theme.ink)
                    .disabled(purchases.isBusy || purchases.displayPrice.isEmpty)

                    Button("恢复购买") {
                        Task { await purchases.restore() }
                    }
                    .disabled(purchases.isBusy)

                    if let error = purchases.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    HStack(spacing: 16) {
                        Link("隐私政策", destination: AppConfig.privacyPolicyURL)
                        Link("使用条款", destination: AppConfig.termsURL)
                    }
                    .font(.footnote)
                }
                .padding(20)
            }
            .navigationTitle("解锁全部滤镜")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("关闭") { dismiss() }
            }
            .task { await loadSamples() }
            .onChange(of: purchases.isUnlocked) { _, unlocked in
                if unlocked { dismiss() }
            }
        }
    }

    private var buttonTitle: String {
        if purchases.isBusy { return "正在购买" }
        if purchases.displayPrice.isEmpty { return "正在获取价格" }
        return "购买 \(purchases.displayPrice)"
    }

    @ViewBuilder
    private func sample(for filter: FilterDefinition) -> some View {
        if let image = samples[filter.id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
                .frame(height: 160)
                .overlay { ProgressView() }
        }
    }

    private func loadSamples() async {
        let images: [String: UIImage] = await Task.detached {
            var output: [String: UIImage] = [:]
            for filter in FilterCatalog.paid {
                if let image = SampleScene.render(filter: filter, engine: .shared) {
                    output[filter.id] = image
                }
            }
            return output
        }.value
        samples = images
    }
}
