import SwiftUI

/// 日期/时间就地选择用的 `Calendar` 合成工具：两个就近浮窗各自只编辑发生时间的一部分
/// （日期 / 时:分），合成时保留不可见组件不变（见 `docs/current/implementation-truth.md` §4.8）。
enum OccurredAtComposer {
    /// 用 `date` 的年/月/日 + `timeSource` 的时/分/秒合成新的 `Date`。
    static func mergingDate(
        _ date: Date,
        timeFrom timeSource: Date,
        calendar: Calendar = .current
    ) -> Date {
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: timeSource)
        var merged = DateComponents()
        merged.year = dateComponents.year
        merged.month = dateComponents.month
        merged.day = dateComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = timeComponents.second
        // 年/月/日 + 时/分/秒 组件几乎必然可合成；失败视为不可恢复的编程错误、debug 立即暴露，
        // 不静默吞成默认值（见 CLAUDE.md 快速失败）。release 兜回原值仅为极端边界的最后保护。
        guard let composed = calendar.date(from: merged) else {
            assertionFailure("发生时间合成失败：\(merged)")
            return date
        }
        return composed
    }

    /// 用 `dateSource` 的年/月/日/秒 + `time` 的时/分合成新的 `Date`。
    static func mergingTime(
        _ time: Date,
        dateFrom dateSource: Date,
        calendar: Calendar = .current
    ) -> Date {
        let dateComponents = calendar.dateComponents(
            [.year, .month, .day, .second],
            from: dateSource
        )
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var merged = DateComponents()
        merged.year = dateComponents.year
        merged.month = dateComponents.month
        merged.day = dateComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = dateComponents.second
        guard let composed = calendar.date(from: merged) else {
            assertionFailure("发生时间合成失败：\(merged)")
            return dateSource
        }
        return composed
    }
}

/// 发生时间·日期就近浮窗（见 docs/current/implementation-truth.md §4.8）：graphical 日历，支持选择任意
/// 过去/未来日期以支持补记；选择后立即用 `Calendar` 合成回填 `occurredAt`（保留原时:分:秒），
/// 无需额外确认按钮。
struct DatePickerSheetView: View {
    @Binding var occurredAt: Date

    @Environment(ThemeManager.self) private var theme

    private var dateBinding: Binding<Date> {
        Binding(
            get: { occurredAt },
            set: { occurredAt = OccurredAtComposer.mergingDate($0, timeFrom: occurredAt) }
        )
    }

    var body: some View {
        DatePicker("发生日期", selection: dateBinding, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .tint(theme.accent)
            .labelsHidden()
            .padding()
            .frame(minWidth: 320)
            .background(theme.sheetBackground)
            .accessibilityIdentifier("editorDatePicker")
    }
}

/// 发生时间·时间就近浮窗（见 docs/current/implementation-truth.md §4.8）：时/分双滚轮，选择后立即用
/// `Calendar` 合成回填 `occurredAt`（保留原年月日和不可见秒），无需额外确认按钮。
struct TimePickerSheetView: View {
    @Binding var occurredAt: Date

    private var timeBinding: Binding<Date> {
        Binding(
            get: { occurredAt },
            set: { occurredAt = OccurredAtComposer.mergingTime($0, dateFrom: occurredAt) }
        )
    }

    var body: some View {
        DatePicker("发生时间", selection: timeBinding, displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding()
            .accessibilityIdentifier("editorTimePicker")
    }
}
