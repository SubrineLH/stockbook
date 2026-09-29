import SwiftUI

/// 全部流水，按天分组。从「生意」页点进来。
struct LogsView: View {
    @EnvironmentObject private var store: Store

    private struct DayGroup: Identifiable {
        let id: Date
        let title: String
        let logs: [StockLog]
    }

    private var groups: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.logs) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            DayGroup(id: day,
                     title: Fmt.day(day),
                     logs: grouped[day, default: []].sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        List {
            if groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("还没有出入库记录\n在商品详情页点「入库 / 出库 / 盘点」就会记下来")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                ForEach(groups) { group in
                    Section(header: dayHeader(group)) {
                        ForEach(group.logs) { log in
                            LogRow(log: log, showsTime: true)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("全部流水")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dayHeader(_ group: DayGroup) -> some View {
        HStack {
            Text(group.title)
            Spacer()
            Text(netText(group.logs))
        }
    }

    private func netText(_ logs: [StockLog]) -> String {
        let inboundValue = logs.filter { $0.kind == .inbound }.reduce(0) { $0 + $1.amount }
        let outboundValue = logs.filter { $0.kind == .outbound }.reduce(0) { $0 + $1.amount }
        return "进 \(Fmt.moneyRound(inboundValue)) · 出 \(Fmt.moneyRound(outboundValue))"
    }
}

/// 一条流水。详情页、往来页、流水页共用。
struct LogRow: View {
    @EnvironmentObject private var store: Store
    let log: StockLog
    var showsTime: Bool = false

    private var isInbound: Bool { log.kind == .inbound }

    private var tint: Color {
        switch log.kind {
        case .inbound: return .accentColor
        case .outbound: return .orange
        case .adjust: return .gray
        }
    }

    private var iconName: String {
        switch log.kind {
        case .inbound: return "arrow.down"
        case .outbound: return "arrow.up"
        case .adjust: return "arrow.clockwise"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(log.itemName)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(log.kind.sign)\(log.quantity)")
                    .font(.callout.weight(.medium).monospacedDigit())
                    .foregroundColor(tint)
                if log.kind != .adjust {
                    Text(Fmt.money(log.amount))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if showsTime { parts.append(Fmt.time(log.date)) }

        if log.kind == .adjust {
            parts.append("盘完 \(log.quantity)")
        } else {
            parts.append("\(log.kind.title) @ \(Fmt.money(log.unitPrice))")
        }

        if let id = log.contactID, let contact = store.contact(id: id) {
            parts.append(isInbound ? "欠 \(contact.name)" : contact.name)
        }
        if log.kind == .outbound && !log.delivered {
            parts.append("待发货")
        }
        if !log.note.isEmpty {
            parts.append(log.note)
        }
        return parts.joined(separator: " · ")
    }
}
