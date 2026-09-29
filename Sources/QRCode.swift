import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// MARK: - 商品码

/// 自家商品的二维码内容：stockbook://item/<uuid>
enum ItemCode {
    static let prefix = "stockbook://item/"

    static func link(for item: Item) -> String {
        prefix + item.id.uuidString
    }

    /// 从扫到的文本里认出是不是自家商品码
    static func itemID(from text: String) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(prefix) else { return nil }
        var raw = String(trimmed.dropFirst(prefix.count))
        if let cut = raw.firstIndex(of: "?") {
            raw = String(raw[raw.startIndex..<cut])
        }
        return UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 给客户看的码：纯文本，微信扫出来直接能读懂
    static func customerText(for item: Item) -> String {
        var lines = [item.name]
        lines.append("售价 \(Fmt.money(item.price)) / \(item.unit)")
        if !item.note.isEmpty {
            lines.append(item.note)
        }
        if item.hasSourceLink {
            lines.append(item.sourceURL)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 生成二维码

enum QRCodes {
    /// 用系统 CoreImage 生成，不引第三方库。padding 是四周留白，二维码必须留白才扫得准。
    static func image(from text: String, side: CGFloat, padding: CGFloat = 0) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let qr = UIImage(cgImage: cgImage)

        guard padding > 0 else { return qr }
        let total = side + padding * 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: total, height: total))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: total, height: total))
            qr.draw(in: CGRect(x: padding, y: padding, width: side, height: side))
        }
    }
}

// MARK: - 相机扫码

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onFound: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasFired = false
    private var torchIsOn = false
    private let sessionQueue = DispatchQueue(label: "com.family.stockbook.qr")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)

        // 只启用这台设备真的支持的类型，不然设 metadataObjectTypes 会抛异常
        let wanted: [AVMetadataObject.ObjectType] = [.qr, .ean13, .ean8, .code128, .code39, .itf14]
        output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTorch(false)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func setTorch(_ on: Bool) {
        guard on != torchIsOn else { return }
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchIsOn = on
        } catch {
            // 手电筒打不开不影响扫码，忽略
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasFired else { return }
        let code = metadataObjects
            .compactMap { $0 as? AVMetadataMachineReadableCodeObject }
            .compactMap { $0.stringValue }
            .first
        guard let code = code else { return }
        hasFired = true
        onFound?(code)
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var torchOn: Bool = false
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onFound = onFound
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {
        uiViewController.setTorch(torchOn)
    }
}

// MARK: - 商品二维码面板

