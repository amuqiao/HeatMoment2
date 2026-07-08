import SwiftUI

/// 年度心情日期分布网格（见 `docs/design/04-screen-specs.md` §4.3/§4.12、
/// `docs/design/05-design-system.md` §5.7）：行=周几（周日~周六）、列=按周横向排布，
/// 底部月份标签；有记录的日期格用**当天最后一条时刻的心情色**着色（依公理1），无记录为空态格。
///
/// 复用于两处（05 §5.7「卡片1不承担定位时间轴功能...仅视觉范式相似」）：
/// - `YearHeatmapView`：`onSelectDay` / `onSelectMonth` 非 `nil`，点格/点月驱动时间 anchor；
/// - `MoodStatsView`：`onSelectDay` 为 `nil`，纯展示、不可交互、不接 `selectedDate`。
struct HeatmapGridView: View {
    let year: Int
    /// key 为 `dayOfYear`（1...365/366），value 为当天最后一条时刻的心情（见 `MomentRepository.moodByDay`）。
    let moodByDay: [Int: Mood]
    /// 当前定位选中的日期（仅首页热力图使用，供选中格描边高亮）。
    var selectedDate: Date?
    var selectedGranularity: HeatmapAnchorGranularity?
    /// 点选「有记录」日期格的回调；`nil` 表示不可交互（`MoodStatsView` 用途）。
    var onSelectDay: ((Date) -> Void)?
    /// 点选月份标签的回调；`nil` 表示月份标签仅展示。
    var onSelectMonth: ((Date) -> Void)?

    @Environment(ThemeManager.self) private var theme

    private static let cellSize: CGFloat = 14
    private static let cellSpacing: CGFloat = 3
    private static let calendar = Calendar.current

    private struct DayCell {
        let dayOfYear: Int
        let date: Date
        let row: Int
        let column: Int
    }

    private struct MonthColumnRange {
        let month: Int
        let startColumn: Int
        let endColumn: Int
    }

    /// 一次性预计算的网格布局（阶段5 review 修复：此前 `cells` 是计算属性，被
    /// `grid`/`columnCount`/`monthColumnLabels` 三处各自重复触发重算，且 `grid` 内每格用
    /// `allCells.first(where:)` 做 O(n) 线性扫描——年内约371个网格位 × 约180+条记录，
    /// 改为 `init` 时算一次，按 `column*7+row` 建字典索引，三处复用同一份结果、格子命中 O(1)）。
    private struct GridLayout {
        let cellsByPosition: [Int: DayCell]
        let columnCount: Int
        let monthColumnLabels: [(month: Int, column: Int)]
        let monthColumnRanges: [MonthColumnRange]
    }

    private let layout: GridLayout
    private let monthsWithRecords: Set<Int>

    init(
        year: Int, moodByDay: [Int: Mood], selectedDate: Date? = nil,
        selectedGranularity: HeatmapAnchorGranularity? = nil,
        onSelectDay: ((Date) -> Void)? = nil,
        onSelectMonth: ((Date) -> Void)? = nil
    ) {
        self.year = year
        self.moodByDay = moodByDay
        self.selectedDate = selectedDate
        self.selectedGranularity = selectedGranularity
        self.onSelectDay = onSelectDay
        self.onSelectMonth = onSelectMonth
        let layout = Self.makeLayout(year: year)
        self.layout = layout
        self.monthsWithRecords = Self.monthsWithRecords(in: layout, moodByDay: moodByDay)
    }

