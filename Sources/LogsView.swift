import SwiftUI

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
                    Text("还没有出入库记录\n在商品详情页点「入库 / 出库」就会记下来")
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
        .navigationTitle("流水")
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

/// 一条流水。列表和详情页共用。
struct LogRow: View {
    let log: StockLog
    var showsTime: Bool = false

    private var tint: Color {
        log.kind == .inbound ? .accentColor : .orange
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: log.kind == .inbound ? "arrow.down" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
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
                    .font(.callout.weight(.medium))
                    .foregroundColor(tint)
                    .monospacedDigit()
                Text(Fmt.money(log.amount))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if showsTime { parts.append(Fmt.time(log.date)) }
        parts.append("\(log.kind.title) @ \(Fmt.money(log.unitPrice))")
        if !log.note.isEmpty { parts.append(log.note) }
        return parts.joined(separator: " · ")
    }
}
