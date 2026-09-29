import SwiftUI
import UIKit

struct ItemEditView: View {

    enum Mode {
        case create
        case edit(Item)
    }

    /// 一张新加进来的照片。用 id 保证列表里的位置稳定，删中间那张不会串位。
    private struct NewPhoto: Identifiable {
        let id = UUID()
        let data: Data
    }

    private enum ActiveSheet: Identifiable {
        case camera
        case library
        case barcode

        var id: String {
            switch self {
            case .camera: return "camera"
            case .library: return "library"
            case .barcode: return "barcode"
            }
        }
    }

    @EnvironmentObject private var store: Store
    @Environment(\.presentationMode) private var presentationMode
    let mode: Mode

    @State private var name: String
    @State private var category: String
    @State private var costText: String
    @State private var priceText: String
    @State private var stockText: String
    @State private var unit: String
    @State private var lowStockText: String
    @State private var note: String
    @State private var sourceURL: String
    @State private var barcode: String
    @State private var existingImageNames: [String]
    @State private var newPhotos: [NewPhoto] = []
    @State private var showPhotoMenu = false
    @State private var activeSheet: ActiveSheet?
    @State private var pasteHint = ""

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _category = State(initialValue: "")
            _costText = State(initialValue: "")
            _priceText = State(initialValue: "")
            _stockText = State(initialValue: "")
            _unit = State(initialValue: "件")
            _lowStockText = State(initialValue: "5")
            _note = State(initialValue: "")
            _sourceURL = State(initialValue: "")
            _barcode = State(initialValue: "")
            _existingImageNames = State(initialValue: [])
        case .edit(let item):
            _name = State(initialValue: item.name)
            _category = State(initialValue: item.category)
            _costText = State(initialValue: item.cost == 0 ? "" : String(format: "%.2f", item.cost))
            _priceText = State(initialValue: item.price == 0 ? "" : String(format: "%.2f", item.price))
            _stockText = State(initialValue: String(item.stock))
            _unit = State(initialValue: item.unit)
            _lowStockText = State(initialValue: String(item.lowStock))
            _note = State(initialValue: item.note)
            _sourceURL = State(initialValue: item.sourceURL)
            _barcode = State(initialValue: item.barcode)
            _existingImageNames = State(initialValue: item.imageNames)
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private var existingStock: Int {
        if case .edit(let item) = mode { return item.stock }
        return 0
    }

