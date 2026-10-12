import CoreImage
import SwiftUI

struct EditorScreen: View {
    let source: CIImage
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var saver: PhotoSaver
    @Environment(\.dismiss) private var dismiss
    @State private var preview: UIImage?
    @State private var zoom: CGFloat = 1
    @State private var showAdjust = true
    @State private var saving = false
    @State private var previewSource: CIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ZStack {
                    Color.black
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(zoom)
                            .gesture(zoomGesture)
                    } else {
                        ProgressView("正在准备")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .accessibilityLabel("编辑预览")

                if showAdjust {
                    AdjustPanel()
                }
                FilterStripView()
                HStack {
                    Button(zoom == 1 ? "查看" : "还原大小") {
                        zoom = 1
                    }
                    .font(.footnote)
                    Spacer()
                    Button(saving ? "正在保存" : "保存新照片") {
                        Task { await save() }
                    }
                    .disabled(saving)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.cream)
                    .foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
            .background(Theme.ink)
            .navigationTitle("编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(showAdjust ? "收起" : "调节") { showAdjust.toggle() }
                }
            }
            .task { await preparePreviewSource() }
            .onChange(of: app.recipe) { _, _ in
                Task { await renderPreview() }
            }
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(4, max(1, value))
            }
    }

    private func preparePreviewSource() async {
        let source = source
        let prepared: CIImage? = await Task.detached {
            guard let cg = FilterEngine.shared.previewCGImage(from: source, maxWidth: 1600) else { return nil }
            return CIImage(cgImage: cg)
        }.value
        previewSource = prepared
        await renderPreview()
    }

    private func renderPreview() async {
        guard let previewSource else { return }
        let recipe = app.recipe
        let image = await Task.detached {
            let filtered = FilterEngine.shared.apply(to: previewSource, recipe: recipe, grainPhase: 2, faces: .detect)
            return FilterEngine.shared.previewCGImage(from: filtered, maxWidth: 1600).map { UIImage(cgImage: $0) }
        }.value
        preview = image
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let source = source
        let recipe = app.recipe
        do {
            let url = try await Task.detached {
                let filtered = FilterEngine.shared.apply(
                    to: source,
                    recipe: recipe,
                    grainPhase: CGFloat.random(in: 0...800),
                    faces: .detect
                )
                return try FilterEngine.shared.writeTemporary(image: filtered)
            }.value
            saver.enqueueFile(url, kind: .photo)
        } catch {
            saver.show("这张没有保存下来，请再试一次。")
        }
    }
}
