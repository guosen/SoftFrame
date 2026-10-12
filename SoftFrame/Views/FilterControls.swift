import SwiftUI

struct FilterStripView: View {
    @EnvironmentObject private var app: AppModel
    var disabled: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterCatalog.all) { filter in
                    let selected = app.recipe.filterID == filter.id
                    let locked = filter.isPaid && !app.purchases.isUnlocked
                    Button {
                        app.selectFilter(filter.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(filter.name)
                                    .font(.subheadline.weight(.semibold))
                                if locked {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                }
                            }
                            if selected {
                                Text(filter.blurb)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selected ? Theme.cream.opacity(0.22) : Color.white.opacity(0.08))
                        .foregroundStyle(selected ? Theme.cream : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(disabled)
                    .accessibilityLabel(locked ? "\(filter.name)，未解锁" : filter.name)
                    .accessibilityHint(filter.blurb)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct AdjustPanel: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            slider(title: "强度", value: app.recipe.intensity, range: 0...100, text: "\(Int(app.recipe.intensity))") { newValue in
                var recipe = app.recipe
                recipe.intensity = newValue
                app.update(recipe)
            }
            slider(title: "颗粒", value: app.recipe.grain, range: 0...100, text: "\(Int(app.recipe.grain))") { newValue in
                var recipe = app.recipe
                recipe.grain = newValue
                app.update(recipe)
            }
            slider(title: "冷暖", value: app.recipe.warmth, range: -50...50, text: signed(app.recipe.warmth)) { newValue in
                var recipe = app.recipe
                recipe.warmth = newValue
                app.update(recipe)
            }
            slider(title: "肤色", value: app.recipe.skin, range: 0...30, text: "\(Int(app.recipe.skin))") { newValue in
                var recipe = app.recipe
                recipe.skin = newValue
                app.update(recipe)
            }
            Button("恢复推荐") {
                app.restoreRecommended()
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.cream)
            .accessibilityHint("只重置当前滤镜")
        }
        .padding(14)
        .background(.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func signed(_ value: Double) -> String {
        let number = Int(value)
        return number > 0 ? "+\(number)" : "\(number)"
    }

    private func slider(title: String, value: Double, range: ClosedRange<Double>, text: String, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(text).monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))
            Slider(value: Binding(get: { value }, set: onChange), in: range)
                .tint(Theme.cream)
                .accessibilityLabel(title)
        }
    }
}
