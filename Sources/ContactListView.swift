import SwiftUI

/// 往来：客户和供应商，以及各自欠了多少钱。
struct ContactListView: View {
    @EnvironmentObject private var store: Store
    @State private var showAdd = false
    @State private var pendingDelete: Contact?
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            if !store.contacts.isEmpty {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        total("客户欠我", store.totalReceivable, .accentColor)
                        total("我欠供应商", store.totalPayable, .orange)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }

            if store.contacts.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("还没有客户或供应商\n点右上角 + 加一个\n\n以后出货可以挂他账上，欠多少一目了然")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                }
            } else {
                if !store.contacts(kind: .customer).isEmpty {
                    Section(header: Text("客户 · 他欠我钱")) {
                        ForEach(store.contacts(kind: .customer)) { contact in
                            NavigationLink(destination: ContactDetailView(contactID: contact.id)) {
                                ContactRow(contact: contact)
                            }
                        }
                        .onDelete { offsets in askDelete(offsets, in: store.contacts(kind: .customer)) }
                    }
                }
                if !store.contacts(kind: .supplier).isEmpty {
                    Section(header: Text("供应商 · 我欠他钱")) {
                        ForEach(store.contacts(kind: .supplier)) { contact in
                            NavigationLink(destination: ContactDetailView(contactID: contact.id)) {
                                ContactRow(contact: contact)
                            }
                        }
                        .onDelete { offsets in askDelete(offsets, in: store.contacts(kind: .supplier)) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("往来")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            ContactEditView(mode: .create)
                .environmentObject(store)
        }
        .actionSheet(isPresented: $showDeleteConfirm) {
            ActionSheet(title: Text("删掉「\(pendingDelete?.name ?? "")」？"),
                        message: Text("他的收付款记录会一起删掉，历史流水里的挂账对象会变成空白。"),
                        buttons: [
                            .destructive(Text("删除")) {
                                if let contact = pendingDelete {
                                    store.deleteContact(contact.id)
                                }
                                pendingDelete = nil
                            },
                            .cancel(Text("取消")) { pendingDelete = nil }
                        ])
        }
    }

    private func total(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(Fmt.moneyRound(value))
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func askDelete(_ offsets: IndexSet, in list: [Contact]) {
        guard let index = offsets.first, index < list.count else { return }
        pendingDelete = list[index]
        showDeleteConfirm = true
    }
}

struct ContactRow: View {
    @EnvironmentObject private var store: Store
    let contact: Contact

    private var amount: Double { store.balance(for: contact.id) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: contact.kind == .customer ? "person.crop.circle" : "building.2")
                .font(.system(size: 22))
                .foregroundColor(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .font(.body)
                    .lineLimit(1)
                Text(contact.phone.isEmpty ? contact.kind.title : contact.phone)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if amount > 0.005 {
                    Text(Fmt.money(amount))
                        .font(.callout.weight(.medium).monospacedDigit())
                        .foregroundColor(contact.kind == .customer ? .accentColor : .orange)
                    Text(contact.kind == .customer ? "欠我" : "我欠")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("已结清")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
