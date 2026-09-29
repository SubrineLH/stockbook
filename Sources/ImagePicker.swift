import SwiftUI
import UIKit

/// 相机 / 相册选择器。iOS 15 没有 PhotosPicker，只能用 UIKit 包一层。
struct ImagePicker: UIViewControllerRepresentable {
    let source: UIImagePickerController.SourceType
    let onPicked: (Data) -> Void

    static var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onPicked: (Data) -> Void

        init(onPicked: @escaping (Data) -> Void) {
            self.onPicked = onPicked
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let picked = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            if let picked = picked,
               let data = downscaled(picked, maxSide: 1200).jpegData(compressionQuality: 0.7) {
                onPicked(data)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

/// 原图动辄四五兆，压到最长边 1200 再存，几百件货也占不了多少地方。
func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
    let longest = max(image.size.width, image.size.height)
    guard longest > maxSide else { return image }
    let scale = maxSide / longest
    let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: target)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
    }
}
