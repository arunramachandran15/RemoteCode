import SwiftUI
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    enum Source {
        case camera
        case photoLibrary
    }

    let source: Source
    let onImagesPicked: ([Data]) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        switch source {
        case .camera:
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            picker.allowsEditing = false
            return picker
        case .photoLibrary:
            var config = PHPickerConfiguration()
            config.selectionLimit = 0
            config.filter = .images
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagesPicked: onImagesPicked)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate {
        let onImagesPicked: ([Data]) -> Void
        private static let maxDimension: CGFloat = 1920

        init(onImagesPicked: @escaping ([Data]) -> Void) {
            self.onImagesPicked = onImagesPicked
        }

        private static func resizedJPEGData(from image: UIImage) -> Data? {
            let resized = downsized(image)
            return resized.jpegData(compressionQuality: 0.7)
        }

        private static func downsized(_ image: UIImage) -> UIImage {
            let size = image.size
            guard max(size.width, size.height) > maxDimension else { return image }
            let scale = maxDimension / max(size.width, size.height)
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            let data = image.flatMap { Self.resizedJPEGData(from: $0) } ?? Data()
            DispatchQueue.main.async {
                self.onImagesPicked(data.isEmpty ? [] : [data])
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            DispatchQueue.main.async {
                self.onImagesPicked([])
            }
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let providers = results.compactMap { $0.itemProvider.canLoadObject(ofClass: UIImage.self) ? $0.itemProvider : nil }
            guard !providers.isEmpty else {
                DispatchQueue.main.async {
                    self.onImagesPicked([])
                }
                return
            }
            let group = DispatchGroup()
            var images: [(Int, Data)] = []
            let lock = NSLock()

            for (index, provider) in providers.enumerated() {
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let uiImage = obj as? UIImage, let data = Self.resizedJPEGData(from: uiImage) {
                        lock.lock()
                        images.append((index, data))
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) { [weak self] in
                let sorted = images.sorted { $0.0 < $1.0 }.map(\.1)
                self?.onImagesPicked(sorted)
            }
        }
    }
}
