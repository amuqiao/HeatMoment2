import SwiftUI

struct ExportView: View {
    let exportService: any ExportServicing

    @Environment(ThemeManager.self) private var theme

    @State private var selectedFormat: ExportFormat = .markdown
    @State private var includePhotos = true
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var exportDateBounds: ExportDateBounds?
    @State private var didLoadDateBounds = false
    @State private var exportResult: ExportResult?
    @State private var exportFailure: FailureState?
    @State private var isExporting = false
    @State private var exportAttemptID = 0
    @State private var exportTask: Task<Void, Never>?
    #if DEBUG
        @State private var didForceDateBoundsFailure = false
    #endif

    init(exportService: any ExportServicing) {
        self.exportService = exportService
        let defaultRange = ExportDateRangeDefaults.recentThreeDays()
        _startDate = State(initialValue: defaultRange.start)
        _endDate = State(initialValue: defaultRange.end)
    }

    var body: some View {
        TaskPageScrollView(accessibilityIdentifier: "exportScrollView") {
            summarySection
            scopeSection
            contentSection
            formatSection
            generateButton
            if let exportResult {
                ResultSection(result: exportResult)
            }
            if let exportFailure {
                FailureSection(
                    failure: exportFailure,
                    isExporting: isExporting,
                    retry: retry
                )
            }
        }
        .appSheetDetailNavigationChrome("阅读副本导出")
        .themedTaskContainer(theme)
        .onChange(of: selectedFormat) { _, _ in
            clearExportState()
        }
        .onChange(of: includePhotos) { _, _ in
            clearExportState()
        }
        .onChange(of: startDate) { _, _ in
            clearExportState()
        }
        .onChange(of: endDate) { _, _ in
            clearExportState()
        }
        .task {
            try? exportService.cleanupTemporaryExports()
            await loadDateBoundsIfNeeded()
        }
        .onDisappear {
            cancelExport()
        }
    }

