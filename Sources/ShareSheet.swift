import SwiftUI
import UIKit

/// 包一层系统分享面板，用来把导出的 CSV 发给微信 / 存到「文件」。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// URL 本身不是 Identifiable，包一层才能配合 .sheet(item:) 使用。
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
