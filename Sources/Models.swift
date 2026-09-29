import Foundation

/// 一件商品。库存数量以「当前值」为准，每次出入库都会改写它，同时留一条流水。
struct Item: Identifiable, Codable, Hashable {

    var id: UUID = UUID()
    var name: String = ""
    var category: String = ""
    /// 进价
    var cost: Double = 0
    /// 售价
    var price: Double = 0
    var stock: Int = 0
    var unit: String = "件"
    /// 库存少于等于这个数就算不足
    var lowStock: Int = 5
    var note: String = ""
    /// 商品照片的文件名，可以有多张；文件放在 Application Support/StockBook/Images 下
    var imageNames: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// 进货链接，一般是 1688 / 淘宝的商品页
    var sourceURL: String = ""
    /// 商品包装上自带的条码（69 码等），扫一下就能找到这件货
    var barcode: String = ""

    enum CodingKeys: String, CodingKey {
        case id, name, category, cost, price, stock, unit, lowStock, note
        case imageNames, createdAt, updatedAt, sourceURL, barcode
    }

    /// 1.2 及以前只存一张图，字段叫 imageName。留这个 key 专门用来读老数据。
    enum LegacyKeys: String, CodingKey {
        case imageName
    }

    var isLow: Bool { stock <= lowStock }
    var valueByPrice: Double { price * Double(stock) }
    var valueByCost: Double { cost * Double(stock) }
    var profit: Double { price - cost }
    var hasSourceLink: Bool { !sourceURL.trimmingCharacters(in: .whitespaces).isEmpty }
    /// 列表缩略图用第一张
    var coverImageName: String? { imageNames.first }
}

// 放在 extension 里手写解码器：这样既保留了容错解码（旧数据缺字段也能读），
// 又不会把编译器自动生成的 memberwise init 顶掉。
extension Item {
    /// 全部字段都用 decodeIfPresent —— 以后再加字段，旧版本的 data.json 依然能读出来，
    /// 不会因为缺一个字段导致整份数据读不出来。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        cost = try container.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        price = try container.decodeIfPresent(Double.self, forKey: .price) ?? 0
        stock = try container.decodeIfPresent(Int.self, forKey: .stock) ?? 0
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? "件"
        lowStock = try container.decodeIfPresent(Int.self, forKey: .lowStock) ?? 5
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        imageNames = try container.decodeIfPresent([String].self, forKey: .imageNames) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        barcode = try container.decodeIfPresent(String.self, forKey: .barcode) ?? ""

        // 老数据只有一张图存在 imageName 里，搬进新的数组
        if imageNames.isEmpty {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            if let old = try legacy.decodeIfPresent(String.self, forKey: .imageName), !old.isEmpty {
                imageNames = [old]
            }
        }
    }
}

/// 一条库存变动流水。
struct StockLog: Identifiable, Codable, Hashable {

    enum Kind: String, Codable, Hashable {
        case inbound
        case outbound
        case adjust

        var title: String {
            switch self {
            case .inbound: return "入库"
            case .outbound: return "出库"
            case .adjust: return "盘点"
            }
        }

        var sign: String {
            switch self {
            case .inbound: return "+"
            case .outbound: return "−"
            case .adjust: return "→"
            }
        }
    }

    var id: UUID = UUID()
    var itemID: UUID = UUID()
    /// 冗余存一份名字，商品被删掉以后流水还能看懂
    var itemName: String = ""
    var kind: Kind = .inbound
    /// 入库/出库是变动数量；盘点是盘完之后的实际数量
    var quantity: Int = 0
    var unitPrice: Double = 0
    /// 出货时顺手记下当时的进价，用来算真实毛利
    var costPrice: Double = 0
    var date: Date = Date()
    var note: String = ""
    /// 挂账给谁（客户或供应商）。nil 表示当场结清
    var contactID: UUID? = nil
    /// 货发了没，只对出库有意义
    var delivered: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, itemID, itemName, kind, quantity, unitPrice, costPrice
        case date, note, contactID, delivered
    }

    /// 这一单的金额
    var amount: Double { unitPrice * Double(quantity) }
    /// 这一单赚了多少（出库才有意义）
    var profit: Double { Double(quantity) * (unitPrice - costPrice) }
}

extension StockLog {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        itemID = try container.decodeIfPresent(UUID.self, forKey: .itemID) ?? UUID()
        itemName = try container.decodeIfPresent(String.self, forKey: .itemName) ?? ""
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .inbound
        quantity = try container.decodeIfPresent(Int.self, forKey: .quantity) ?? 0
        unitPrice = try container.decodeIfPresent(Double.self, forKey: .unitPrice) ?? 0
        costPrice = try container.decodeIfPresent(Double.self, forKey: .costPrice) ?? 0
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        contactID = try container.decodeIfPresent(UUID.self, forKey: .contactID)
        delivered = try container.decodeIfPresent(Bool.self, forKey: .delivered) ?? true
    }
}

/// 往来对象：客户（欠我钱）或供应商（我欠他钱）。
struct Contact: Identifiable, Codable, Hashable {

    enum Kind: String, Codable, Hashable {
        case customer
        case supplier

        var title: String {
            switch self {
            case .customer: return "客户"
            case .supplier: return "供应商"
            }
        }
    }

    var id: UUID = UUID()
    var name: String = ""
    var kind: Kind = .customer
    var phone: String = ""
    var note: String = ""
    var createdAt: Date = Date()
}

/// 一笔收款或付款，用来核销欠账。
struct Payment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var contactID: UUID = UUID()
    var amount: Double = 0
    var date: Date = Date()
    var note: String = ""
}

/// 落盘的整个数据库。
struct Database: Codable {
    var items: [Item] = []
    var logs: [StockLog] = []
    var contacts: [Contact] = []
    var payments: [Payment] = []
    var version: Int = 1

    enum CodingKeys: String, CodingKey {
        case items, logs, contacts, payments, version
    }
}

extension Database {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        logs = try container.decodeIfPresent([StockLog].self, forKey: .logs) ?? []
        contacts = try container.decodeIfPresent([Contact].self, forKey: .contacts) ?? []
        payments = try container.decodeIfPresent([Payment].self, forKey: .payments) ?? []
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }
}

/// 完整备份文件：商品 + 流水 + 往来 + 图片（图片转成 base64 塞在同一个文件里，方便微信直接发）。
struct BackupFile: Codable {
    static let magic = "stockbook-backup"

    var format: String = BackupFile.magic
    var version: Int = 1
    var exportedAt: Date = Date()
    var items: [Item] = []
    var logs: [StockLog] = []
    var contacts: [Contact] = []
    var payments: [Payment] = []
    /// 图片文件名 -> base64
    var images: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case format, version, exportedAt, items, logs, contacts, payments, images
    }
}

extension BackupFile {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? ""
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        logs = try container.decodeIfPresent([StockLog].self, forKey: .logs) ?? []
        contacts = try container.decodeIfPresent([Contact].self, forKey: .contacts) ?? []
        payments = try container.decodeIfPresent([Payment].self, forKey: .payments) ?? []
        images = try container.decodeIfPresent([String: String].self, forKey: .images) ?? [:]
    }
}

/// 一段时间内的经营数字。
struct PeriodStats {
    var salesAmount: Double = 0
    var salesProfit: Double = 0
    var purchaseAmount: Double = 0
    var soldCount: Int = 0
    var orderCount: Int = 0
}

/// 畅销排行里的一行。
struct TopSeller: Identifiable {
    var id: String { name }
    let name: String
    let quantity: Int
    let amount: Double
}
