import SwiftUI

/// 入库 / 出库的填写面板。入库默认带出进价，出库默认带出售价。
struct StockSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.presentationMode) private var presentationMode

    let itemID: UUID
    let kind: StockLog.Kind

    @State private var quantityText = ""
    @State private var priceText = ""
    @State private var note = ""

    private var item: Item? { store.item(id: itemID) }
    private var quantity: Int { Int(quantityText) ?? 0 }
    private var price: Double { Double(priceText) ?? 0 }

    private var overdraw: Bool {
        guard let item = item else { return false }
        return kind == .outbound && quantity > item.stock
    }

    private var title: String {
        kind == .inbound ? "入库" : "出库"
    }

    var body: some View {
        NavigationView {
            Form {
                if let item = item {
                    Section {
                        HStack {
                            Text(item.name)
                                .font(.headline)
                            Spacer(minLength: 16)
                            Text("存 \(item.stock) \(item.unit)")
                                .font(.body.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }

                    Section(header: Text(kind == .inbound ? "这次进了多少" : "这次卖了多少")) {
                        FieldRow("数量") {
                            TextField("0", text: $quantityText)
                                .keyboardType(.numberPad)
                                .font(.body.monospacedDigit())
                                .frame(minWidth: 80, alignment: .trailing)
                        }
                        FieldRow(kind == .inbound ? "进价" : "售价") {
                            TextField("0.00", text: $priceText)
                                .keyboardType(.decimalPad)
                                .font(.body.monospacedDigit())
                                .frame(minWidth: 80, alignment: .trailing)
                        }
                        FieldRow("备注") {
                            TextField("可选", text: $note)
                                .frame(minWidth: 80, alignment: .trailing)
                        }
                    }

                    Section {
                        HStack {
                            Text("合计")
                                .foregroundColor(.secondary)
                            Spacer(minLength: 16)
                            Text(Fmt.money(Double(quantity) * price))
                                .font(.headline.monospacedDigit())
                                .foregroundColor(.accentColor)
                        }
                        if overdraw {
                            Label("库存只有 \(item.stock)，不够出", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundColor(.orange)
                        }
                    }
                } else {
                    Text("商品已删除")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { commit() }
                        .disabled(quantity <= 0 || overdraw)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear(perform: prefill)
    }

    private func prefill() {
        guard let item = item else { return }
        quantityText = ""
        priceText = String(format: "%.2f", kind == .inbound ? item.cost : item.price)
        note = ""
    }

    private func commit() {
        guard let item = item, quantity > 0, !overdraw else { return }
        store.record(itemID: item.id,
                     kind: kind,
                     quantity: quantity,
                     unitPrice: price,
                     note: note)
        presentationMode.wrappedValue.dismiss()
    }
}
