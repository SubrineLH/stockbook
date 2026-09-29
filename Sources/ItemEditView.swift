import SwiftUI
import UIKit

struct ItemEditView: View {

    enum Mode {
        case create
        case edit(Item)
    }

    private enum PhotoSource: String, Identifiable {
        case camera
        case library
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var name: String
    @State private var category: String
    @State private var costText: String
    @State private var priceText: String
    @State private var stockText: String
    @State private var unit: String
    @State private var lowStockText: String
    @State private var note: String
    @State private var imageData: Data?
    @State private var keptImageName: String?
    @State private var removeImage = false
    @State private var showPhotoMenu = false
    @State private var photoSource: PhotoSource?

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
            _keptImageName = State(initialValue: nil)
        case .edit(let item):
            _name = State(initialValue: item.name)
            _category = State(initialValue: item.category)
            _costText = State(initialValue: item.cost == 0 ? "" : String(format: "%.2f", item.cost))
            _priceText = State(initialValue: item.price == 0 ? "" : String(format: "%.2f", item.price))
            _stockText = State(initialValue: String(item.stock))
            _unit = State(initialValue: item.unit)
            _lowStockText = State(initialValue: String(item.lowStock))
            _note = State(initialValue: item.note)
            _keptImageName = State(initialValue: item.imageName)
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

    private var hasImage: Bool {
        imageData != nil || (!removeImage && keptImageName != nil)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("商品照片")) {
                    photoRow
                }

                Section(header: Text("基本信息")) {
                    TextField("商品名称", text: $name)
                    TextField("分类，比如 鲜果 / 粮油", text: $category)
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
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Text("改数量请到商品详情页用「入库 / 出库」，流水才对得上。")
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
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .confirmationDialog("商品照片", isPresented: $showPhotoMenu, titleVisibility: .visible) {
            if ImagePicker.cameraAvailable {
                Button("拍一张") { photoSource = .camera }
            }
            Button("从相册选") { photoSource = .library }
            if hasImage {
                Button("删除照片", role: .destructive) { clearImage() }
            }
            Button("取消", role: .cancel) { }
        }
        .sheet(item: $photoSource) { source in
            ImagePicker(source: source == .camera ? .camera : .photoLibrary) { data in
                imageData = data
                removeImage = false
            }
        }
    }

    @ViewBuilder
    private var photoRow: some View {
        Button {
            showPhotoMenu = true
        } label: {
            HStack {
                Spacer()
                photoPreview
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let data = imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if !removeImage, let name = keptImageName, let image = store.image(named: name) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "camera")
                    .font(.system(size: 28))
                Text("拍一张商品照片")
                    .font(.footnote)
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.secondarySystemFill))
        }
    }

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
            .monospacedDigit()
            .frame(minWidth: 80, alignment: .trailing)
    }

    private func intField(_ binding: Binding<String>) -> some View {
        TextField("0", text: binding)
            .keyboardType(.numberPad)
            .monospacedDigit()
            .frame(minWidth: 80, alignment: .trailing)
    }

    private func clearImage() {
        imageData = nil
        keptImageName = nil
        removeImage = true
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let trimmedCategory = category.trimmingCharacters(in: .whitespaces)
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
            store.addItem(item, imageData: imageData)
        case .edit(let original):
            var item = original
            item.name = trimmedName
            item.category = trimmedCategory
            item.cost = cost
            item.price = price
            item.unit = finalUnit
            item.lowStock = low
            item.note = note
            store.updateItem(item, imageData: imageData, removeImage: removeImage)
        }
        dismiss()
    }
}