    private var photoCount: Int { existingImageNames.count + newPhotos.count }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("商品照片")) {
                    photoStrip
                    Text(photoHint)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("基本信息")) {
                    TextField("商品名称", text: $name)
                    TextField("分类，比如 鲜果 / 粮油", text: $category)
                }

                Section(header: Text("商品条码")) {
                    FieldRow("条码") {
                        TextField("包装上的数字", text: $barcode)
                            .keyboardType(.numberPad)
                            .font(.body.monospacedDigit())
                            .frame(minWidth: 80, alignment: .trailing)
                    }
                    Button {
                        activeSheet = .barcode
                    } label: {
                        Label("扫一下包装上的条码", systemImage: "barcode.viewfinder")
                    }
                    Text("填了之后，用「扫一扫」扫这个条码就能直接找到这件货。袋装米、饮料这类有正规条码的货最省事。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("进货链接")) {
                    TextField("粘贴 1688 / 淘宝商品链接", text: $sourceURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                    }

                    if !pasteHint.isEmpty {
                        Text(pasteHint)
                            .font(.footnote)
                            .foregroundColor(.orange)
                    }

                    Text("在 1688 / 淘宝里点商品的「分享 → 复制链接」，回来按上面的按钮。带口令的整段文字也能识别，会自动把网址挑出来。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("价格")) {
                    FieldRow("进价") { moneyField($costText) }
                    FieldRow("售价") { moneyField($priceText) }
                    if !profitHint.isEmpty {
                        Text(profitHint)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("库存")) {
                    if isCreating {
                        FieldRow("初始数量") { intField($stockText) }
                    } else {
                        HStack {
                            Text("当前库存")
                            Spacer(minLength: 16)
                            Text("\(existingStock)")
                                .font(.body.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        Text("改数量请到商品详情页用「入库 / 出库 / 盘点」，流水才对得上。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    FieldRow("单位") {
                        TextField("件", text: $unit)
                            .frame(minWidth: 80, alignment: .trailing)
                    }
                    FieldRow("少于多少算不足") { intField($lowStockText) }
                }

                Section(header: Text("备注")) {
                    TextField("可选", text: $note)
                }
            }
            .navigationTitle(isCreating ? "添加商品" : "编辑商品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .actionSheet(isPresented: $showPhotoMenu) {
            ActionSheet(title: Text("加一张商品照片"), buttons: photoButtons)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .camera:
                ImagePicker(source: .camera) { data in
                    newPhotos.append(NewPhoto(data: data))
                }
            case .library:
                ImagePicker(source: .photoLibrary) { data in
                    newPhotos.append(NewPhoto(data: data))
                }
            case .barcode:
                BarcodeScanSheet { code in
                    barcode = code
                }
            }
        }
    }

    // MARK: - 照片

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(existingImageNames, id: \.self) { storedName in
                    photoTile(image: store.image(named: storedName)) {
                        existingImageNames.removeAll { $0 == storedName }
                    }
                }
                ForEach(newPhotos) { photo in
                    photoTile(image: UIImage(data: photo.data)) {
                        newPhotos.removeAll { $0.id == photo.id }
                    }
                }
                addPhotoButton
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
    }

    private func photoTile(image: UIImage?, onDelete: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(UIColor.secondarySystemFill)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.45), radius: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(4)
        }
        .frame(width: 96, height: 96)
    }

    private var addPhotoButton: some View {
        Button {
            showPhotoMenu = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "camera")
                    .font(.system(size: 22))
                Text("加照片")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .frame(width: 96, height: 96)
            .background(Color(UIColor.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var photoHint: String {
        switch photoCount {
        case 0:
            return "还没有照片。建议拍两三张：正面、标签、包装。"
        case 1:
            return "现在 1 张。第一张会作为列表里的封面，可以再加几张。"
        default:
            return "共 \(photoCount) 张，第一张作为列表封面。"
        }
    }

    /// iOS 14 没有 .confirmationDialog，用 ActionSheet 代替。
    private var photoButtons: [ActionSheet.Button] {
        var buttons: [ActionSheet.Button] = []
        if ImagePicker.cameraAvailable {
            buttons.append(.default(Text("拍一张")) { activeSheet = .camera })
        }
        buttons.append(.default(Text("从相册选")) { activeSheet = .library })
        buttons.append(.cancel(Text("取消")))
        return buttons
    }

    // MARK: - 其它字段

    private var profitHint: String {
        let cost = Double(costText) ?? 0
        let price = Double(priceText) ?? 0
        guard cost > 0 || price > 0 else { return "" }
        let profit = price - cost
        guard cost > 0 else { return "单件利润 \(Fmt.money(profit))" }
        return String(format: "单件利润 %@，毛利率 %.0f%%", Fmt.money(profit), profit / cost * 100)
    }

    private func moneyField(_ binding: Binding<String>) -> some View {
        TextField("0.00", text: binding)
            .keyboardType(.decimalPad)
            .font(.body.monospacedDigit())
            .frame(minWidth: 80, alignment: .trailing)
    }

    private func intField(_ binding: Binding<String>) -> some View {
        TextField("0", text: binding)
            .keyboardType(.numberPad)
            .font(.body.monospacedDigit())
            .frame(minWidth: 80, alignment: .trailing)
    }

    private func pasteFromClipboard() {
        let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            pasteHint = "剪贴板里没有内容。先在 1688 / 淘宝里复制商品链接。"
            return
        }
        if let link = Links.firstLink(in: text) {
            sourceURL = link
            pasteHint = ""
        } else {
            sourceURL = text
            pasteHint = "没找到网址。淘宝要选「复制链接」，不是「复制口令」。"
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let trimmedCategory = category.trimmingCharacters(in: .whitespaces)
        // 贴进来的是整段分享文字也没关系，这里再抠一次网址
        let link = Links.firstLink(in: sourceURL)
            ?? sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBarcode = barcode.trimmingCharacters(in: .whitespaces)
        let cost = Double(costText) ?? 0
        let price = Double(priceText) ?? 0
        let low = Int(lowStockText) ?? 5
        let finalUnit = unit.trimmingCharacters(in: .whitespaces).isEmpty ? "件" : unit

        switch mode {
        case .create:
            var item = Item()
            item.name = trimmedName
            item.category = trimmedCategory
            item.cost = cost
            item.price = price
            item.stock = Int(stockText) ?? 0
            item.unit = finalUnit
            item.lowStock = low
            item.note = note
            item.sourceURL = link
            item.barcode = trimmedBarcode
            store.addItem(item, images: newPhotos.map { $0.data })
        case .edit(let original):
            var item = original
            item.name = trimmedName
            item.category = trimmedCategory
            item.cost = cost
            item.price = price
            item.unit = finalUnit
            item.lowStock = low
            item.note = note
            item.sourceURL = link
            item.barcode = trimmedBarcode
            store.updateItem(item,
                             newImages: newPhotos.map { $0.data },
                             keepImageNames: existingImageNames)
        }
        presentationMode.wrappedValue.dismiss()
    }
}
