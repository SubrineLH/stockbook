import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var shareItem: ShareItem?
    @State private var showClearConfirm = false

    var body: some View {
        List {
            Section(header: Text("导出备份")) {
                Button {
                    if let url = store.exportItemsCSV() {
                        shareItem = ShareItem(url: url)
                    }
                } label: {
                    Label("导出库存表（CSV）", systemImage: "square.and.arrow.up")
                }

                Button {
                    if let url = store.exportLogsCSV() {
                        shareItem = ShareItem(url: url)
                    }
                } label: {
                    Label("导出流水（CSV）", systemImage: "square.and.arrow.up")
                }

                Text("表格可以发到微信再传到电脑，用 Excel 打开中文不会乱码。换手机前记得先导一份。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("本机数据")) {
                infoRow("商品", "\(store.items.count) 项")
                infoRow("库存件数", "\(store.totalStockCount)")
                infoRow("流水", "\(store.logs.count) 条")
                infoRow("照片占用", store.imageFolderSize)
            }

            Section(header: Text("危险操作")) {
                Button("清空所有流水") { showClearConfirm = true }
                    .foregroundColor(.red)
            }

            Section(header: Text("关于")) {
                infoRow("版本", "1.0.0")
                Text("数据只存在这台手机上，不联网、不上传。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert(isPresented: $showClearConfirm) {
            Alert(title: Text("确定清空所有流水？"),
                  message: Text("商品和库存数量不受影响，只是删掉出入库记录。"),
                  primaryButton: .destructive(Text("清空")) { store.clearLogs() },
                  secondaryButton: .cancel(Text("取消")))
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }
}
