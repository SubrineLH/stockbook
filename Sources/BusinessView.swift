import SwiftUI

/// 生意：赚了多少、还欠着多少、该发什么货。
struct BusinessView: View {
    @EnvironmentObject private var store: Store

    enum Span: String, CaseIterable, Hashable {
        case today
        case month
        case year

        var title: String {
            switch self {
            case .today: return "今天"
            case .month: return "本月"
            case .year: return "今年"
            }
        }
    }

    @State private var span: Span = .today

    private var since: Date {
        switch span {
        case .today: return store.startOfToday
        case .month: return store.startOfMonth
        case .year: return store.startOfYear
        }
    }

    private var stats: PeriodStats { store.stats(since: since) }
    private var topSellers: [TopSeller] { store.topSellers(since: since, limit: 5) }

    var body: some View {
        List {
            Section {
                Picker("区间", selection: $span) {
                    ForEach(Span.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(span.title)卖出")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Fmt.moneyRound(stats.salesAmount))
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("\(stats.orderCount) 单 / \(stats.soldCount) 件")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    HStack(alignment: .top, spacing: 8) {
                        stat("赚了多少", Fmt.moneyRound(stats.salesProfit), stats.salesProfit >= 0 ? .primary : .red)
                        stat("进货花了", Fmt.moneyRound(stats.purchaseAmount), .primary)
                    }

                    if stats.orderCount > 0 {
                        Text(String(format: "平均毛利率 %.0f%%",
                                    stats.salesAmount > 0 ? stats.salesProfit / stats.salesAmount * 100 : 0))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .card()
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section(header: Text("应收应付")) {
                NavigationLink(destination: ContactListView()) {
                    infoRow("客户欠我的", Fmt.moneyRound(store.totalReceivable), .accentColor)
                }
                NavigationLink(destination: ContactListView()) {
                    infoRow("我欠供应商的", Fmt.moneyRound(store.totalPayable), .orange)
                }
            }

            if !store.pendingDeliveryLogs.isEmpty {
                Section(header: Text("该发货了")) {
                    NavigationLink(destination: PendingDeliveryView()) {
                        HStack {
                            Text("还没发的货")
                            Spacer(minLength: 16)
                            Text("\(store.pendingDeliveryLogs.count) 单")
                                .font(.body.monospacedDigit())
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section(header: Text("\(span.title)卖得最好的")) {
                if topSellers.isEmpty {
                    Text("这段时间还没有出货")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(topSellers) { seller in
                        TopSellerRow(seller: seller, maxQuantity: topSellers.first?.quantity ?? 1)
                    }
                }
            }

            Section {
                NavigationLink(destination: LogsView()) {
                    Label("全部流水", systemImage: "list.bullet.rectangle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("生意")
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.callout.weight(.medium).monospacedDigit())
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundColor(color)
        }
    }
}

/// 畅销榜里的一行，带一条手绘的横条（iOS 14 没有官方图表，这里不引第三方库）。
struct TopSellerRow: View {
    let seller: TopSeller
    let maxQuantity: Int

    private var ratio: CGFloat {
        guard maxQuantity > 0 else { return 0 }
        return max(0.06, CGFloat(seller.quantity) / CGFloat(maxQuantity))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(seller.name)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(seller.quantity) 件 · \(Fmt.moneyRound(seller.amount))")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(UIColor.secondarySystemFill))
                Capsule()
                    .fill(Color.accentColor)
                    .scaleEffect(x: ratio, y: 1, anchor: .leading)
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
    }
}

/// 出库了还没发货的单子。
struct PendingDeliveryView: View {
    @EnvironmentObject private var store: Store

    private var pending: [StockLog] { store.pendingDeliveryLogs }

    var body: some View {
        List {
            if pending.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("没有待发货的单子")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                Section(header: Text("点一下标记成已发出")) {
                    ForEach(pending) { log in
                        Button {
                            store.markDelivered(logID: log.id)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(log.itemName)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(subtitle(log))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text("\(log.quantity) 件")
                                    .font(.callout.monospacedDigit())
                                    .foregroundColor(.orange)
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("待发货")
    }

    private func subtitle(_ log: StockLog) -> String {
        var parts = [Fmt.day(log.date) + " " + Fmt.time(log.date)]
        if let id = log.contactID, let contact = store.contact(id: id) {
            parts.append(contact.name)
        }
        if !log.note.isEmpty { parts.append(log.note) }
        return parts.joined(separator: " · ")
    }
}
