import Foundation
import SwiftUI
import UIKit

/// 全部数据都在本机：JSON 存商品和流水，商品图片按文件存。
final class Store: ObservableObject {

    @Published private(set) var items: [Item] = []
    @Published private(set) var logs: [StockLog] = []
    /// 出错时给界面弹一句提示
    @Published var errorMessage: String?

    private let fileManager = FileManager.default
    private let dbURL: URL
    private let imagesURL: URL
    private var imageCache: [String: UIImage] = [:]

    // MARK: - 生命周期

    init() {
        let base = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StockBook", isDirectory: true)
        imagesURL = base.appendingPathComponent("Images", isDirectory: true)
        dbURL = base.appendingPathComponent("data.json")
        try? fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: dbURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let db = try decoder.decode(Database.self, from: data)
            items = db.items
            logs = db.logs
        } catch {
            errorMessage = "数据文件读不出来，可能已损坏。请到「设置」里导出一份备份。"
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(Database(items: items, logs: logs))
            try data.write(to: dbURL, options: .atomic)
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 总览数据

    var totalValueByPrice: Double { items.reduce(0) { $0 + $1.valueByPrice } }
    var totalValueByCost: Double { items.reduce(0) { $0 + $1.valueByCost } }
    var totalStockCount: Int { items.reduce(0) { $0 + $1.stock } }
    var lowStockItems: [Item] { items.filter { $0.isLow } }

    /// 用过的分类，给列表页的筛选条用
    var categories: [String] {
        var seen = Set<String>()
        for item in items {
            let name = item.category.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { seen.insert(name) }
        }
        return seen.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var todayOutAmount: Double {
        let calendar = Calendar.current
        return logs
            .filter { $0.kind == .outbound && calendar.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    var todayOutCount: Int {
        let calendar = Calendar.current
        return logs
            .filter { $0.kind == .outbound && calendar.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.quantity }
    }

    func logs(for itemID: UUID) -> [StockLog] {
        logs.filter { $0.itemID == itemID }.sorted { $0.date > $1.date }
    }

    // MARK: - 商品

    func item(id: UUID) -> Item? {
        items.first { $0.id == id }
    }

    func addItem(_ item: Item, imageData: Data?) {
        var newItem = item
        newItem.imageName = imageData.flatMap { storeImage($0) }
        newItem.createdAt = Date()
        newItem.updatedAt = Date()
        items.insert(newItem, at: 0)
        if newItem.stock > 0 {
            logs.insert(StockLog(itemID: newItem.id,
                                 itemName: newItem.name,
                                 kind: .inbound,
                                 quantity: newItem.stock,
                                 unitPrice: newItem.cost,
                                 note: "新建商品"),
                        at: 0)
        }
        save()
    }

    func updateItem(_ item: Item, imageData: Data?, removeImage: Bool) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.updatedAt = Date()

        if let data = imageData {
            if let old = items[index].imageName { deleteImage(old) }
            updated.imageName = storeImage(data)
        } else if removeImage {
            if let old = items[index].imageName { deleteImage(old) }
            updated.imageName = nil
        } else {
            updated.imageName = items[index].imageName
        }

        items[index] = updated
        save()
    }

    func deleteItems(_ ids: [UUID]) {
        for id in ids {
            if let item = item(id: id), let name = item.imageName {
                deleteImage(name)
            }
        }
        items.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: - 出入库

    func record(itemID: UUID, kind: StockLog.Kind, quantity: Int, unitPrice: Double, note: String) {
        guard quantity > 0, let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = items[index]
        switch kind {
        case .inbound:
            item.stock += quantity
        case .outbound:
            item.stock -= quantity
        }
        item.updatedAt = Date()
        items[index] = item
        logs.insert(StockLog(itemID: item.id,
                             itemName: item.name,
                             kind: kind,
                             quantity: quantity,
                             unitPrice: unitPrice,
                             date: Date(),
                             note: note),
                    at: 0)
        save()
    }

    func clearLogs() {
        logs.removeAll()
        save()
    }

    // MARK: - 完整备份 / 恢复

    enum ImportMode {
        /// 只补进备份里有、本机没有的（同 id 比 updatedAt，取新的）
        case merge
        /// 清空后整个换成备份里的
        case replace
    }

    enum StoreError: LocalizedError {
        case notABackup
        case unreadable

        var errorDescription: String? {
            switch self {
            case .notABackup: return "这个文件不是库存本的备份文件，请选对文件。"
            case .unreadable: return "文件打不开，可能没下载完。"
            }
        }
    }

    /// 把商品、流水、图片（转 base64）打包成一个 json 文件，方便微信直接发。
    func exportBackup() -> URL? {
        var encodedImages: [String: String] = [:]
        for item in items {
            guard let name = item.imageName, encodedImages[name] == nil else { continue }
            guard let data = try? Data(contentsOf: imagesURL.appendingPathComponent(name)) else { continue }
            encodedImages[name] = data.base64EncodedString()
        }

        let backup = BackupFile(items: items, logs: logs, images: encodedImages)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(backup)
            let name = "库存本备份-\(Self.fileStamp(Date())).json"
            let url = fileManager.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = "导出备份失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 恢复备份。返回值是给用户看的一句话总结。
    @discardableResult
    func importBackup(from url: URL, mode: ImportMode) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw StoreError.unreadable }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(BackupFile.self, from: data),
              backup.format == BackupFile.magic else {
            throw StoreError.notABackup
        }

        // 图片先落盘，商品引用的是文件名
        for (name, base64) in backup.images {
            guard let imageData = Data(base64Encoded: base64) else { continue }
            try? imageData.write(to: imagesURL.appendingPathComponent(name), options: .atomic)
        }

        var touchedItems = 0
        var touchedLogs = 0

        switch mode {
        case .replace:
            items = backup.items
            logs = backup.logs
            touchedItems = backup.items.count
            touchedLogs = backup.logs.count

        case .merge:
            var byID: [UUID: Item] = [:]
            for item in items { byID[item.id] = item }
            for incoming in backup.items {
                if let current = byID[incoming.id] {
                    if incoming.updatedAt > current.updatedAt {
                        byID[incoming.id] = incoming
                        touchedItems += 1
                    }
                } else {
                    byID[incoming.id] = incoming
                    touchedItems += 1
                }
            }
            items = Array(byID.values)

            var knownLogIDs = Set(logs.map { $0.id })
            for log in backup.logs where !knownLogIDs.contains(log.id) {
                logs.append(log)
                knownLogIDs.insert(log.id)
                touchedLogs += 1
            }
        }

        imageCache.removeAll()
        save()

        switch mode {
        case .replace:
            return "已恢复 \(items.count) 件商品、\(logs.count) 条流水。"
        case .merge:
            return "新增或更新 \(touchedItems) 件商品、\(touchedLogs) 条流水，现在共 \(items.count) 件商品。"
        }
    }

    private static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: date)
    }

    // MARK: - 图片

    private func storeImage(_ data: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: imagesURL.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            errorMessage = "图片保存失败：\(error.localizedDescription)"
            return nil
        }
    }

