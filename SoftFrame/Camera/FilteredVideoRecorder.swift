import AVFoundation
import CoreImage
import CoreMedia
import Foundation

final class FilteredVideoRecorder {
    let url: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let context: CIContext
    private let size = CGSize(width: 1080, height: 1920)
    private var started = false
    private var startTime: CMTime?
    private(set) var failed = false
    private(set) var lastElapsed: Double = 0

    init?(recordAudio: Bool, context: CIContext) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        self.url = url
        self.context = context
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            return nil
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: bufferAttributes)
        var resolvedAudio: AVAssetWriterInput?
        if recordAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 128_000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            resolvedAudio = input
        }
        guard writer.canAdd(videoInput) else { return nil }
        writer.add(videoInput)
        if let resolvedAudio, writer.canAdd(resolvedAudio) {
            writer.add(resolvedAudio)
            audioInput = resolvedAudio
        } else {
            audioInput = nil
        }
    }

    func append(image: CIImage, at time: CMTime, engine: FilterEngine) {
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: time)
            started = true
            startTime = time
        }
        guard videoInput.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let pixelBuffer else { return }
        let fitted = engine.fitted(image, size: size)
        context.render(fitted, to: pixelBuffer, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpaceCreateDeviceRGB())
        if !adaptor.append(pixelBuffer, withPresentationTime: time) {
            failed = true
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard started, let audioInput, audioInput.isReadyForMoreMediaData else { return }
        if !audioInput.append(sampleBuffer) {
            failed = true
        }
    }

    func seconds(since time: CMTime) -> Double {
        guard let startTime else { return 0 }
        let value = max(0, CMTimeGetSeconds(CMTimeSubtract(time, startTime)))
        lastElapsed = value
        return value
    }

    func cancel() {
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }

    func finish() async -> URL? {
        guard started else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }
}
