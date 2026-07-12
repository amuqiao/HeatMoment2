import SwiftUI

struct ExportView: View {
    @Environment(CanonicalLibraryService.self) private var canonicalService
    @Environment(ThemeManager.self) private var theme

    @State private var selectedFormat: ExportFormat = .markdown
    @State private var selectedScopeMode: ScopeMode = .all
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
        .settingsDetailNavigationChrome("导出")
        .themedTaskContainer(theme)
        .onChange(of: selectedFormat) { _, _ in
            clearExportState()
        }
        .onChange(of: selectedScopeMode) { _, _ in
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
            try? ExportService.cleanupTemporaryExports()
            await loadDateBoundsIfNeeded()
        }
        .onDisappear {
            cancelExport()
        }
    }

    private var summarySection: some View {
        TaskSurfaceSection(accessibilityIdentifier: "exportSummarySection") {
            VStack(alignment: .leading, spacing: 8) {
                Text("导出会生成副本，不会改变当前数据，也不会影响 iCloud 同步。")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.primaryText)
                    .accessibilityIdentifier("exportReadonlyText")
                Text("当前支持 Markdown 和 PDF；Markdown 会保留相对照片目录，PDF 会把照片嵌入文档。")
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("exportScopeText")
            }
            .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
            .padding(.vertical, 12)
        }
    }

    private var scopeSection: some View {
        TaskSurfaceSection(title: "范围", accessibilityIdentifier: "exportScopeSection") {
            VStack(spacing: 0) {
                Picker("导出范围", selection: $selectedScopeMode) {
                    ForEach(ScopeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
                .padding(.vertical, 12)
                .disabled(isExporting || exportDateBounds == nil)
                .accessibilityIdentifier("exportScopePicker")

                if selectedScopeMode == .dateRange {
                    TaskSurfaceSeparator()
                    DatePicker(
                        "开始日期",
                        selection: $startDate,
                        displayedComponents: .date
                    )
                    .font(AppTypography.body)
                    .tint(theme.accent)
                    .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
                    .frame(minHeight: TaskSurfaceMetrics.rowMinHeight)
                    .disabled(isExporting)
                    .accessibilityIdentifier("exportStartDatePicker")

                    TaskSurfaceSeparator()
                    DatePicker(
                        "结束日期",
                        selection: $endDate,
                        displayedComponents: .date
                    )
                    .font(AppTypography.body)
                    .tint(theme.accent)
                    .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
                    .frame(minHeight: TaskSurfaceMetrics.rowMinHeight)
                    .disabled(isExporting)
                    .accessibilityIdentifier("exportEndDatePicker")
                }

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
            Picker("导出格式", selection: $selectedFormat) {
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
                let service = makeExportService(format: request.format)
                exportResult = try await service.export(request: request)
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
        let scope: ExportScope
        switch selectedScopeMode {
        case .all:
            scope = .all
        case .dateRange:
            guard dateRangeIsValid else { return nil }
            scope = .dateRange(start: startDate, end: endDate)
        }
        return ExportRequest(
            scope: scope,
            format: selectedFormat,
            includePhotos: includePhotos
        )
    }

    private func makeExportService(format: ExportFormat) -> ExportService {
        #if DEBUG
            if format == .pdf, UITestSupport.wantsExportForcePDFFailure {
                return ExportService(snapshotProvider: FailingPDFExportSnapshotProvider())
            }
        #endif
        return ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(
                repository: canonicalService.repository
            )
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
            var bounds = try await canonicalService.repository.exportDateBounds()
            #if DEBUG
                if bounds == nil, UITestSupport.wantsExportForcePDFFailure {
                    let date = Date(timeIntervalSince1970: 3_600)
                    bounds = ExportDateBounds(earliest: date, latest: date)
                }
            #endif
            exportDateBounds = bounds
            exportFailure = nil
            if let bounds {
                startDate = Calendar.current.startOfDay(for: bounds.earliest)
                endDate = Calendar.current.startOfDay(for: bounds.latest)
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
        if selectedScopeMode == .dateRange, !dateRangeIsValid {
            return "开始日期不能晚于结束日期。"
        }
        return nil
    }

    var dateRangeIsValid: Bool {
        Calendar.current.startOfDay(for: startDate) <= Calendar.current.startOfDay(for: endDate)
    }

    func failureMessage(for error: Error, format: ExportFormat) -> String {
        if case ExportError.emptyExport = error {
            return "所选范围内没有可导出的时刻，请调整日期范围后重试。"
        }
        if case ExportError.invalidDateRange = error {
            return "开始日期不能晚于结束日期。"
        }
        return "\(format.displayName) 导出失败，请重试。"
    }
}

#Preview {
    ExportView()
        .environment(ThemeManager())
        .environment(CanonicalLibraryService.makeInMemoryForPreview())
}
