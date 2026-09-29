import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    /// 上次备份时间，用来提醒别忘了备份
    @AppStorage("lastBackupAt") private var lastBackupAt: Double = 0

    private enum AlertKind: Identifiable {
        case clearConfirm
        case importDone(String)
        case failed(String)

        var id: String {
            switch self {
            case .clearConfirm: return "clear"
            case .importDone(let text): return "done-\(text)"
            case .failed(let text): return "failed-\(text)"
            }
        }
    }

    @State private var shareItem: ShareItem?
    @State private var alert: AlertKind?
    @State private var showImporter = false
    @State private var pendingImport: URL?
    @State private var showImportChoice = false

    var body: some View {
        List {
            backupSection
            csvSection
            dataSection
            dangerSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json],
                      onCompletion: handlePickedFile)
        .actionSheet(isPresented: $showImportChoice) {
            ActionSheet(title: Text("怎么恢复？"),
                        message: Text(pendingImport?.lastPathComponent ?? ""),
                        buttons: [
                            .default(Text("合并进来（保留现有数据）")) { runImport(.merge) },
                            .destructive(Text("完全覆盖（清空后恢复）")) { runImport(.replace) },
                            .cancel(Text("取消")) { pendingImport = nil }
                        ])
        }
        .alert(item: $alert) { kind in
            switch kind {
            case .clearConfirm:
                return Alert(title: Text("确定清空所有流水？"),
                             message: Text("商品和库存数量不受影响，只是删掉出入库记录。"),
                             primaryButton: .destructive(Text("清空")) { store.clearLogs() },
                             secondaryButton: .cancel(Text("取消")))
            case .importDone(let text):
                return Alert(title: Text("恢复完成"),
                             message: Text(text),
                             dismissButton: .default(Text("好")))
            case .failed(let text):
                return Alert(title: Text("没成功"),
                             message: Text(text),
                             dismissButton: .default(Text("好")))
            }
        }
    }

    // MARK: - 各区块

    private var backupSection: some View {
        Section(header: Text("备份与恢复")) {
            Button {
                guard let url = store.exportBackup() else { return }
                lastBackupAt = Date().timeIntervalSince1970
                shareItem = ShareItem(url: url)
            } label: {
                Label("导出完整备份", systemImage: "square.and.arrow.up")
            }

            Button {
                showImporter = true
            } label: {
                Label("从备份恢复", systemImage: "square.and.arrow.down")
            }

            HStack {
                Text("上次备份")
                Spacer(minLength: 16)
                Text(backupStatusText)
                    .foregroundColor(lastBackupAt > 0 ? .secondary : .orange)
            }

            Text("备份文件里含全部商品、照片和流水。导出后发到微信「文件传输助手」或存网盘；换手机时把文件传回来，点「从备份恢复」。")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var csvSection: some View {
        Section(header: Text("导出表格（对账用）")) {
            Button {
                if let url = store.exportItemsCSV() {
                    shareItem = ShareItem(url: url)
                }
            } label: {
                Label("导出库存表 CSV", systemImage: "tablecells")
            }

            Button {
                if let url = store.exportLogsCSV() {
                    shareItem = ShareItem(url: url)
                }
            } label: {
                Label("导出流水 CSV", systemImage: "tablecells")
            }

            Button {
                if let url = store.exportContactsCSV() {
                    shareItem = ShareItem(url: url)
                }
            } label: {
                Label("导出往来欠款 CSV", systemImage: "tablecells")
            }

            Text("CSV 用 Excel 打开看，中文不会乱码。但它只是一张表，不能导回 App；要恢复数据请用上面的完整备份。")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var dataSection: some View {
        Section(header: Text("本机数据")) {
            infoRow("商品", "\(store.items.count) 项")
            infoRow("库存件数", "\(store.totalStockCount)")
            infoRow("流水", "\(store.logs.count) 条")
            infoRow("照片占用", store.imageFolderSize)
        }
    }

    private var dangerSection: some View {
        Section(header: Text("危险操作")) {
            Button("清空所有流水") { alert = .clearConfirm }
                .foregroundColor(.red)
        }
    }

    private var aboutSection: some View {
        Section(header: Text("关于")) {
            infoRow("版本", "1.5.1")
            Text("数据只存在这台手机上，不联网、不上传。")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 辅助

    private var backupStatusText: String {
        guard lastBackupAt > 0 else { return "从没备份过" }
        let date = Date(timeIntervalSince1970: lastBackupAt)
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case ..<1: return "今天"
        case 1: return "昨天"
        default: return "\(days) 天前"
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

    private func handlePickedFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            pendingImport = url
            showImportChoice = true
        case .failure(let error):
            alert = .failed("选文件失败：\(error.localizedDescription)")
        }
    }

    private func runImport(_ mode: Store.ImportMode) {
        guard let url = pendingImport else { return }
        pendingImport = nil
        do {
            let summary = try store.importBackup(from: url, mode: mode)
            alert = .importDone(summary)
        } catch let error as LocalizedError {
            alert = .failed(error.errorDescription ?? "导入失败。")
        } catch {
            alert = .failed("导入失败：\(error.localizedDescription)")
        }
    }
}
