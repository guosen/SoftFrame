import Foundation
import CoreGraphics

struct ColorGrade {
    var saturation: CGFloat
    var contrast: CGFloat
    var brightness: CGFloat
    /// 0 保持阴影，越大越抬亮。
    var shadowAmount: CGFloat
    /// 1 保持高光，越小越压暗。
    var highlightAmount: CGFloat
    var redGain: CGFloat
    var greenGain: CGFloat
    var blueGain: CGFloat
    var tint: CGFloat
}

struct FilterDefinition: Identifiable, Equatable {
    let id: String
    let name: String
    let blurb: String
    let isPaid: Bool
    let defaultGrain: Double
    let defaultWarmth: Double
    let defaultSkin: Double
    let grade: ColorGrade
}

enum FilterCatalog {
    static let cream = FilterDefinition(
        id: "cream",
        name: "奶油",
        blurb: "室内柔光自拍",
        isPaid: false,
        defaultGrain: 15,
        defaultWarmth: 8,
        defaultSkin: 12,
        grade: ColorGrade(saturation: 0.86, contrast: 0.92, brightness: 0.025, shadowAmount: 0.34, highlightAmount: 0.88, redGain: 1.03, greenGain: 1.0, blueGain: 0.97, tint: 2)
    )

    static let haze = FilterDefinition(
        id: "haze",
        name: "薄雾",
        blurb: "阴天降低反差",
        isPaid: false,
        defaultGrain: 20,
        defaultWarmth: 0,
        defaultSkin: 12,
        grade: ColorGrade(saturation: 0.78, contrast: 0.84, brightness: 0.04, shadowAmount: 0.48, highlightAmount: 0.96, redGain: 0.99, greenGain: 1.0, blueGain: 1.02, tint: 0)
    )

    static let porch = FilterDefinition(
        id: "porch",
        name: "门廊",
        blurb: "探店暖色灯光",
        isPaid: false,
        defaultGrain: 10,
        defaultWarmth: 18,
        defaultSkin: 12,
        grade: ColorGrade(saturation: 0.94, contrast: 0.98, brightness: 0.02, shadowAmount: 0.28, highlightAmount: 0.9, redGain: 1.06, greenGain: 1.0, blueGain: 0.92, tint: 4)
    )

    static let plate = FilterDefinition(
        id: "plate",
        name: "餐盘",
        blurb: "食物颜色温暖",
        isPaid: false,
        defaultGrain: 8,
        defaultWarmth: 12,
        defaultSkin: 0,
        grade: ColorGrade(saturation: 1.08, contrast: 1.02, brightness: 0.015, shadowAmount: 0.18, highlightAmount: 0.94, redGain: 1.05, greenGain: 1.02, blueGain: 0.9, tint: 3)
    )

    static let dusk = FilterDefinition(
        id: "dusk",
        name: "薄暮",
        blurb: "夜景压低高光",
        isPaid: true,
        defaultGrain: 18,
        defaultWarmth: -6,
        defaultSkin: 10,
        grade: ColorGrade(saturation: 0.82, contrast: 1.06, brightness: -0.05, shadowAmount: 0.12, highlightAmount: 0.72, redGain: 0.96, greenGain: 0.98, blueGain: 1.05, tint: -2)
    )

    static let mint = FilterDefinition(
        id: "mint",
        name: "清薄荷",
        blurb: "白天冷调街拍",
        isPaid: true,
        defaultGrain: 12,
        defaultWarmth: -14,
        defaultSkin: 10,
        grade: ColorGrade(saturation: 0.9, contrast: 1.04, brightness: 0.01, shadowAmount: 0.16, highlightAmount: 0.9, redGain: 0.94, greenGain: 1.03, blueGain: 1.05, tint: -6)
    )

    static let reed = FilterDefinition(
        id: "reed",
        name: "青苇",
        blurb: "轻微胶片绿色",
        isPaid: true,
        defaultGrain: 25,
        defaultWarmth: -4,
        defaultSkin: 8,
        grade: ColorGrade(saturation: 0.76, contrast: 0.96, brightness: 0.0, shadowAmount: 0.22, highlightAmount: 0.86, redGain: 0.95, greenGain: 1.07, blueGain: 0.98, tint: 1)
    )

    static let bulb = FilterDefinition(
        id: "bulb",
        name: "直闪",
        blurb: "旧手机直闪",
        isPaid: true,
        defaultGrain: 22,
        defaultWarmth: 6,
        defaultSkin: 14,
        grade: ColorGrade(saturation: 0.88, contrast: 1.12, brightness: 0.045, shadowAmount: 0.2, highlightAmount: 1.02, redGain: 1.05, greenGain: 0.99, blueGain: 1.02, tint: 1)
    )

    static let all: [FilterDefinition] = [cream, haze, porch, plate, dusk, mint, reed, bulb]
    static let free: [FilterDefinition] = all.filter { !$0.isPaid }
    static let paid: [FilterDefinition] = all.filter(\.isPaid)

    static func definition(id: String) -> FilterDefinition {
        all.first { $0.id == id } ?? cream
    }
}
