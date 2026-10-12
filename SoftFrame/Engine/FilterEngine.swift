import CoreImage
import CoreGraphics
import ImageIO
import Vision

enum FaceHint {
    /// 在当前图上检测人脸，导出时使用。
    case detect
    /// 归一化矩形，原点在左下，和 CIImage 一致。空数组表示已知没有脸。
    case known([CGRect])
}

enum ImageWriteError: Error {
    case unreadable
    case encodeFailed
}

final class FilterEngine {
    static let shared = FilterEngine()

    let context: CIContext

    init() {
        context = CIContext(options: [
            .cacheIntermediates: false,
            .useSoftwareRenderer: false
        ])
    }

    func apply(to source: CIImage, recipe: FilterRecipe, grainPhase: CGFloat, faces: FaceHint) -> CIImage {
        let source = normalized(source)
        let extent = source.extent
        guard extent.width > 1, extent.height > 1, extent.width.isFinite, extent.height.isFinite else { return source }

        let recipe = recipe.clamped()
        var image = applyGrade(source, recipe: recipe)
        image = applyWarmth(image, warmth: recipe.warmth, tint: recipe.filter.grade.tint)
        image = applySkin(image, strength: recipe.skin, faces: faces)
        image = applyGrain(image, amount: recipe.grain, phase: grainPhase)
        image = mix(processed: image, original: source, intensity: recipe.intensity)
        return normalized(image.cropped(to: extent))
    }

    func previewCGImage(from image: CIImage, maxWidth: CGFloat) -> CGImage? {
        let scaled = scale(normalized(image), maxWidth: maxWidth)
        let frame = normalized(scaled)
        return context.createCGImage(frame, from: frame.extent)
    }

    func writeTemporary(image: CIImage) throws -> URL {
        let frame = normalized(image)
        let bounds = CGRect(x: 0, y: 0, width: frame.extent.width.rounded(), height: frame.extent.height.rounded())
        let cropped = frame.cropped(to: bounds)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let heic = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".heic")
        do {
            try context.writeHEIFRepresentation(of: cropped, to: heic, format: .RGBA8, colorSpace: colorSpace, options: [:])
            return heic
        } catch {
            try? FileManager.default.removeItem(at: heic)
        }

