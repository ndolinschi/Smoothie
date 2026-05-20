import SwiftUI
import PhotosUI
import UIKit

/// SwiftUI wrapper around PHPickerViewController (library) and
/// UIImagePickerController (camera). Returns a `StagedImage` ready to be
/// appended to `MessageInput.attachments`. The picker resizes images to a
/// max 1600 px on the long edge and re-encodes them as JPEG @ 0.85 quality
/// so the base64 payload stays under a few MB per attachment — Claude's
/// vision input cap is generous, but the HTTP body limit and stream-json
/// stdin pipe aren't.
struct ImagePickerSheet: View {
    enum Source: String, Identifiable {
        case camera, library
        var id: String { rawValue }
    }

    let source: Source
    let onPicked: (StagedImage) -> Void
    let onCancel: () -> Void

    var body: some View {
        switch source {
        case .camera:
            CameraPicker(onPicked: onPicked, onCancel: onCancel)
                .ignoresSafeArea()
        case .library:
            LibraryPicker(onPicked: onPicked, onCancel: onCancel)
                .ignoresSafeArea()
        }
    }
}

// MARK: - PHPickerViewController bridge

private struct LibraryPicker: UIViewControllerRepresentable {
    let onPicked: (StagedImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (StagedImage) -> Void
        let onCancel: () -> Void
        init(onPicked: @escaping (StagedImage) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                onCancel()
                return
            }
            let suggestedName = results.first?.assetIdentifier ?? "image"
            let onPicked = self.onPicked
            let onCancel = self.onCancel
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let uiImage = object as? UIImage
                let pngData = uiImage.flatMap { $0.pngData() }
                Task { @MainActor in
                    guard let pngData,
                          let image = UIImage(data: pngData),
                          let staged = StagedImage.build(from: image, suggestedName: suggestedName) else {
                        onCancel()
                        return
                    }
                    onPicked(staged)
                }
            }
        }
    }
}

// MARK: - Camera bridge

private struct CameraPicker: UIViewControllerRepresentable {
    let onPicked: (StagedImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (StagedImage) -> Void
        let onCancel: () -> Void
        init(onPicked: @escaping (StagedImage) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.originalImage] as? UIImage)
            guard let image, let staged = StagedImage.build(from: image, suggestedName: "camera") else {
                onCancel(); return
            }
            onPicked(staged)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

// MARK: - Building a StagedImage

extension StagedImage {
    /// Compress, resize, base64-encode. Returns nil if the image can't be
    /// rendered as JPEG. Cap long edge at 1600 px so the payload stays
    /// reasonable; for retina photos this drops a typical 4 MB image to
    /// ~300 KB, well under any wire limit.
    @MainActor
    static func build(from image: UIImage, suggestedName: String) -> StagedImage? {
        let maxEdge: CGFloat = 1600
        let resized = image.resizedToMaxEdge(maxEdge)
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        let base64 = data.base64EncodedString()
        let thumb = resized.resizedToMaxEdge(120)
        let name = suggestedName.split(separator: "/").last.map(String.init) ?? "image"
        return StagedImage(
            name: name.hasSuffix(".jpg") ? name : "\(name).jpg",
            mimeType: "image/jpeg",
            base64: base64,
            thumbnail: thumb
        )
    }
}

private extension UIImage {
    func resizedToMaxEdge(_ maxEdge: CGFloat) -> UIImage {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxEdge else { return self }
        let scale = maxEdge / longEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