    func image(named name: String?) -> UIImage? {
        guard let name = name else { return nil }
        if let cached = imageCache[name] { return cached }
        let url = imagesURL.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        imageCache[name] = image
        return image
    }

    private func deleteImage(_ name: String) {
        imageCache.removeValue(forKey: name)
        try? fileManager.removeItem(at: imagesURL.appendingPathComponent(name))
    }

    /// 图片目录占用空间，设置页里显示
    var imageFolderSize: String {
        let size = (try? fileManager.contentsOfDirectory(at: imagesURL, includingPropertiesForKeys: [.fileSizeKey]))?
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0, +) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    // MARK: - 导出

    func exportItemsCSV() -> URL? {
        var rows = ["名称,分类,进价,售价,库存,单位,货值(按售价),货值(按进价),低库存阈值,备注"]
        for item in items {
            let cells = [item.name,
                         item.category,
                         Self.plain(item.cost),
                         Self.plain(item.price),
                         String(item.stock),
                         item.unit,
                         Self.plain(item.valueByPrice),
                         Self.plain(item.valueByCost),
                         String(item.lowStock),
                         item.note]
            rows.append(cells.map(Self.csvCell).joined(separator: ","))
        }
        return writeCSV(rows.joined(separator: "\n"), fileName: "库存表.csv")
    }

    func exportLogsCSV() -> URL? {
        var rows = ["日期,类型,商品,数量,单价,金额,备注"]
        for log in logs.sorted(by: { $0.date > $1.date }) {
            let cells = [Self.stamp(log.date),
                         log.kind.title,
                         log.itemName,
                         String(log.quantity),
                         Self.plain(log.unitPrice),
                         Self.plain(log.amount),
                         log.note]
            rows.append(cells.map(Self.csvCell).joined(separator: ","))
        }
        return writeCSV(rows.joined(separator: "\n"), fileName: "流水.csv")
    }

    private func writeCSV(_ text: String, fileName: String) -> URL? {
        let url = fileManager.temporaryDirectory.appendingPathComponent(fileName)
        // Excel 认 UTF-8 需要 BOM，否则中文乱码
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(text.utf8))
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    private static func csvCell(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return text
    }

    private static func plain(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
