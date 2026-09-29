import SwiftUI

/// 一个客户 / 供应商的账：欠多少、挂了哪些单、给了多少钱。
struct ContactDetailView: View {
    @EnvironmentObject private var store: Store
    let contactID: UUID

    private enum ActiveSheet: Identifiable {
        case edit
        case payment

        var id: String {
            switch self {
            case .edit: return "edit"
            case .payment: return "payment"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?

    private var contact: Contact? { store.contact(id: contactID) }
    private var amount: Double { store.balance(for: contactID) }

    var body: some View {
        Group {
            if let contact = contact {
                content(contact)
            } else {
                Text("这个往来对象已经被删掉了")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func content(_ contact: Contact) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(contact.kind == .customer ? "他还欠我" : "我还欠他")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(amount > 0.005 ? Fmt.money(amount) : "已结清")
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(amount > 0.005 ? (contact.kind == .customer ? .accentColor : .orange) : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    if amount < -0.005 {
                        Text("多收了 \(Fmt.money(-amount))，下次少收点或者退给他")
                            .font(.footnote)
                            .foregroundColor(.orange)
                    }

                    Button {
                        activeSheet = .payment
                    } label: {
                        Label(contact.kind == .customer ? "记一笔收款" : "记一笔付款",
                              systemImage: "yensign.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle())
                    .padding(.top, 4)
                }
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section(header: Text("基本信息")) {
                infoRow("类型", contact.kind.title)
                if !contact.phone.isEmpty {
                    infoRow("电话", contact.phone)
                }
                if !contact.note.isEmpty {
                    infoRow("备注", contact.note)
                }
            }

            Section(header: Text("挂在他名下的单")) {
                chargedList
            }

            Section(header: Text("收付款记录")) {
                paymentList
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(contact.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("编辑") { activeSheet = .edit }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        if let contact = contact {
            switch sheet {
            case .edit:
                ContactEditView(mode: .edit(contact))
                    .environmentObject(store)
            case .payment:
                PaymentSheet(contact: contact)
                    .environmentObject(store)
            }
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
    private var chargedList: some View {
        if store.logs(forContact: contactID).isEmpty {
            Text("还没有挂账的单")
                .font(.footnote)
                .foregroundColor(.secondary)
        } else {
            ForEach(store.logs(forContact: contactID)) { log in
                LogRow(log: log, showsTime: true)
            }
        }
    }

    @ViewBuilder
    private var paymentList: some View {
        if store.payments(forContact: contactID).isEmpty {
            Text("还没有收付款记录")
                .font(.footnote)
                .foregroundColor(.secondary)
        } else {
            ForEach(store.payments(forContact: contactID)) { payment in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "yensign")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Fmt.day(payment.date)) \(Fmt.time(payment.date))")
                            .font(.body)
                        if !payment.note.isEmpty {
                            Text(payment.note)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(Fmt.money(payment.amount))
                        .font(.callout.weight(.medium).monospacedDigit())
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// 记一笔收款 / 付款。
struct PaymentSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.presentationMode) private var presentationMode

    let contact: Contact

    @State private var amountText = ""
    @State private var note = ""

    private var isCustomer: Bool { contact.kind == .customer }
    private var amount: Double { Double(amountText) ?? 0 }
    private var owed: Double { store.balance(for: contact.id) }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text(isCustomer ? "他还欠我" : "我还欠他")
                            .foregroundColor(.secondary)
                        Spacer(minLength: 16)
                        Text(owed > 0.005 ? Fmt.money(owed) : "已结清")
                            .font(.body.monospacedDigit())
                            .foregroundColor(owed > 0.005 ? .orange : .secondary)
                    }
                }

                Section(header: Text(isCustomer ? "这次收了多少钱" : "这次付了多少钱")) {
                    FieldRow("金额") {
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.body.monospacedDigit())
                            .frame(minWidth: 80, alignment: .trailing)
                    }
                    if owed > 0.005 {
                        Button(isCustomer ? "收全部 \(Fmt.money(owed))" : "付全部 \(Fmt.money(owed))") {
                            amountText = String(format: "%.2f", owed)
                        }
                    }
                    FieldRow("备注") {
                        TextField("可选", text: $note)
                            .frame(minWidth: 80, alignment: .trailing)
                    }
                }

                Section {
                    HStack {
                        Text("记完还剩")
                            .foregroundColor(.secondary)
                        Spacer(minLength: 16)
                        Text(remainingText)
                            .font(.body.monospacedDigit())
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .navigationTitle(isCustomer ? "记收款" : "记付款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        store.addPayment(contactID: contact.id, amount: amount, note: note)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var remainingText: String {
        let left = owed - amount
        if left > 0.005 { return Fmt.money(left) }
        if left < -0.005 { return "多收 \(Fmt.money(-left))" }
        return "结清"
    }
}
