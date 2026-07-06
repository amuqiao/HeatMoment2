import SwiftUI

/// 年度心情日期分布网格（见 `docs/design/04-screen-specs.md` §4.3/§4.12、
/// `docs/design/05-design-system.md` §5.7）：行=周几（周日~周六）、列=按周横向排布，
/// 底部月份标签；有记录的日期格用**当天最后一条时刻的心情色**着色（依公理1），无记录为空态格。
///
/// 复用于两处（05 §5.7「卡片1不承担定位时间轴功能...仅视觉范式相似」）：
/// - `YearHeatmapView`：`onSelectDay` 非 `nil`，点格驱动 `TimelineModel.heatmapFocusDate`；
/// - `MoodStatsView`：`onSelectDay` 为 `nil`，纯展示、不可交互、不接 `selectedDate`。
struct HeatmapGridView: View {
    let year: Int
    /// key 为 `dayOfYear`（1...365/366），value 为当天最后一条时刻的心情（见 `MomentRepository.moodByDay`）。
    let moodByDay: [Int: Mood]
    /// 当前定位选中的日期（仅首页热力图使用，供选中格描边高亮）。
    var selectedDate: Date?
    /// 点选「有记录」日期格的回调；`nil` 表示不可交互（`MoodStatsView` 用途）。
    var onSelectDay: ((Date) -> Void)?

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

    private var cells: [DayCell] {
        guard
            let startOfYear = Self.calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
            let range = Self.calendar.range(of: .day, in: .year, for: startOfYear)
        else { return [] }
        let startWeekday = Self.calendar.component(.weekday, from: startOfYear) // 1(周日)...7(周六)
        return range.compactMap { dayOfYear -> DayCell? in
            guard let date = Self.calendar.date(byAdding: .day, value: dayOfYear - 1, to: startOfYear) else {
                return nil
            }
            let weekday = Self.calendar.component(.weekday, from: date)
            let column = (dayOfYear - 1 + startWeekday - 1) / 7
            return DayCell(dayOfYear: dayOfYear, date: date, row: weekday - 1, column: column)
        }
    }

    private var columnCount: Int { (cells.map(\.column).max() ?? 0) + 1 }

    private var monthColumnLabels: [(month: Int, column: Int)] {
        var result: [(Int, Int)] = []
        var seenMonths = Set<Int>()
        for cell in cells.sorted(by: { $0.dayOfYear < $1.dayOfYear }) {
            let month = Self.calendar.component(.month, from: cell.date)
            if !seenMonths.contains(month) {
                seenMonths.insert(month)
                result.append((month, cell.column))
            }
        }
        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                grid
                monthLabelsRow
            }
            .padding(.horizontal, 4)
        }
    }

    private var grid: some View {
        let allCells = cells
        let rows = Array(repeating: GridItem(.fixed(Self.cellSize), spacing: Self.cellSpacing), count: 7)
        return LazyHGrid(rows: rows, spacing: Self.cellSpacing) {
            ForEach(0..<columnCount, id: \.self) { column in
                ForEach(0..<7, id: \.self) { row in
                    if let cell = allCells.first(where: { $0.column == column && $0.row == row }) {
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
        let isSelected = selectedDate.map { Self.calendar.isDate($0, inSameDayAs: cell.date) } ?? false
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(mood.map { MoodColorPalette.color(for: $0) } ?? theme.heatmapEmptyCell)
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
        guard let mood else { return "\(dateText)，没有记录" }
        guard onSelectDay != nil else { return "\(dateText)，有记录，当日心情\(mood.displayName)" }
        return "\(dateText)，有记录，当日心情\(mood.displayName)，点击定位"
    }

    private var monthLabelsRow: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: 14)
            ForEach(monthColumnLabels, id: \.column) { item in
                Text("\(item.month)月")
                    .font(.caption2)
                    .foregroundStyle(SemanticColor.secondaryText)
                    .offset(x: CGFloat(item.column) * (Self.cellSize + Self.cellSpacing))
            }
        }
        .frame(
            width: CGFloat(columnCount) * (Self.cellSize + Self.cellSpacing),
            height: 14,
            alignment: .leading
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
