import SwiftUI

struct ContactEditView: View {

    enum Mode {
        case create
        case edit(Contact)
    }

    @EnvironmentObject private var store: Store
    @Environment(\.presentationMode) private var presentationMode
    let mode: Mode

    @State private var name: String
    @State private var kind: Contact.Kind
    @State private var phone: String
    @State private var note: String

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _kind = State(initialValue: .customer)
            _phone = State(initialValue: "")
            _note = State(initialValue: "")
        case .edit(let contact):
            _name = State(initialValue: contact.name)
            _kind = State(initialValue: contact.kind)
            _phone = State(initialValue: contact.phone)
            _note = State(initialValue: contact.note)
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("名字 / 店名", text: $name)

                    Picker("类型", selection: $kind) {
                        Text("客户（他欠我钱）").tag(Contact.Kind.customer)
                        Text("供应商（我欠他钱）").tag(Contact.Kind.supplier)
                    }

                    TextField("电话（可选）", text: $phone)
                        .keyboardType(.phonePad)
                }

                Section(header: Text("备注")) {
                    TextField("可选", text: $note)
                }

                Section {
                    Text("出货时选「记在这个客户账上」，这一单就变成他的欠款；他给钱了到他的页面记一笔收款。进货挂供应商账上同理。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(isCreating ? "新增往来对象" : "编辑往来对象")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        switch mode {
        case .create:
            var contact = Contact()
            contact.name = trimmedName
            contact.kind = kind
            contact.phone = phone.trimmingCharacters(in: .whitespaces)
            contact.note = note
            store.addContact(contact)
        case .edit(let original):
            var contact = original
            contact.name = trimmedName
            contact.kind = kind
            contact.phone = phone.trimmingCharacters(in: .whitespaces)
            contact.note = note
            store.updateContact(contact)
        }
        presentationMode.wrappedValue.dismiss()
    }
}
