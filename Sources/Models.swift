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
    /// 图片文件名，实际文件放在 Application Support/StockBook/Images 下
    var imageName: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var isLow: Bool { stock <= lowStock }
    var valueByPrice: Double { price * Double(stock) }
    var valueByCost: Double { cost * Double(stock) }
    var profit: Double { price - cost }
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
