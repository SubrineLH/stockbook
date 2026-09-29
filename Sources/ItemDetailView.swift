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

        var id: String {
            switch self {
            case .edit(let item): return "edit-\(item.id)"
            case .inbound(let id): return "in-\(id)"
            case .outbound(let id): return "out-\(id)"
            case .count(let id): return "count-\(id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?

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

            Section(header: Text("信息")) {
                infoRow("分类", item.category.isEmpty ? "未分类" : item.category)
                infoRow("进价", Fmt.money(item.cost))
                infoRow("单件利润", Fmt.money(item.profit))
                infoRow("按售价算的货值", Fmt.money(item.valueByPrice))
                infoRow("少于多少算不足", "\(item.lowStock) \(item.unit)")
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
            }
        }
    }

    private func header(_ item: Item) -> some View {
        VStack(spacing: 16) {
            Group {
                if let image = store.image(named: item.imageName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color(UIColor.secondarySystemFill)
                        Image(systemName: "shippingbox")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

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
