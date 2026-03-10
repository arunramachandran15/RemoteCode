import SwiftUI
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    enum Source {
        case camera
        case photoLibrary
    }

    let source: Source
    let onImagePicked: (Data) -> Void

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
            config.selectionLimit = 1
            config.filter = .images
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate {
        let onImagePicked: (Data) -> Void
        private static let maxDimension: CGFloat = 1920

        init(onImagePicked: @escaping (Data) -> Void) {
            self.onImagePicked = onImagePicked
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
            picker.dismiss(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.onImagePicked(data)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.onImagePicked(Data())
            }
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                DispatchQueue.main.async {
                    self.onImagePicked(Data())
                }
                return
            }
            provider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                let data = (obj as? UIImage).flatMap { Self.resizedJPEGData(from: $0) } ?? Data()
                DispatchQueue.main.async {
                    self?.onImagePicked(data)
                }
            }
        }
    }
}
