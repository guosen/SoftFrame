import CoreImage
import UIKit

enum SampleScene {
    /// 购买页用的本地样张，走真实滤镜，不使用外部图片。
    static func render(filter: FilterDefinition, engine: FilterEngine) -> UIImage? {
        let size = CGSize(width: 360, height: 480)
        let background = CIFilter.linearGradient()
        background.point0 = CGPoint(x: 0, y: 0)
        background.point1 = CGPoint(x: 0, y: size.height)
        background.color0 = CIColor(red: 0.93, green: 0.84, blue: 0.74)
        background.color1 = CIColor(red: 0.45, green: 0.38, blue: 0.34)
        var image = (background.outputImage ?? CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))).cropped(to: CGRect(origin: .zero, size: size))

        let window = CIImage(color: CIColor(red: 0.98, green: 0.95, blue: 0.88))
            .cropped(to: CGRect(x: 40, y: 300, width: 90, height: 120))
        image = window.composited(over: image)

        let skin = CIFilter.radialGradient()
        skin.center = CGPoint(x: 200, y: 230)
        skin.radius0 = 70
        skin.radius1 = 92
        skin.color0 = CIColor(red: 0.86, green: 0.68, blue: 0.56)
        skin.color1 = CIColor(red: 0.86, green: 0.68, blue: 0.56, alpha: 0)
        if let face = skin.outputImage?.cropped(to: CGRect(origin: .zero, size: size)) {
            image = face.composited(over: image)
        }

        let recipe = FilterRecipe.recommended(for: filter)
        let faceRect = CGRect(x: 0.30, y: 0.28, width: 0.38, height: 0.28)
        let filtered = engine.apply(to: image, recipe: recipe, grainPhase: 4, faces: .known([faceRect]))
        guard let cg = engine.previewCGImage(from: filtered, maxWidth: 360) else { return nil }
        return UIImage(cgImage: cg)
    }
}
