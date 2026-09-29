import SwiftUI
import UIKit

struct ItemDetailView: View {
    @EnvironmentObject private var store: Store
    let itemID: UUID

    private enum ActiveSheet: Identifiable {
        case edit(Item)
        case inbound(UUID)
        case outbound(UUID)
        case count(UUID)
        case code(UUID)

        var id: String {
            switch self {
            case .edit(let item): return "edit-\(item.id)"
            case .inbound(let id): return "in-\(id)"
            case .outbound(let id): return "out-\(id)"
            case .count(let id): return "count-\(id)"
            case .code(let id): return "code-\(id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var photoIndex = 0

    var body: some View {
        Group {
            if let item = store.item(id: itemID) {
                content(item)
            } else {
                Text("这个商品已经被删掉了")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func content(_ item: Item) -> some View {
        List {
            Section {
                header(item)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section {
                HStack(spacing: 12) {
                    Button {
                        activeSheet = .inbound(item.id)
                    } label: {
                        Label("入库", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle())

                    Button {
                        activeSheet = .outbound(item.id)
                    } label: {
                        Label("出库", systemImage: "arrow.up.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())
                }
                .padding(.vertical, 4)

                Button {
                    activeSheet = .count(item.id)
                } label: {
                    Label("盘点（按实数改库存）", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButtonStyle())
                .padding(.bottom, 4)
            }

            if item.hasSourceLink {
                Section(header: Text("进货链接")) {
                    Button {
                        if let url = Links.url(from: item.sourceURL) {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }
                    } label: {
                        Label("去 1688 打开这个货", systemImage: "link")
                    }
                    Text(item.sourceURL)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Section {
                Button {
                    activeSheet = .code(item.id)
                } label: {
                    Label("商品二维码（可打印贴货架）", systemImage: "qrcode")
                }
            }

            Section(header: Text("信息")) {
                infoRow("分类", item.category.isEmpty ? "未分类" : item.category)
                infoRow("进价", Fmt.money(item.cost))
                infoRow("单件利润", Fmt.money(item.profit))
                infoRow("按售价算的货值", Fmt.money(item.valueByPrice))
                infoRow("少于多少算不足", "\(item.lowStock) \(item.unit)")
                infoRow("照片", item.imageNames.isEmpty ? "还没拍" : "\(item.imageNames.count) 张")
                if !item.barcode.isEmpty {
                    infoRow("商品条码", item.barcode)
                }
                if !item.note.isEmpty {
                    infoRow("备注", item.note)
                }
            }

            Section(header: Text("这个商品的流水")) {
                logList(item)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("编辑") { activeSheet = .edit(item) }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .edit(let item):
                ItemEditView(mode: .edit(item))
                    .environmentObject(store)
            case .inbound(let id):
                StockSheet(itemID: id, kind: .inbound)
                    .environmentObject(store)
            case .outbound(let id):
                StockSheet(itemID: id, kind: .outbound)
                    .environmentObject(store)
            case .count(let id):
                CountSheet(itemID: id)
                    .environmentObject(store)
            case .code(let id):
                ItemCodeSheet(itemID: id)
                    .environmentObject(store)
            }
        }
    }

    /// 当前该显示第几张图（编辑过之后张数可能变少，这里夹一下范围）
    private func currentPhotoName(_ item: Item) -> String? {
        guard !item.imageNames.isEmpty else { return nil }
        return item.imageNames[safe: min(photoIndex, item.imageNames.count - 1)]
    }

    private func header(_ item: Item) -> some View {
        VStack(spacing: 16) {
            photoViewer(item)

            VStack(spacing: 6) {
                Text(item.name)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(Fmt.money(item.price))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundColor(.accentColor)

                HStack(spacing: 6) {
                    Text("库存 \(item.stock) \(item.unit)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(item.isLow ? .orange : .secondary)
                    if item.isLow {
                        Text("不足")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// 大图 + 下面的小图条。图片用 scaledToFill 铺满整个框再裁，跟外框严丝合缝。
    @ViewBuilder
    private func photoViewer(_ item: Item) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Color(UIColor.secondarySystemFill)
                if let name = currentPhotoName(item), let image = store.image(named: name) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 240)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if item.imageNames.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(item.imageNames, id: \.self) { name in
                            photoThumb(name: name, selected: name == currentPhotoName(item))
                                .onTapGesture {
                                    if let index = item.imageNames.firstIndex(of: name) {
                                        photoIndex = index
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private func photoThumb(name: String, selected: Bool) -> some View {
        ZStack {
            Group {
                if let image = store.image(named: name) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(UIColor.secondarySystemFill)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                .frame(width: 52, height: 52)
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func logList(_ item: Item) -> some View {
        if store.logs(for: item.id).isEmpty {
            Text("还没有出入库记录")
                .font(.footnote)
                .foregroundColor(.secondary)
        } else {
            ForEach(store.logs(for: item.id)) { log in
                LogRow(log: log, showsTime: true)
            }
        }
    }
}
