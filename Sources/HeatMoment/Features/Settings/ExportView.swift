import SwiftUI

struct ExportView: View {
    let exportService: any ExportServicing

    @Environment(ThemeManager.self) private var theme

    @State var selectedFormat: ExportFormat = .markdown
    @State var includePhotos = true
    @State var startDate = Date()
    @State var endDate = Date()
    @State var exportDateBounds: ExportDateBounds?
    @State var didLoadDateBounds = false
    @State var pendingShareTransaction: ExportShareTransaction?
    @State var exportFailure: FailureState?
    @State var isExporting = false
    @State var isShareSheetPresented = false
    @State var isResolvingShare = false
    @State var didHandleShareCompletion = false
    @State var exportAttemptID = 0
    @State var exportTask: Task<Void, Never>?
    #if DEBUG
        @State var didForceDateBoundsFailure = false
        @State var didForceShareFailure = false
    #endif

    init(exportService: any ExportServicing) {
        self.exportService = exportService
        let defaultRange = ExportDateRangeDefaults.recentThreeDays()
        _startDate = State(initialValue: defaultRange.start)
        _endDate = State(initialValue: defaultRange.end)
    }

    var body: some View {
        TaskPageScrollView(accessibilityIdentifier: "exportScrollView") {
            scopeSection
            contentSection
            formatSection
            generateButton
            if let exportFailure {
                FailureSection(
                    failure: exportFailure,
                    isExporting: isExportBusy,
                    retry: retry
                )
            }
        }
        .appSheetDetailNavigationChrome("导出")
        .themedTaskContainer(theme)
        .sheet(
            isPresented: $isShareSheetPresented,
            onDismiss: {
                finishSharedExport(completed: false, error: nil)
            },
            content: {
                if let pendingShareTransaction {
                    ExportShareSheet(transaction: pendingShareTransaction) { completed, error in
                        finishSharedExport(completed: completed, error: error)
                    }
                }
            }
        )
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
            if cleanupTemporaryExports() {
                await loadDateBoundsIfNeeded()
            }
        }
        .onDisappear {
            cancelExport()
        }
    }

    private var scopeSection: some View {
        TaskSurfaceSection(title: "日期", accessibilityIdentifier: "exportScopeSection") {
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
        .disabled(isExportBusy || exportDateBounds == nil)
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
            .disabled(isExportBusy || exportDateBounds == nil)
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
            .disabled(isExportBusy)
            .accessibilityIdentifier("exportFormatPicker")
        }
    }

    private var generateButton: some View {
        Button {
            exportSelectedFormat()
        } label: {
            Label {
                Text(exportButtonTitle)
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
                .fill(isExportBusy ? theme.accentDisabledFill : theme.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(isExportBusy || makeRequest() == nil)
        .accessibilityIdentifier("exportGenerateButton")
    }

}

#Preview {
    ExportView(exportService: PreviewExportService())
        .environment(ThemeManager())
}