/// 详情页里点「商品二维码」打开，可选择生成商品码或报价码，存相册 / 分享。
struct ItemCodeSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.presentationMode) private var presentationMode

    let itemID: UUID

    enum Mode: String, CaseIterable, Hashable {
        case shopCode
        case customer

        var title: String {
            switch self {
            case .shopCode: return "商品码"
            case .customer: return "报价码"
            }
        }
    }

    @State private var mode: Mode = .shopCode
    @State private var shareItem: ShareItem?
    @State private var savedNotice = false

    private var item: Item? { store.item(id: itemID) }

    private var codeText: String {
        guard let item = item else { return "" }
        switch mode {
        case .shopCode: return ItemCode.link(for: item)
        case .customer: return ItemCode.customerText(for: item)
        }
    }

    private var explanation: String {
        switch mode {
        case .shopCode:
            return "用 App 里的「扫一扫」扫这个码，直接跳到这件商品。可以打印出来贴货架上。"
        case .customer:
            return item?.hasSourceLink == true
                ? "纯文字码，客户用微信扫就能看到名称和价格，并能点开你的 1688 链接。"
                : "纯文字码，客户用微信扫就能看到名称和价格。"
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    codeImage

                    if let item = item, mode == .customer {
                        Text(codeText)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else if let item = item {
                        Text(item.name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Text(explanation)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button {
                            saveToAlbum()
                        } label: {
                            Label("存到相册", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FilledButtonStyle())

                        Button {
                            share()
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OutlineButtonStyle())
                    }

                    if savedNotice {
                        Text("已存到相册，去「照片」里找。")
                            .font(.footnote)
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("商品二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(item: $shareItem) { value in
            ShareSheet(items: [value.url])
        }
    }

    @ViewBuilder
    private var codeImage: some View {
        if let image = QRCodes.image(from: codeText, side: 900, padding: 48) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Text("这件商品信息不全，生成不了二维码")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func makeImageURL() -> URL? {
        guard let image = QRCodes.image(from: codeText, side: 900, padding: 48),
              let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("二维码-\(mode.title).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func saveToAlbum() {
        guard let image = QRCodes.image(from: codeText, side: 900, padding: 48) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        savedNotice = true
    }

    private func share() {
        guard let url = makeImageURL() else { return }
        shareItem = ShareItem(url: url)
    }
}

// MARK: - 扫一扫

/// 扫自家商品码 / 包装条码 → 直接打开这件商品，后面就能入库出库；
/// 扫到网址 → 直接打开；扫到别的 → 显示出来。
struct ScanSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.presentationMode) private var presentationMode

    @State private var foundItemID: UUID?
    @State private var notice: String?
    @State private var sessionID = 0
    @State private var torchOn = false

    var body: some View {
        NavigationView {
            Group {
                if let id = foundItemID {
                    ItemDetailView(itemID: id)
                } else {
                    scannerBody
                        .navigationTitle("扫一扫")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if foundItemID != nil {
                        Button("继续扫") { resume() }
                    } else {
                        Button("关闭") { presentationMode.wrappedValue.dismiss() }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if foundItemID == nil {
                        Button {
                            torchOn.toggle()
                        } label: {
                            Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                        }
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var scannerBody: some View {
        ZStack {
            QRScannerView(torchOn: torchOn, onFound: handle)
                .id(sessionID)
                .edgesIgnoringSafeArea(.all)

            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 240, height: 240)
                Text("对准商品码或包装条码")
                    .font(.footnote)
                    .foregroundColor(.white)
                    .padding(.top, 16)
                Spacer()

                if let notice = notice {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("扫到的内容")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(notice)
                            .font(.footnote)
                            .lineLimit(4)
                        HStack(spacing: 12) {
                            Button("复制") { UIPasteboard.general.string = notice }
                                .font(.footnote.weight(.medium))
                            Button("继续扫") { resume() }
                                .font(.footnote.weight(.medium))
                        }
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private func resume() {
        foundItemID = nil
        notice = nil
        torchOn = false
        sessionID += 1
    }

    private func handle(_ code: String) {
        // 1. 自家商品码
        if let id = ItemCode.itemID(from: code) {
            if store.item(id: id) != nil {
                foundItemID = id
            } else {
                notice = "这个码对应的商品已经不在库存里了。"
            }
            return
        }

        // 2. 商品包装上自带的条码
        if let matched = store.item(barcode: code) {
            foundItemID = matched.id
            return
        }

        // 3. 网址
        let lower = code.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://"),
           let url = Links.url(from: code) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            presentationMode.wrappedValue.dismiss()
            return
        }

        // 4. 其它内容，展示出来让用户自己看
        notice = code
    }
}

// MARK: - 只扫一串码（用来填输入框）

struct BarcodeScanSheet: View {
    @Environment(\.presentationMode) private var presentationMode

    let onCode: (String) -> Void

    @State private var sessionID = 0
    @State private var torchOn = false

    var body: some View {
        NavigationView {
            ZStack {
                QRScannerView(torchOn: torchOn, onFound: { code in
                    onCode(code)
                    presentationMode.wrappedValue.dismiss()
                })
                .id(sessionID)
                .edgesIgnoringSafeArea(.all)

                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 280, height: 140)
                    Text("把包装上的条码放进取景框")
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(.top, 16)
                    Spacer()
                }
            }
            .navigationTitle("扫条码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        torchOn.toggle()
                    } label: {
                        Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
