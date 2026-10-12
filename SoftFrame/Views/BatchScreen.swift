import PhotosUI
import SwiftUI

struct BatchScreen: View {
    let items: [PhotosPickerItem]
    let recipe: FilterRecipe
    @EnvironmentObject private var saver: PhotoSaver
    @Environment(\.dismiss) private var dismiss
    @State private var finishedCount = 0
    @State private var success = 0
    @State private var failed = 0
    @State private var done = false
    @State private var cancelled = false
    @State private var runner: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("使用「\(recipe.filter.name)」")
                    .font(.headline)
                Text(done ? summary : "正在处理 \(finishedCount) / \(items.count)")
                    .font(.title3.monospacedDigit())
                if failed > 0 {
                    Text("失败 \(failed) 张")
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(finishedCount), total: Double(max(items.count, 1)))
                    .tint(Theme.cream)
                    .padding(.horizontal, 32)
                if done {
                    Button("关闭") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.cream)
                        .foregroundStyle(Theme.ink)
                } else {
                    Button("取消") {
                        runner?.cancel()
                        cancelled = true
                    }
                }
                Text("原图会留在相册里，这里只新增成片。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.ink)
            .navigationTitle("批量")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                let task = Task { await run() }
                runner = task
            }
        }
    }

    private var summary: String {
        if cancelled {
            return "已取消。保存了 \(success) 张，失败 \(failed) 张"
        }
        return "完成 \(success) 张，失败 \(failed) 张"
    }

    private func run() async {
        for item in items {
            if Task.isCancelled {
                break
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ImageWriteError.unreadable
                }
                let source = try ImageDecoding.ciImage(from: data)
                let recipe = recipe
                let url = try await Task.detached {
                    let filtered = FilterEngine.shared.apply(
                        to: source,
                        recipe: recipe,
                        grainPhase: CGFloat.random(in: 0...800),
                        faces: .detect
                    )
                    return try FilterEngine.shared.writeTemporary(image: filtered)
                }.value
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: url)
                    break
                }
                saver.enqueueFile(url, kind: .photo)
                success += 1
            } catch {
                if Task.isCancelled {
                    break
                }
                failed += 1
            }
            finishedCount += 1
        }
        done = true
    }
}
