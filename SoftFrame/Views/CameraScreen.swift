import AVFoundation
import SwiftUI

struct CameraScreen: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var saver: PhotoSaver
    @StateObject private var camera = CameraController()
    @StateObject private var level = LevelMonitor()
    @State private var showAdjust = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.cameraDenied {
                denied
            } else {
                GeometryReader { geo in
                    ZStack {
                        preview
                        LevelGuide(roll: level.roll)
                            .opacity(level.enabled ? 1 : 0)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                    .onAppear { camera.setPreviewAspect(geo.size.width / max(geo.size.height, 1)) }
                    .onChange(of: geo.size) { _, size in
                        camera.setPreviewAspect(size.width / max(size.height, 1))
                    }
                }
                .ignoresSafeArea()
                controls
            }
        }
        .onAppear(perform: connect)
        .onDisappear {
            camera.stop()
            level.setEnabled(false)
        }
        .onChange(of: app.recipe) { _, recipe in
            camera.setRecipe(recipe)
        }
        .alert("录制无声视频", isPresented: $camera.needsSilentConfirm) {
            Button("继续") { camera.confirmSilentRecording() }
            Button("去设置") { openSystemSettings() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("麦克风没有打开。可以继续录一段没有声音的视频。")
        }
    }

    private var preview: some View {
        Group {
            if let image = camera.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        }
        .accessibilityLabel("取景")
    }

    private var controls: some View {
        VStack(spacing: 12) {
            topBar
            BannerOverlay(text: saver.banner)
            if saver.pending > 0 {
                Text("正在保存 \(saver.pending) 个")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            if camera.isRecording {
                Text(timeText(camera.recordingSeconds))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.red.opacity(0.85))
                    .clipShape(Capsule())
            }
            if showAdjust && !camera.isRecording {
                AdjustPanel()
            }
            FilterStripView(disabled: camera.isRecording)
            shutterRow
        }
        .padding(.bottom, 12)
    }

    private var topBar: some View {
        HStack {
            if camera.hasFlash {
                Button(flashTitle) { camera.cycleFlash() }
                    .accessibilityLabel("闪光灯\(flashTitle)")
            }
            Spacer()
            Button(level.enabled ? "水平开" : "水平") {
                level.setEnabled(!level.enabled)
            }
            .accessibilityLabel(level.enabled ? "关闭水平参考线" : "打开水平参考线")
            Spacer()
            Button {
                showAdjust.toggle()
            } label: {
                Text(showAdjust ? "收起" : "调节")
            }
            .disabled(camera.isRecording)
            Spacer()
            Button {
                app.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("设置")
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var shutterRow: some View {
        HStack {
            Picker("模式", selection: modeBinding) {
                Text("照片").tag(CaptureMode.photo)
                Text("视频").tag(CaptureMode.video)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .disabled(camera.isRecording)

            Spacer()

            Button(action: shutter) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 72, height: 72)
                    if camera.mode == .video && camera.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red)
                            .frame(width: 28, height: 28)
                    } else if camera.mode == .video {
                        Circle().fill(Color.red).frame(width: 58, height: 58)
                    } else {
                        Circle().fill(Color.white).frame(width: 58, height: 58)
                    }
                }
            }
            .accessibilityLabel(shutterLabel)
            .disabled(camera.inFlightCaptures >= AppConfig.maxInFlightCaptures && camera.mode == .photo)

            Spacer()

            Button(action: camera.flipCamera) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .disabled(camera.isRecording)
            .accessibilityLabel("切换前后摄像头")
            .frame(width: 120)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
    }

    private var denied: some View {
        VStack(spacing: 12) {
            Text("需要相机才能拍摄")
                .font(.headline)
            Text("到系统设置里允许 SoftFrame 使用相机。相册里的照片仍然可以调色。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("去设置", action: openSystemSettings)
                .buttonStyle(.borderedProminent)
                .tint(Theme.cream)
                .foregroundStyle(Theme.ink)
        }
        .padding(24)
    }

    private var modeBinding: Binding<CaptureMode> {
        Binding(
            get: { camera.mode },
            set: { camera.setMode($0) }
        )
    }

    private var flashTitle: String {
        switch camera.flashMode {
        case .on: return "闪光开"
        case .auto: return "闪光自动"
        default: return "闪光关"
        }
    }

    private var shutterLabel: String {
        if camera.mode == .video {
            return camera.isRecording ? "停止录像" : "开始录像"
        }
        return "拍照"
    }

    private func shutter() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if camera.mode == .photo {
            camera.takePhoto()
        } else {
            camera.toggleRecording()
        }
    }

    private func connect() {
        camera.onMessage = { message in
            Task { @MainActor in
                saver.show(message)
            }
        }
        camera.onPhotoReady = { url in
            Task { @MainActor in
                saver.enqueueFile(url, kind: .photo)
            }
        }
        camera.onVideoReady = { url in
            Task { @MainActor in
                saver.enqueueFile(url, kind: .video)
            }
        }
        camera.setRecipe(app.recipe)
        camera.start()
    }

    private func timeText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
