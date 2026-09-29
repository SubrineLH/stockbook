import SwiftUI

/// 金额和日期的统一格式，别在各处各写一遍。
enum Fmt {

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    /// 单价：两位小数
    static func money(_ value: Double) -> String {
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "¥" + (formatter.string(from: NSNumber(value: value)) ?? "0.00")
    }

    /// 汇总：不要小数，一眼看得清
    static func moneyRound(_ value: Double) -> String {
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return "¥" + (formatter.string(from: NSNumber(value: value)) ?? "0")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func day(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? "今天" : dayFormatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}

/// 白底圆角卡片，全局统一。
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// 表单里「左边标题 右边输入」的一行
struct FieldRow<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            content
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 80, alignment: .trailing)
        }
    }
}

/// 商品缩略图：有图显示图，没图显示一个箱子
struct ItemThumbnail: View {
    @EnvironmentObject var store: Store
    let item: Item
    var side: CGFloat = 44

    var body: some View {
        Group {
            if let image = store.image(named: item.imageName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(UIColor.secondarySystemFill)
                    Image(systemName: "shippingbox")
                        .font(.system(size: side * 0.4))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
