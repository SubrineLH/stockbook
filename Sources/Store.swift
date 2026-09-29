import Foundation
import SwiftUI
import UIKit

/// 全部数据都在本机：JSON 存商品、流水、往来，商品图片按文件存。
final class Store: ObservableObject {

    @Published private(set) var items: [Item] = []
    @Published private(set) var logs: [StockLog] = []
    @Published private(set) var contacts: [Contact] = []
    @Published private(set) var payments: [Payment] = []
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
            contacts = db.contacts
            payments = db.payments
        } catch {
            errorMessage = "数据文件读不出来，可能已损坏。请到「设置」里导出一份备份。"
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let db = Database(items: items,
                              logs: logs,
                              contacts: contacts,
                              payments: payments)
            let data = try encoder.encode(db)
            try data.write(to: dbURL, options: .atomic)
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 库存总览

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

    func logs(for itemID: UUID) -> [StockLog] {
        logs.filter { $0.itemID == itemID }.sorted { $0.date > $1.date }
    }

    /// 出库了但还没发货的，排老的在前，先发先出
    var pendingDeliveryLogs: [StockLog] {
        logs.filter { $0.kind == .outbound && !$0.delivered }
            .sorted { $0.date < $1.date }
    }

    // MARK: - 商品

    func item(id: UUID) -> Item? {
        items.first { $0.id == id }
    }

    /// 按包装上的条码找货
    func item(barcode: String) -> Item? {
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        return items.first { $0.barcode == code }
    }

    func addItem(_ item: Item, images: [Data]) {
        var newItem = item
        newItem.imageNames = images.compactMap { storeImage($0) }
        newItem.createdAt = Date()
        newItem.updatedAt = Date()
        items.insert(newItem, at: 0)
        if newItem.stock > 0 {
            var log = StockLog()
            log.itemID = newItem.id
            log.itemName = newItem.name
            log.kind = .inbound
            log.quantity = newItem.stock
            log.unitPrice = newItem.cost
            log.note = "新建商品"
            logs.insert(log, at: 0)
        }
        save()
    }

    /// keepImageNames 是用户保留下来的旧照片，没在里面的一律从磁盘删掉
    func updateItem(_ item: Item, newImages: [Data], keepImageNames: [String]) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.updatedAt = Date()

        for old in items[index].imageNames where !keepImageNames.contains(old) {
            deleteImage(old)
        }

        var finalNames = keepImageNames
        for data in newImages {
            if let name = storeImage(data) { finalNames.append(name) }
        }
        updated.imageNames = finalNames

        items[index] = updated
        save()
    }

    func deleteItems(_ ids: [UUID]) {
        for id in ids {
            if let item = item(id: id) {
                for name in item.imageNames { deleteImage(name) }
            }
        }
        items.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: - 出入库 / 盘点

    func record(itemID: UUID,
                kind: StockLog.Kind,
                quantity: Int,
                unitPrice: Double,
                note: String,
                contactID: UUID?,
                delivered: Bool) {
        guard quantity > 0, kind != .adjust,
              let index = items.firstIndex(where: { $0.id == itemID }) else { return }

        var item = items[index]

        var log = StockLog()
        log.itemID = item.id
        log.itemName = item.name
        log.kind = kind
        log.quantity = quantity
        log.unitPrice = unitPrice
        log.date = Date()
        log.note = note
        log.contactID = contactID
        log.delivered = kind == .outbound ? delivered : true

        switch kind {
        case .inbound:
            item.stock += quantity
            // 最后一次进价法：进了新价就顺手更新商品进价，不然后面算毛利是错的
            if unitPrice > 0 { item.cost = unitPrice }
            log.costPrice = 0
        case .outbound:
            item.stock -= quantity
            // 记下出货那一刻的进价，这才是这单的真实成本
            log.costPrice = item.cost
        case .adjust:
            return
        }

        item.updatedAt = Date()
        items[index] = item
        logs.insert(log, at: 0)
        save()
    }

    /// 盘点：把库存直接改成实际数到的数量，并留一条盘点流水。
    func adjust(itemID: UUID, countedStock: Int, note: String) {
        guard countedStock >= 0, let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = items[index]
        let before = item.stock
        guard before != countedStock else { return }

        item.stock = countedStock
        item.updatedAt = Date()
        items[index] = item

        var log = StockLog()
        log.itemID = item.id
        log.itemName = item.name
        log.kind = .adjust
        log.quantity = countedStock
        log.unitPrice = 0
        log.costPrice = 0
        log.note = note.isEmpty ? "盘前 \(before)" : "盘前 \(before) · \(note)"
        logs.insert(log, at: 0)
        save()
    }

    func markDelivered(logID: UUID) {
        guard let index = logs.firstIndex(where: { $0.id == logID }) else { return }
        logs[index].delivered = true
        save()
    }

    func clearLogs() {
        logs.removeAll()
        save()
    }

    // MARK: - 往来（客户 / 供应商）

    func contact(id: UUID) -> Contact? {
        contacts.first { $0.id == id }
    }

    func contacts(kind: Contact.Kind) -> [Contact] {
        contacts
            .filter { $0.kind == kind }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func addContact(_ contact: Contact) {
        var newContact = contact
        newContact.createdAt = Date()
        contacts.insert(newContact, at: 0)
        save()
    }

    func updateContact(_ contact: Contact) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[index] = contact
        save()
    }

    func deleteContact(_ id: UUID) {
        contacts.removeAll { $0.id == id }
        payments.removeAll { $0.contactID == id }
        for index in logs.indices where logs[index].contactID == id {
            logs[index].contactID = nil
        }
        save()
    }

    func addPayment(contactID: UUID, amount: Double, note: String) {
        guard amount > 0 else { return }
        payments.insert(Payment(contactID: contactID,
                                amount: amount,
                                date: Date(),
                                note: note),
                        at: 0)
        save()
    }

    /// 一个人的账：正数 = 对方欠我（客户）／我欠他（供应商）。
    func balance(for contactID: UUID) -> Double {
        let charged = logs
            .filter { $0.contactID == contactID && $0.kind != .adjust }
            .reduce(0) { $0 + $1.amount }
        let paid = payments
            .filter { $0.contactID == contactID }
            .reduce(0) { $0 + $1.amount }
        return charged - paid
    }

    /// 客户总共欠我多少
    var totalReceivable: Double {
        var total = 0.0
        for contact in contacts where contact.kind == .customer {
            total += max(0, balance(for: contact.id))
        }
        return total
    }

    /// 我总共欠供应商多少
    var totalPayable: Double {
        var total = 0.0
        for contact in contacts where contact.kind == .supplier {
            total += max(0, balance(for: contact.id))
        }
        return total
    }

    func logs(forContact contactID: UUID) -> [StockLog] {
        logs.filter { $0.contactID == contactID }.sorted { $0.date > $1.date }
    }

    func payments(forContact contactID: UUID) -> [Payment] {
        payments.filter { $0.contactID == contactID }.sorted { $0.date > $1.date }
    }

    // MARK: - 经营统计

    var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }

    var startOfMonth: Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month], from: Date())
        return calendar.date(from: parts) ?? startOfToday
    }

    var startOfYear: Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year], from: Date())
        return calendar.date(from: parts) ?? startOfToday
    }

    func stats(since: Date) -> PeriodStats {
        var result = PeriodStats()
        for log in logs where log.date >= since {
            switch log.kind {
            case .inbound:
                result.purchaseAmount += log.amount
            case .outbound:
                result.salesAmount += log.amount
                result.salesProfit += log.profit
                result.soldCount += log.quantity
                result.orderCount += 1
            case .adjust:
                break
            }
        }
        return result
    }

    func topSellers(since: Date, limit: Int) -> [TopSeller] {
        var quantityByName: [String: Int] = [:]
        var amountByName: [String: Double] = [:]
        for log in logs where log.kind == .outbound && log.date >= since {
            quantityByName[log.itemName, default: 0] += log.quantity
            amountByName[log.itemName, default: 0] += log.amount
        }
        var rows: [TopSeller] = []
        for (name, quantity) in quantityByName {
            rows.append(TopSeller(name: name,
                                  quantity: quantity,
                                  amount: amountByName[name] ?? 0))
        }
        return Array(rows.sorted { $0.quantity > $1.quantity }.prefix(limit))
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

    /// 把商品、流水、往来、图片（转 base64）打包成一个 json 文件，方便微信直接发。
    func exportBackup() -> URL? {
        var encodedImages: [String: String] = [:]
        for item in items {
            for name in item.imageNames where encodedImages[name] == nil {
                guard let data = try? Data(contentsOf: imagesURL.appendingPathComponent(name)) else { continue }
                encodedImages[name] = data.base64EncodedString()
            }
        }

        let backup = BackupFile(items: items,
                                logs: logs,
                                contacts: contacts,
                                payments: payments,
                                images: encodedImages)
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
        var touchedContacts = 0
        var touchedPayments = 0

        switch mode {
        case .replace:
            items = backup.items
            logs = backup.logs
            contacts = backup.contacts
            payments = backup.payments
            touchedItems = backup.items.count
            touchedLogs = backup.logs.count
            touchedContacts = backup.contacts.count
            touchedPayments = backup.payments.count

        case .merge:
            var byItemID: [UUID: Item] = [:]
            for item in items { byItemID[item.id] = item }
            for incoming in backup.items {
                if let current = byItemID[incoming.id] {
                    if incoming.updatedAt > current.updatedAt {
                        byItemID[incoming.id] = incoming
                        touchedItems += 1
                    }
                } else {
                    byItemID[incoming.id] = incoming
                    touchedItems += 1
                }
            }
            items = Array(byItemID.values)

            var knownLogIDs = Set(logs.map { $0.id })
            for log in backup.logs where !knownLogIDs.contains(log.id) {
                logs.append(log)
                knownLogIDs.insert(log.id)
                touchedLogs += 1
            }

            var knownContactIDs = Set(contacts.map { $0.id })
            for contact in backup.contacts where !knownContactIDs.contains(contact.id) {
                contacts.append(contact)
                knownContactIDs.insert(contact.id)
                touchedContacts += 1
            }

            var knownPaymentIDs = Set(payments.map { $0.id })
            for payment in backup.payments where !knownPaymentIDs.contains(payment.id) {
                payments.append(payment)
                knownPaymentIDs.insert(payment.id)
                touchedPayments += 1
            }
        }

        imageCache.removeAll()
        save()

        switch mode {
        case .replace:
            return "已恢复 \(items.count) 件商品、\(logs.count) 条流水、\(contacts.count) 个往来对象。"
        case .merge:
            return "新增或更新 \(touchedItems) 件商品、\(touchedLogs) 条流水、\(touchedContacts) 个往来对象、\(touchedPayments) 笔收付款。"
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

    // MARK: - 导出 CSV

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
        var rows = ["日期,类型,商品,数量,单价,金额,挂账对象,已发货,备注"]
        for log in logs.sorted(by: { $0.date > $1.date }) {
            let who = log.contactID.flatMap { contact(id: $0)?.name } ?? ""
            let cells = [Self.stamp(log.date),
                         log.kind.title,
                         log.itemName,
                         String(log.quantity),
                         Self.plain(log.unitPrice),
                         Self.plain(log.amount),
                         who,
                         log.kind == .outbound ? (log.delivered ? "是" : "否") : "",
                         log.note]
            rows.append(cells.map(Self.csvCell).joined(separator: ","))
        }
        return writeCSV(rows.joined(separator: "\n"), fileName: "流水.csv")
    }

    func exportContactsCSV() -> URL? {
        var rows = ["名称,类型,电话,欠款(正数=客户欠我/我欠供应商),备注"]
        let sorted = contacts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for contact in sorted {
            let cells = [contact.name,
                         contact.kind.title,
                         contact.phone,
                         Self.plain(balance(for: contact.id)),
                         contact.note]
            rows.append(cells.map(Self.csvCell).joined(separator: ","))
        }
        return writeCSV(rows.joined(separator: "\n"), fileName: "往来欠款.csv")
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
