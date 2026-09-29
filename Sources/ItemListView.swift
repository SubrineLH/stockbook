import SwiftUI

struct ItemListView: View {
    @EnvironmentObject private var store: Store
    @State private var keyword = ""
    @State private var showAdd = false

    private var visibleItems: [Item] {
        let sorted = store.items.sorted { $0.updatedAt > $1.updatedAt }
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.category.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            Section {
                SummaryCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if visibleItems.isEmpty {
                Section {
                    EmptyHint(hasKeyword: !keyword.trimmingCharacters(in: .whitespaces).isEmpty)
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
        .navigationTitle("库存本")
        .searchable(text: $keyword,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜商品名或分类")
        .toolbar {
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
    }

    private var listHeader: some View {
        HStack {
            Text("商品 \(store.items.count) 项")
            Spacer()
            if !store.lowStockItems.isEmpty {
                Label("\(store.lowStockItems.count) 项不足",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        store.deleteItems(offsets.map { visibleItems[$0].id })
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
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
                    .monospacedDigit()
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
                .font(.callout.weight(.medium))
                .monospacedDigit()
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
                Text(item.category.isEmpty ? "未分类" : item.category)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.money(item.price))
                    .font(.callout)
                    .monospacedDigit()
                Text("存 \(item.stock) \(item.unit)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(item.isLow ? .orange : .secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct EmptyHint: View {
    let hasKeyword: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: hasKeyword ? "magnifyingglass" : "shippingbox")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(hasKeyword ? "没找到这个商品" : "还没有商品\n点右上角 + 添加第一件")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
