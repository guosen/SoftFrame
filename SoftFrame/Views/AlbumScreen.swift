import CoreImage
import PhotosUI
import SwiftUI

struct AlbumScreen: View {
    @EnvironmentObject private var app: AppModel
    @State private var singleItem: PhotosPickerItem?
    @State private var batchSelection: [PhotosPickerItem] = []
    @State private var editorImage: CIImage?
    @State private var batchItems: [PhotosPickerItem] = []
    @State private var showBatch = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("将使用「\(app.recipe.filter.name)」")
                    .font(.headline)
                Text("实况照片只会处理其中的静态画面，不保留实况。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("一次最多 20 张，多出来的选不了。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                PhotosPicker(selection: $singleItem, matching: .images) {
                    label("编辑一张照片", systemImage: "photo")
                }
                .onChange(of: singleItem) { _, item in
                    guard let item else { return }
                    Task { await loadSingle(item) }
                }

                PhotosPicker(selection: $batchSelection, maxSelectionCount: AppConfig.maxBatchCount, matching: .images) {
                    label("批量套用", systemImage: "square.stack.3d.up")
                }
                .onChange(of: batchSelection) { _, items in
                    guard !items.isEmpty else { return }
                    let chosen = Array(items.prefix(AppConfig.maxBatchCount))
                    batchSelection = []
                    batchItems = chosen
                    showBatch = true
                }

                FilterStripView()
                Spacer()
            }
            .padding(20)
            .navigationTitle("相册")
            .toolbar {
                Button {
                    app.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
            .fullScreenCover(isPresented: editorPresented) {
                if let editorImage {
                    EditorScreen(source: editorImage)
                }
            }
            .fullScreenCover(isPresented: $showBatch) {
                BatchScreen(items: batchItems, recipe: app.recipe)
            }
            .alert("这张照片读不了", isPresented: errorPresented) {
                Button("好", role: .cancel) { loadError = nil }
            } message: {
                Text(loadError ?? "请换一张。")
            }
        }
    }

    private var editorPresented: Binding<Bool> {
        Binding(
            get: { editorImage != nil },
            set: { show in
                if !show {
                    editorImage = nil
                    singleItem = nil
                }
            }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { loadError != nil },
            set: { show in
                if !show { loadError = nil }
            }
        )
    }

    private func label(_ title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func loadSingle(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ImageWriteError.unreadable
            }
            editorImage = try ImageDecoding.ciImage(from: data)
        } catch {
            loadError = "这张照片读不了，请换一张。"
            singleItem = nil
        }
    }
}