        let jpeg = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try context.writeJPEGRepresentation(
                of: cropped,
                to: jpeg,
                colorSpace: colorSpace,
                options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.95]
            )
            return jpeg
        } catch {
            try? FileManager.default.removeItem(at: jpeg)
            throw ImageWriteError.encodeFailed
        }
    }

    func centerCrop(_ image: CIImage, to aspectWidthOverHeight: CGFloat) -> CIImage {
        let image = normalized(image)
        let extent = image.extent
        guard aspectWidthOverHeight > 0.05, extent.width > 1, extent.height > 1 else { return image }
        let imageAspect = extent.width / extent.height
        var crop = extent
        if imageAspect > aspectWidthOverHeight {
            let newWidth = extent.height * aspectWidthOverHeight
            crop.origin.x = (extent.width - newWidth) / 2
            crop.size.width = newWidth
        } else if imageAspect < aspectWidthOverHeight {
            let newHeight = extent.width / aspectWidthOverHeight
            crop.origin.y = (extent.height - newHeight) / 2
            crop.size.height = newHeight
        }
        return normalized(image.cropped(to: crop))
    }

    func normalizedFaces(in image: CIImage) -> [CGRect] {
        let image = normalized(image)
        let extent = image.extent
        guard extent.width > 1, extent.height > 1 else { return [] }
        return detectFaces(in: image).map { rect in
            CGRect(
                x: rect.minX / extent.width,
                y: rect.minY / extent.height,
                width: rect.width / extent.width,
                height: rect.height / extent.height
            )
        }
    }

    func fitted(_ image: CIImage, size: CGSize) -> CIImage {
        let image = normalized(image)
        let extent = image.extent
        guard extent.width > 1, extent.height > 1, size.width > 1, size.height > 1 else { return image }
        let scale = max(size.width / extent.width, size.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaled.extent
        let originX = scaledExtent.minX + (scaledExtent.width - size.width) / 2
        let originY = scaledExtent.minY + (scaledExtent.height - size.height) / 2
        let cropped = scaled.cropped(to: CGRect(x: originX, y: originY, width: size.width, height: size.height))
        return normalized(cropped)
    }

    // MARK: - Pipeline

    private func applyGrade(_ image: CIImage, recipe: FilterRecipe) -> CIImage {
        let grade = recipe.filter.grade
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.saturation = Float(grade.saturation)
        controls.contrast = Float(grade.contrast)
        controls.brightness = Float(grade.brightness)
        var output = controls.outputImage ?? image

        let tone = CIFilter.highlightShadowAdjust()
        tone.inputImage = output
        tone.highlightAmount = Float(min(1, max(0, grade.highlightAmount)))
        tone.shadowAmount = Float(min(1, max(0, grade.shadowAmount)))
        output = tone.outputImage ?? output

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = output
        matrix.rVector = CIVector(x: grade.redGain, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: grade.greenGain, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: grade.blueGain, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return matrix.outputImage?.cropped(to: image.extent) ?? output
    }

    private func applyWarmth(_ image: CIImage, warmth: Double, tint: CGFloat) -> CIImage {
        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = image
        filter.neutral = CIVector(x: 6500, y: 0)
        let temperature = 6500 - CGFloat(warmth) * 22
        filter.targetNeutral = CIVector(x: min(9000, max(3500, temperature)), y: tint + CGFloat(warmth) * 0.05)
        return filter.outputImage?.cropped(to: image.extent) ?? image
    }

    private func applySkin(_ image: CIImage, strength: Double, faces: FaceHint) -> CIImage {
        guard strength > 0.5 else { return image }
        let rects: [CGRect]
        switch faces {
        case .detect:
            rects = detectFaces(in: image)
        case .known(let known):
            rects = known.map { denormalize($0, extent: image.extent) }
        }
        guard !rects.isEmpty else { return image }

        let mix = CGFloat(strength / 30) * 0.45
        let faceWidth = rects.map(\.width).max() ?? image.extent.width * 0.3
        let sigma = max(0.4, CGFloat(strength / 30) * faceWidth * 0.012)
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: image.extent)
        let softened = dissolve(from: blurred, to: image, time: 1 - mix)
        let mask = faceMask(rects: rects, extent: image.extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = softened
        blend.backgroundImage = image
        blend.maskImage = mask
        return blend.outputImage?.cropped(to: image.extent) ?? image
    }

    private func applyGrain(_ image: CIImage, amount: Double, phase: CGFloat) -> CIImage {
        guard amount > 0.5 else { return image }
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }
        let shifted = noise.transformed(by: CGAffineTransform(translationX: phase * 19, y: phase * 11))
        let crop = image.extent.insetBy(dx: -8, dy: -8)
        let alpha = CGFloat(amount / 100) * 0.33
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = shifted.cropped(to: crop)
        let gray = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
        matrix.rVector = gray
        matrix.gVector = gray
        matrix.bVector = gray
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: alpha)
        guard let speck = matrix.outputImage?.cropped(to: image.extent) else { return image }
        return speck.composited(over: image).cropped(to: image.extent)
    }

    private func mix(processed: CIImage, original: CIImage, intensity: Double) -> CIImage {
        if intensity >= 99.5 { return processed }
        if intensity <= 0.5 { return original }
        return dissolve(from: processed, to: original, time: 1 - CGFloat(intensity / 100))
    }

    private func dissolve(from image: CIImage, to target: CIImage, time: CGFloat) -> CIImage {
        let filter = CIFilter.dissolveTransition()
        filter.inputImage = image
        filter.targetImage = target
        filter.time = Float(min(1, max(0, time)))
        return filter.outputImage?.cropped(to: image.extent) ?? image
    }

    private func detectFaces(in image: CIImage) -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let observations = request.results ?? []
        return observations.map { denormalize($0.boundingBox, extent: image.extent).insetBy(dx: -0.04 * $0.boundingBox.width * image.extent.width, dy: -0.08 * $0.boundingBox.height * image.extent.height) }
    }

    private func faceMask(rects: [CGRect], extent: CGRect) -> CIImage {
        var accum = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        for face in rects {
            let ellipse = ellipseMask(face: face, extent: extent)
            let lighten = CIFilter.lightenBlendMode()
            lighten.inputImage = ellipse
            lighten.backgroundImage = accum
            accum = lighten.outputImage?.cropped(to: extent) ?? accum
        }
        return accum
    }

    private func ellipseMask(face: CGRect, extent: CGRect) -> CIImage {
        let center = CGPoint(x: face.midX, y: face.midY)
        let radius = max(8, face.width * 0.48)
        let gradient = CIFilter.radialGradient()
        gradient.center = center
        gradient.radius0 = Float(radius * 0.45)
        gradient.radius1 = Float(radius)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        let local = (gradient.outputImage ?? CIImage(color: .black)).cropped(to: face.insetBy(dx: -face.width, dy: -face.height))
        let stretch = max(0.6, face.height / max(face.width, 1))
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: center.x, y: center.y)
        transform = transform.scaledBy(x: 1, y: stretch)
        transform = transform.translatedBy(x: -center.x, y: -center.y)
        return local.transformed(by: transform).cropped(to: extent)
    }

    private func denormalize(_ rect: CGRect, extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + rect.minX * extent.width,
            y: extent.minY + rect.minY * extent.height,
            width: rect.width * extent.width,
            height: rect.height * extent.height
        )
    }

    private func normalized(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.isFinite, !extent.isEmpty else { return image }
        if extent.minX == 0, extent.minY == 0 { return image }
        return image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }

    private func scale(_ image: CIImage, maxWidth: CGFloat) -> CIImage {
        let width = image.extent.width
        guard width > maxWidth, width > 0 else { return image }
        let factor = maxWidth / width
        return image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
    }
}

private extension CGRect {
    var isFinite: Bool {
        origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite
    }
}

enum ImageDecoding {
    static func ciImage(from data: Data) throws -> CIImage {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw ImageWriteError.unreadable
        }
        let extent = image.extent
        guard extent.width >= 2, extent.height >= 2, extent.width <= 12000, extent.height <= 12000 else {
            throw ImageWriteError.unreadable
        }
        return image
    }
}
