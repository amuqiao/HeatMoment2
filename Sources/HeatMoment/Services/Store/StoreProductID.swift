import Foundation

/// Pro 商品标识符，对齐 `Config/HeatMoment.storekit`（见 `docs/current/implementation-truth.md` §11.1）。
/// 两个商品是 OR 关系：任一有效即视为 Pro（月订阅未过期 或 终身买断已购）。
enum StoreProductID {
    /// 月度 Pro（自动续期订阅）。
    static let monthly = "com.heatmoment.pro.monthly"

    /// 终身 Pro（一次性买断）。**定价待产品最终确定**（见 docs/current/implementation-truth.md §11.1、`docs/plans/README.md`）：
    /// `Config/HeatMoment.storekit` 当前用占位价格 ¥6.00，ASC 正式上架前需重新核定，不代表最终定价。
    static let lifetime = "com.heatmoment.pro.lifetime"

    static var all: [String] { [monthly, lifetime] }
}
