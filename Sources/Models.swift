import Foundation

/// 一件商品。库存数量以「当前值」为准，每次出入库都会改写它，同时留一条流水。
///
/// 注意：这里手写了 init(from:)，全部字段都用 decodeIfPresent。
/// 以后再加字段时，旧版本的 data.json 依然能读出来，不会因为缺字段整份数据崩掉。
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
    /// 图片文件名，实际文件放在 Application Support/StockBook/Images 下
    var imageName: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// 进货链接，一般是 1688 / 淘宝的商品页
    var sourceURL: String = ""

    enum CodingKeys: String, CodingKey {
        case id, name, category, cost, price, stock, unit, lowStock, note
        case imageName, createdAt, updatedAt, sourceURL
    }

    init() {}

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
        imageName = try container.decodeIfPresent(String.self, forKey: .imageName)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
    }

    var isLow: Bool { stock <= lowStock }
    var valueByPrice: Double { price * Double(stock) }
    var valueByCost: Double { cost * Double(stock) }
    var profit: Double { price - cost }
    var hasSourceLink: Bool { !sourceURL.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// 一条出入库流水。
struct StockLog: Identifiable, Codable, Hashable {

    enum Kind: String, Codable, Hashable {
        case inbound
        case outbound

        var title: String {
            switch self {
            case .inbound: return "入库"
            case .outbound: return "出库"
            }
        }

        var sign: String {
            switch self {
            case .inbound: return "+"
            case .outbound: return "−"
            }
        }
    }

    var id: UUID = UUID()
    var itemID: UUID = UUID()
    /// 冗余存一份名字，商品被删掉以后流水还能看懂
    var itemName: String = ""
    var kind: Kind = .inbound
    var quantity: Int = 0
    var unitPrice: Double = 0
    var date: Date = Date()
    var note: String = ""

    var amount: Double { unitPrice * Double(quantity) }
}

/// 落盘的整个数据库。
struct Database: Codable {
    var items: [Item] = []
    var logs: [StockLog] = []
    var version: Int = 1
}

/// 完整备份文件：商品 + 流水 + 图片（图片转成 base64 塞在同一个文件里，方便微信直接发）。
struct BackupFile: Codable {
    static let magic = "stockbook-backup"

    var format: String = BackupFile.magic
    var version: Int = 1
    var exportedAt: Date = Date()
    var items: [Item] = []
    var logs: [StockLog] = []
    /// 图片文件名 -> base64
    var images: [String: String] = [:]
}
