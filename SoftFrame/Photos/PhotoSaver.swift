import Combine
import Foundation
import Photos
import UIKit

enum SavedMedia {
    case photo
    case video

    var resourceType: PHAssetResourceType {
        switch self {
        case .photo: return .photo
        case .video: return .video
        }
    }
}

enum SaveError: LocalizedError {
    case photoPermission
    case noSpace
    case failed

    var errorDescription: String? {
        switch self {
        case .photoPermission:
            return "没有相册权限，暂时存不了。请到系统设置里允许添加照片。"
        case .noSpace:
            return "手机存储空间不足，保存失败。"
        case .failed:
            return "保存失败，请再试一次。"
        }
    }
}

@MainActor
final class PhotoSaver: ObservableObject {
    @Published private(set) var pending = 0
    @Published var banner: String?
    private var successfulSaves = 0
    private var didRequestReview = false
    var onTenthSave: (() -> Void)?

    func enqueueFile(_ url: URL, kind: SavedMedia) {
        pending += 1
        Task {
            defer {
                try? FileManager.default.removeItem(at: url)
                pending = max(0, pending - 1)
            }
            do {
                try await Self.write(url: url, kind: kind.resourceType)
                noteSuccess()
                show("已保存")
            } catch {
                show(Self.describe(error))
            }
        }
    }

    func show(_ text: String) {
        banner = text
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if banner == text {
                banner = nil
            }
        }
    }

    private func noteSuccess() {
        successfulSaves += 1
        guard successfulSaves == AppConfig.reviewSaveThreshold, !didRequestReview else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        let key = "softframe.review.\(version)"
        if UserDefaults.standard.bool(forKey: key) {
            didRequestReview = true
            return
        }
        didRequestReview = true
        UserDefaults.standard.set(true, forKey: key)
        onTenthSave?()
    }

    private static func write(url: URL, kind: PHAssetResourceType) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .denied || status == .restricted {
            throw SaveError.photoPermission
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: kind, fileURL: url, options: nil)
            }
        } catch {
            throw map(error)
        }
    }

    private static func map(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError {
            return SaveError.noSpace
        }
        if ns.domain == PHPhotosErrorDomain {
            return SaveError.photoPermission
        }
        return SaveError.failed
    }

    private static func describe(_ error: Error) -> String {
        if let save = error as? SaveError {
            return save.errorDescription ?? "保存失败，请再试一次。"
        }
        return error.localizedDescription
    }
}
