import Foundation

extension ExportView {
    func exportSelectedFormat() {
        guard !isExportBusy, let request = makeRequest() else { return }
        exportTask?.cancel()
        isExporting = true
        pendingShareTransaction = nil
        exportFailure = nil
        didHandleShareCompletion = false
        exportAttemptID += 1
        let attemptID = exportAttemptID
        exportTask = Task {
            defer {
                isExporting = false
                exportTask = nil
            }
            do {
                let transaction = try await exportService.prepareShareTransaction(request: request)
                #if DEBUG
                    if UITestSupport.wantsExportShareFailOnce, !didForceShareFailure {
                        didForceShareFailure = true
                        pendingShareTransaction = transaction
                        finishSharedExport(completed: false, error: ShareFailureError())
                        return
                    }
                    if UITestSupport.wantsExportShareAutoComplete {
                        pendingShareTransaction = transaction
                        finishSharedExport(completed: true, error: nil)
                        return
                    }
                #endif
                pendingShareTransaction = transaction
                isShareSheetPresented = true
            } catch is CancellationError {
                pendingShareTransaction = nil
            } catch {
                exportFailure = FailureState(
                    attemptID: attemptID,
                    message: failureMessage(for: error, format: request.format),
                    retryAction: .export
                )
            }
        }
    }

    func makeRequest() -> ExportRequest? {
        guard exportDateBounds != nil else { return nil }
        guard dateRangeIsValid else { return nil }
        return ExportRequest(
            scope: .dateRange(start: startDate, end: endDate),
            format: selectedFormat,
            includePhotos: includePhotos
        )
    }

    func loadDateBoundsIfNeeded() async {
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

    func reloadDateBounds() async {
        didLoadDateBounds = false
        exportDateBounds = nil
        exportFailure = nil
        if cleanupTemporaryExports() {
            await loadDateBoundsIfNeeded()
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        isExporting = false
        if pendingShareTransaction != nil, !isShareSheetPresented {
            pendingShareTransaction = nil
            _ = cleanupTemporaryExports()
        }
    }

    func retry(_ failure: ExportView.FailureState) {
        switch failure.retryAction {
        case .export:
            exportSelectedFormat()
        case .cleanupTemporaryExports:
            if cleanupTemporaryExports() {
                Task { await loadDateBoundsIfNeeded() }
            }
        case .loadDateBounds:
            Task { await reloadDateBounds() }
        case .share:
            retryShare()
        }
    }

    func clearExportState() {
        let shouldCleanupPendingShare = pendingShareTransaction != nil
        exportFailure = nil
        pendingShareTransaction = nil
        didHandleShareCompletion = false
        if shouldCleanupPendingShare {
            _ = cleanupTemporaryExports()
        }
    }

    var validationMessage: String? {
        let retryAction = exportFailure?.retryAction
        if retryAction == .loadDateBounds || retryAction == .cleanupTemporaryExports {
            return nil
        }
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

    var isExportBusy: Bool {
        isExporting || isShareSheetPresented || isResolvingShare
    }

    var exportButtonTitle: String {
        if isExporting { return selectedFormat.exportingTitle }
        if isShareSheetPresented || isResolvingShare { return "正在分享..." }
        return selectedFormat.generateTitle
    }

    func finishSharedExport(completed _: Bool, error: Error?) {
        guard
            let transaction = pendingShareTransaction,
            !isResolvingShare,
            !didHandleShareCompletion
        else {
            return
        }
        didHandleShareCompletion = true
        if error != nil {
            isShareSheetPresented = false
            exportAttemptID += 1
            exportFailure = FailureState(
                attemptID: exportAttemptID,
                message: "系统分享失败，请重试。",
                retryAction: .share
            )
            return
        }
        isResolvingShare = true
        isShareSheetPresented = false
        Task { @MainActor in
            defer {
                pendingShareTransaction = nil
                isResolvingShare = false
            }
            _ = finishShareTransaction(transaction)
        }
    }

    func retryShare() {
        guard pendingShareTransaction != nil, !isExportBusy else { return }
        exportFailure = nil
        didHandleShareCompletion = false
        #if DEBUG
            if UITestSupport.wantsExportShareAutoComplete {
                finishSharedExport(completed: true, error: nil)
                return
            }
        #endif
        isShareSheetPresented = true
    }

    @discardableResult
    func finishShareTransaction(_ transaction: ExportShareTransaction) -> Bool {
        do {
            try exportService.finishShareTransaction(transaction)
            if exportFailure?.retryAction == .cleanupTemporaryExports {
                exportFailure = nil
            }
            return true
        } catch {
            exportAttemptID += 1
            exportFailure = FailureState(
                attemptID: exportAttemptID,
                message: "临时文件清理失败，请重试。",
                retryAction: .cleanupTemporaryExports
            )
            return false
        }
    }

    @discardableResult
    func cleanupTemporaryExports() -> Bool {
        do {
            try exportService.cleanupTemporaryExports()
            if exportFailure?.retryAction == .cleanupTemporaryExports {
                exportFailure = nil
            }
            return true
        } catch {
            exportAttemptID += 1
            exportFailure = FailureState(
                attemptID: exportAttemptID,
                message: "临时文件清理失败，请重试。",
                retryAction: .cleanupTemporaryExports
            )
            return false
        }
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
