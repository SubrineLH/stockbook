import SwiftUI
import UIKit

struct ItemListView: View {
    @EnvironmentObject private var store: Store

    enum QuickFilter: Hashable {
        case all
        case lowStock
        case category(String)
    }

    enum SortMode: String, CaseIterable, Hashable {
        case recent
        case name
        case stockAsc
        case valueDesc

        var title: String {
            switch self {
            case .recent: return "最近改动的排前面"
            case .name: return "按名称排"
            case .stockAsc: return "库存少的排前面"
            case .valueDesc: return "货值高的排前面"
            }
        }
    }

    @State private var keyword = ""
    @State private var showAdd = false
    @State private var filter: QuickFilter = .all
    @State private var sortMode: SortMode = .recent
    @State private var showScanner = false
    @State private var scannedItemID: UUID?

    private var visibleItems: [Item] {
        var result = store.items

        switch filter {
        case .all:
            break
        case .lowStock:
            result = result.filter { $0.isLow }
        case .category(let name):
            result = result.filter { $0.category == name }
        }

        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.category.localizedCaseInsensitiveContains(trimmed)
            }
        }

        switch sortMode {
        case .recent:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .name:
            result.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .stockAsc:
            result.sort { $0.stock < $1.stock }
        case .valueDesc:
            result.sort { $0.valueByPrice > $1.valueByPrice }
        }
        return result
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    searchField
                    filterChips
                }
                .padding(.vertical, 2)
            }

            Section {
                SummaryCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if visibleItems.isEmpty {
                Section {
                    EmptyHint(message: emptyMessage)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section(header: listHeader) {
                    ForEach(visibleItems) { item in
                        NavigationLink(destination: ItemDetailView(itemID: item.id)) {
                            ItemRow(item: item)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("StockBook")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 18) {
                    Button { showScanner = true } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    Menu {
                        Picker("排序", selection: $sortMode) {
                            ForEach(SortMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            ItemEditView(mode: .create)
                .environmentObject(store)
        }
        .sheet(isPresented: $showScanner) {
            ScanSheet { id in
                scannedItemID = id
            }
            .environmentObject(store)
        }
        .background(scanLink)
    }

    // MARK: - 顶部

    /// iOS 14 没有 .searchable，自己拼一个搜索框。
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("搜商品名或分类", text: $keyword)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            if !keyword.isEmpty {
                Button {
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", on: filter == .all) {
                    filter = .all
                }

                if !store.lowStockItems.isEmpty {
                    chip(title: "该进货 \(store.lowStockItems.count)", on: filter == .lowStock) {
                        filter = .lowStock
                    }
                }

                ForEach(store.categories, id: \.self) { name in
                    chip(title: name, on: filter == .category(name)) {
                        filter = .category(name)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(on ? Color.accentColor : Color(UIColor.secondarySystemFill))
                .foregroundColor(on ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var listHeader: some View {
        HStack {
            Text("\(visibleItems.count) 件")
            Spacer()
            if filter != .lowStock && !store.lowStockItems.isEmpty {
                Label("\(store.lowStockItems.count) 件不足",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
    }

    private var emptyMessage: String {
        if !keyword.trimmingCharacters(in: .whitespaces).isEmpty {
            return "没找到这个商品"
        }
        switch filter {
        case .lowStock:
            return "没有要补的货，库存都够"
        case .category:
            return "这个分类下还没有商品"
        case .all:
            return "还没有商品\n点右上角 + 添加第一件"
        }
    }

    private func delete(at offsets: IndexSet) {
        store.deleteItems(offsets.map { visibleItems[$0].id })
    }

    // MARK: - 扫码跳转

    /// 扫到自家商品码后，靠这个隐藏的 NavigationLink 把详情页推出来
    private var scanLink: some View {
        NavigationLink(destination: scanDestination, isActive: showsScannedItem) {
            EmptyView()
        }
    }

    private var showsScannedItem: Binding<Bool> {
        Binding(get: { scannedItemID != nil },
                set: { if !$0 { scannedItemID = nil } })
    }

    @ViewBuilder
    private var scanDestination: some View {
        if let id = scannedItemID {
            ItemDetailView(itemID: id)
        }
    }
}

/// 顶部总览卡：一眼看到家底。
struct SummaryCard: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("库存总览")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.moneyRound(store.totalValueByPrice))
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(.accentColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("全卖完能收")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                stat("成本占用", Fmt.moneyRound(store.totalValueByCost))
                stat("库存件数", "\(store.totalStockCount)")
                stat("今日出货", Fmt.moneyRound(store.todayOutAmount))
            }
        }
        .card()
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.callout.weight(.medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 商品列表里的一行。
struct ItemRow: View {
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            ItemThumbnail(item: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if item.hasSourceLink {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(item.category.isEmpty ? "未分类" : item.category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.money(item.price))
                    .font(.callout.monospacedDigit())
                Text("存 \(item.stock) \(item.unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(item.isLow ? .orange : .secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct EmptyHint: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