    /// 对任何合法年份，`year`1月1日的起始日期与年内天数区间不应合成失败；一旦失败即为不可预期的
    /// 日历计算异常，`preconditionFailure` 崩溃暴露，不静默返回空网格（见 CLAUDE.md 快速失败铁律）。
    /// 年内单日日期合成理论上同样不应失败——若真的出现，用 `assertionFailure` 暴露后跳过该日，
    /// 不让个别日期异常拖垮整个网格渲染。
    private static func makeLayout(year: Int) -> GridLayout {
        guard let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        else {
            preconditionFailure("年度热力图起始日期合成失败，年份：\(year)")
        }
        guard let range = calendar.range(of: .day, in: .year, for: startOfYear) else {
            preconditionFailure("年内天数区间计算失败，年份：\(year)")
        }
        let startWeekday = calendar.component(.weekday, from: startOfYear)  // 1(周日)...7(周六)

        var cellsByPosition: [Int: DayCell] = [:]
        var monthColumnLabels: [(month: Int, column: Int)] = []
        var seenMonths = Set<Int>()
        var maxColumn = 0

        for dayOfYear in range {
            guard let date = calendar.date(byAdding: .day, value: dayOfYear - 1, to: startOfYear)
            else {
                assertionFailure("年内单日日期合成失败：年份=\(year)，dayOfYear=\(dayOfYear)")
                continue
            }
            let weekday = calendar.component(.weekday, from: date)
            let row = weekday - 1
            let column = (dayOfYear - 1 + startWeekday - 1) / 7
            cellsByPosition[column * 7 + row] = DayCell(
                dayOfYear: dayOfYear, date: date, row: row, column: column)
            maxColumn = max(maxColumn, column)

            let month = calendar.component(.month, from: date)
            if !seenMonths.contains(month) {
                seenMonths.insert(month)
                monthColumnLabels.append((month, column))
            }
        }

        let monthColumnRanges = monthColumnLabels.enumerated().map { index, item in
            let endColumn =
                index + 1 < monthColumnLabels.count
                ? monthColumnLabels[index + 1].column - 1
                : maxColumn
            return MonthColumnRange(month: item.month, startColumn: item.column, endColumn: endColumn)
        }

        return GridLayout(
            cellsByPosition: cellsByPosition, columnCount: maxColumn + 1,
            monthColumnLabels: monthColumnLabels,
            monthColumnRanges: monthColumnRanges)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                gridWithMonthSelection
                monthLabelsRow
            }
            .padding(.horizontal, 4)
        }
    }

    private var gridWithMonthSelection: some View {
        ZStack(alignment: .topLeading) {
            grid
            selectedMonthOverlay
                .allowsHitTesting(false)
        }
        .frame(
            width: CGFloat(layout.columnCount) * Self.columnStride - Self.cellSpacing,
            height: Self.gridHeight,
            alignment: .topLeading
        )
    }

    private var grid: some View {
        let rows = Array(
            repeating: GridItem(.fixed(Self.cellSize), spacing: Self.cellSpacing), count: 7)
        return LazyHGrid(rows: rows, spacing: Self.cellSpacing) {
            ForEach(0..<layout.columnCount, id: \.self) { column in
                ForEach(0..<7, id: \.self) { row in
                    if let cell = layout.cellsByPosition[column * 7 + row] {
                        dayCellView(cell)
                    } else {
                        Color.clear.frame(width: Self.cellSize, height: Self.cellSize)
                    }
                }
            }
        }
    }

    private func dayCellView(_ cell: DayCell) -> some View {
        let mood = moodByDay[cell.dayOfYear]
        let isSelected =
            selectedGranularity == .day
            && (selectedDate.map { Self.calendar.isDate($0, inSameDayAs: cell.date) } ?? false)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(mood.map { theme.moodColor($0) } ?? theme.heatmapEmptyCell)
            .frame(width: Self.cellSize, height: Self.cellSize)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(theme.accent, lineWidth: isSelected ? 2 : 0)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard mood != nil, let onSelectDay else { return }
                onSelectDay(cell.date)
            }
            .accessibilityLabel(Text(accessibilityLabel(for: cell, mood: mood)))
            .accessibilityAddTraits(mood != nil && onSelectDay != nil ? .isButton : [])
            .accessibilityIdentifier("heatmapDayCell-\(year)-\(cell.dayOfYear)")
    }

    private func accessibilityLabel(for cell: DayCell, mood: Mood?) -> String {
        let dateText = Self.dayFormatter.string(from: cell.date)
        guard let mood else {
            return LanguagePreference.localizedString("\(dateText)，没有记录")
        }
        guard onSelectDay != nil else {
            return LanguagePreference.localizedString("\(dateText)，有记录，当日心情\(mood.displayName)")
        }
        return LanguagePreference.localizedString("\(dateText)，有记录，当日心情\(mood.displayName)，点击定位")
    }

    private var monthLabelsRow: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: 32)
            ForEach(layout.monthColumnLabels, id: \.column) { item in
                monthLabel(item)
                    .offset(x: CGFloat(item.column) * Self.columnStride)
            }
        }
        .frame(
            width: CGFloat(layout.columnCount) * Self.columnStride,
            height: 32,
            alignment: .leading
        )
    }

    @ViewBuilder
    private func monthLabel(_ item: (month: Int, column: Int)) -> some View {
        let label = Text("\(item.month)月")
            .font(.caption2)
            .foregroundStyle(theme.secondaryText)

        if monthsWithRecords.contains(item.month),
           let onSelectMonth,
           let monthDate = Self.monthDate(year: year, month: item.month) {
            Button {
                onSelectMonth(monthDate)
            } label: {
                label
                    .frame(minWidth: 44, minHeight: 32, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(Text("\(item.month)月，点击定位"))
            .accessibilityIdentifier("heatmapMonthLabel-\(year)-\(item.month)")
        } else {
            label
        }
    }

    @ViewBuilder
    private var selectedMonthOverlay: some View {
        if selectedGranularity == .month,
           let selectedDate,
           Self.calendar.component(.year, from: selectedDate) == year {
            let selectedMonth = Self.calendar.component(.month, from: selectedDate)
            if let range = layout.monthColumnRanges.first(where: { $0.month == selectedMonth }) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(theme.selectedMonthFill)
                    .frame(
                        width: CGFloat(range.endColumn - range.startColumn + 1) * Self.columnStride - Self.cellSpacing,
                        height: Self.gridHeight
                    )
                    .offset(x: CGFloat(range.startColumn) * Self.columnStride)
                    .accessibilityHidden(true)
            }
        }
    }

    private static var columnStride: CGFloat { cellSize + cellSpacing }
    private static var gridHeight: CGFloat { cellSize * 7 + cellSpacing * 6 }

    private static func monthDate(year: Int, month: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    private static func monthsWithRecords(in layout: GridLayout, moodByDay: [Int: Mood]) -> Set<Int> {
        Set(
            layout.cellsByPosition.values.compactMap { cell in
                guard moodByDay[cell.dayOfYear] != nil else { return nil }
                return calendar.component(.month, from: cell.date)
            }
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

#Preview {
    HeatmapGridView(year: 2026, moodByDay: [1: .happy, 2: .sad, 40: .motivated])
        .environment(ThemeManager())
        .padding()
        .background(Color.black)
}
