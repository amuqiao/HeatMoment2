import Foundation

/// 情绪展示名：正式多语言由 `Localizable.xcstrings` String Catalog 承载
/// （见 docs/current/implementation-truth.md §7 `Localization/`、阶段 7 D 本地化）。`Mood.localizedNameKey`
/// （见 `Mood.swift`）是最终 i18n key，本属性经 `LanguagePreference.localizedString(_:)`
/// 按当前语言偏好解析出展示文本。
///
/// **用 `LanguagePreference.localizedString` 而非直接 `Text(LocalizedStringKey)`**：本属性
/// 到处以 `String`（而非 `Text`）形式被消费——既有直接 `Text(mood.displayName)`（verbatim
/// 渲染，靠属性自身返回值已是目标语言文本），也有作为另一段插值文本的参数（如
/// `"\(mood.emoji) \(mood.displayName)"`、无障碍朗读拼句）——后一种用法要求它必须是已解析
/// 完成的 `String`，不能是尚待 View 环境解析的 `LocalizedStringKey`，故在此同步读取
/// `LanguagePreference.current` 而非依赖 `.environment(\.locale)` 树形传播（二者共享同一份
/// 真相源，详见 `LanguagePreference` 头部说明）。
///
/// **实现取舍**：本应作为 `Mood.swift` 内的一个新增计算属性（与 `emoji`/`localizedNameKey`
/// 相邻），但当前环境对该文件的写权限异常（`EPERM`，本会话对已存在/已入库文件的写操作
/// 普遍被拒绝，只能创建新文件），故改用同类型的独立扩展文件承载，功能等价、不改变
/// `Mood` 的持久化契约。
extension Mood {
    var displayName: String {
        LanguagePreference.localizedString(localizedNameKey)
    }
}