    private var summarySection: some View {
        TaskSurfaceSection(accessibilityIdentifier: "exportSummarySection") {
            VStack(alignment: .leading, spacing: 8) {
                Text("阅读副本只用于查看、编辑或分享，不会改变当前内容，也不能导回恢复资料库。")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.primaryText)
                    .accessibilityIdentifier("exportReadonlyText")
                Text("需要重装或换设备恢复数据时，请使用“备份与恢复”里的完整备份包。")
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("exportScopeText")
            }
            .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
            .padding(.vertical, 12)
        }
    }

    private var scopeSection: some View {
        TaskSurfaceSection(title: "副本范围", accessibilityIdentifier: "exportScopeSection") {
            VStack(spacing: 0) {
                exportDatePickerRow(
                    title: "开始日期",
                    date: $startDate,
                    identifier: "exportStartDatePicker"
                )

                TaskSurfaceSeparator()
                exportDatePickerRow(
                    title: "结束日期",
                    date: $endDate,
                    identifier: "exportEndDatePicker"
                )

                if let validationMessage {
                    TaskSurfaceSeparator()
                    Text(validationMessage)
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("exportValidationText")
                }
            }
        }
    }

    private func exportDatePickerRow(
        title: String,
        date: Binding<Date>,
        identifier: String
    ) -> some View {
        TaskSurfaceRow {
            Text(title)
                .foregroundStyle(theme.secondaryText)
                .accessibilityHidden(true)
        } trailing: {
            DatePicker(title, selection: date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(theme.accent)
                .accessibilityIdentifier(identifier)
        }
        .disabled(isExporting || exportDateBounds == nil)
    }

    private var contentSection: some View {
        TaskSurfaceSection(title: "内容", accessibilityIdentifier: "exportContentSection") {
            Toggle(isOn: $includePhotos) {
                Label("包含照片", systemImage: "photo")
                    .foregroundStyle(theme.primaryText)
            }
            .tint(theme.accent)
            .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
            .frame(minHeight: TaskSurfaceMetrics.rowMinHeight)
            .disabled(isExporting || exportDateBounds == nil)
            .accessibilityIdentifier("exportIncludePhotosToggle")
        }
    }

    private var formatSection: some View {
        TaskSurfaceSection(title: "格式", accessibilityIdentifier: "exportFormatSection") {
            Picker("副本格式", selection: $selectedFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
            .padding(.vertical, 12)
            .disabled(isExporting)
            .accessibilityIdentifier("exportFormatPicker")
        }
    }

    private var generateButton: some View {
        Button {
            exportSelectedFormat()
        } label: {
            Label {
                Text(isExporting ? selectedFormat.exportingTitle : selectedFormat.generateTitle)
            } icon: {
                Image(systemName: selectedFormat.systemImage)
            }
            .font(AppTypography.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(TaskSurfaceMetrics.panelPadding)
            .foregroundStyle(theme.onAccentText)
            .background(
                RoundedRectangle(
                    cornerRadius: TaskSurfaceMetrics.panelCornerRadius,
                    style: .continuous
                )
                .fill(isExporting ? theme.accentDisabledFill : theme.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(isExporting || makeRequest() == nil)
        .accessibilityIdentifier("exportGenerateButton")
    }

    private func exportSelectedFormat() {
        guard !isExporting, let request = makeRequest() else { return }
        exportTask?.cancel()
        isExporting = true
        exportResult = nil
        exportFailure = nil
        exportAttemptID += 1
        let attemptID = exportAttemptID
        exportTask = Task {
            defer {
                isExporting = false
                exportTask = nil
            }
            do {
                exportResult = try await exportService.export(request: request)
            } catch is CancellationError {
                exportResult = nil
            } catch {
                exportFailure = FailureState(
                    attemptID: attemptID,
                    message: failureMessage(for: error, format: request.format),
                    retryAction: .export
                )
            }
        }
    }

    private func makeRequest() -> ExportRequest? {
        guard exportDateBounds != nil else { return nil }
        guard dateRangeIsValid else { return nil }
        return ExportRequest(
            scope: .dateRange(start: startDate, end: endDate),
            format: selectedFormat,
            includePhotos: includePhotos
        )
    }

    private func loadDateBoundsIfNeeded() async {
        guard !didLoadDateBounds else { return }
        didLoadDateBounds = true
        do {
            #if DEBUG
                if UITestSupport.wantsExportDateBoundsFailOnce {
                    if !didForceDateBoundsFailure {
                        didForceDateBoundsFailure = true
                        throw DateBoundsLoadError()
                    }
                }
            #endif
            let bounds = try await exportService.exportDateBounds()
            exportDateBounds = bounds
            exportFailure = nil
            if bounds != nil {
                let defaultRange = ExportDateRangeDefaults.recentThreeDays()
                startDate = defaultRange.start
                endDate = defaultRange.end
            }
        } catch {
            exportFailure = FailureState(
                attemptID: exportAttemptID,
                message: "导出数据读取失败，请重试。",
                retryAction: .loadDateBounds
            )
        }
    }

    private func reloadDateBounds() async {
        didLoadDateBounds = false
        exportDateBounds = nil
        exportFailure = nil
        await loadDateBoundsIfNeeded()
    }
}

private extension ExportView {
    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        isExporting = false
    }

    func retry(_ failure: ExportView.FailureState) {
        switch failure.retryAction {
        case .export:
            exportSelectedFormat()
        case .loadDateBounds:
            Task { await reloadDateBounds() }
        }
    }

    func clearExportState() {
        exportResult = nil
        exportFailure = nil
    }

    var validationMessage: String? {
        if exportFailure?.retryAction == .loadDateBounds { return nil }
        guard exportDateBounds != nil else {
            return "暂无可导出的时刻。"
        }
        if !dateRangeIsValid {
            return "开始日期不能晚于结束日期。"
        }
        return nil
    }

    var dateRangeIsValid: Bool {
        Calendar.current.startOfDay(for: startDate) <= Calendar.current.startOfDay(for: endDate)
    }

    func failureMessage(for error: Error, format: ExportFormat) -> String {
        if case ExportError.emptyExport = error {
            return "所选日期内没有可导出的时刻，请调整后重试。"
        }
        if case ExportError.invalidDateRange = error {
            return "开始日期不能晚于结束日期。"
        }
        return "\(format.displayName) 导出失败，请重试。"
    }
}

#Preview {
    ExportView(exportService: PreviewExportService())
        .environment(ThemeManager())
}
