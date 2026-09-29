import SwiftUI

/// 入库 / 出库的填写面板。
/// 入库默认带出进价，出库默认带出售价；都可以挂到某个客户或供应商的账上。
struct StockSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.presentationMode) private var presentationMode

    let itemID: UUID
    let kind: StockLog.Kind

    @State private var quantityText = ""
    @State private var priceText = ""
    @State private var note = ""
    @State private var contactID: UUID?
    @State private var delivered = true

    private var item: Item? { store.item(id: itemID) }
    private var quantity: Int { Int(quantityText) ?? 0 }
    private var price: Double { Double(priceText) ?? 0 }
    private var isInbound: Bool { kind == .inbound }

    private var overdraw: Bool {
        guard let item = item else { return false }
        return !isInbound && quantity > item.stock
    }

    private var candidates: [Contact] {
        store.contacts(kind: isInbound ? .supplier : .customer)
    }

    private var title: String { isInbound ? "入库" : "出库" }

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

                    Section(header: Text(isInbound ? "这次进了多少" : "这次卖了多少")) {
                        FieldRow("数量") {
                            TextField("0", text: $quantityText)
                                .keyboardType(.numberPad)
                                .font(.body.monospacedDigit())
                                .frame(minWidth: 80, alignment: .trailing)
                        }
                        FieldRow(isInbound ? "进价" : "售价") {
                            TextField("0.00", text: $priceText)
                                .keyboardType(.decimalPad)
                                .font(.body.monospacedDigit())
                                .frame(minWidth: 80, alignment: .trailing)
                        }
                    }

                    Section(header: Text("账怎么算")) {
                        if candidates.isEmpty {
                            Text(isInbound
                                 ? "还没有供应商。到「往来」页加一个，进货就能挂他账上。"
                                 : "还没有客户。到「往来」页加一个，出货就能挂他账上。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else {
                            Picker("记在谁账上", selection: $contactID) {
                                Text("当场结清").tag(UUID?.none)
                                ForEach(candidates) { contact in
                                    Text(contact.name).tag(UUID?.some(contact.id))
                                }
                            }
                        }

                        if !isInbound {
                            Toggle("货已经发出", isOn: $delivered)
                            if !delivered {
                                Text("先记成「待发货」，在「生意」页可以随时标记已发。")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
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
                        if isInbound && price > 0 && price != item.cost {
                            Text("填了新进价，保存后这个商品的进价会更新成 \(Fmt.money(price))，后面算毛利才准。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section(header: Text("备注")) {
                        TextField("可选", text: $note)
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
        priceText = String(format: "%.2f", isInbound ? item.cost : item.price)
        note = ""
        contactID = nil
        delivered = true
    }

    private func commit() {
        guard let item = item, quantity > 0, !overdraw else { return }
        store.record(itemID: item.id,
                     kind: kind,
                     quantity: quantity,
                     unitPrice: price,
                     note: note,
                     contactID: contactID,
                     delivered: delivered)
        presentationMode.wrappedValue.dismiss()
    }
}

/// 盘点：把账面数字改成实际数出来的数字。
struct CountSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.presentationMode) private var presentationMode

    let itemID: UUID

    @State private var countText = ""
    @State private var note = ""

    private var item: Item? { store.item(id: itemID) }
    private var counted: Int? { Int(countText) }
    private var difference: Int? {
        guard let counted = counted, let item = item else { return nil }
        return counted - item.stock
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
                            Text("账面 \(item.stock) \(item.unit)")
                                .font(.body.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }

                    Section(header: Text("实际数到多少")) {
                        FieldRow("实际数量") {
                            TextField("0", text: $countText)
                                .keyboardType(.numberPad)
                                .font(.body.monospacedDigit())
                                .frame(minWidth: 80, alignment: .trailing)
                        }

                        if let difference = difference {
                            if difference == 0 {
                                Text("跟账面一样，不用调。")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            } else if difference > 0 {
                                Text("比账面多 \(difference) \(item.unit)，保存后库存会调高。")
                                    .font(.footnote)
                                    .foregroundColor(.orange)
                            } else {
                                Text("比账面少 \(-difference) \(item.unit)，保存后库存会调低（破损/记错/被拿走）。")
                                    .font(.footnote)
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    Section(header: Text("原因")) {
                        TextField("可选，比如 破损 / 丢失 / 记错", text: $note)
                    }
                } else {
                    Text("商品已删除")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("盘点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        store.adjust(itemID: itemID, countedStock: counted ?? 0, note: note)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(counted == nil)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear(perform: prefill)
    }

    private func prefill() {
        guard countText.isEmpty, let item = item else { return }
        countText = String(item.stock)
    }
}
