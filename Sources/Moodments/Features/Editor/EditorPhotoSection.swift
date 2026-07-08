import PhotosUI
import SwiftUI

/// `PhotosPickerItem.loadTransferable` 返回 `nil`（未抛错但也未给出数据）时的合成错误，
/// 仅用于统一走 `ErrorPresenter.report(message:underlying:)` 的日志通道，不面向用户展示。
private enum PhotoLoadError: Error {
    case emptyData
}

/// 编辑器照片区（见 `docs/design/04-screen-specs.md` §4.4、05-design-system.md §5.7）：
/// 未加时为主色实心大按钮「添加照片」；已加后为「日志图片 N 张」+ 横排缩略图（⊖ 删除角标，
/// 提供 `accessibilityAction` 替代路径）+ ⊕ 追加。第 4 张触发 Paywall——额度判定完全经
/// `MomentEditorModel`（`checkCanAddPhoto`/`remainingPhotoSlots`）消费 `QuotaService` 结果，
/// 本视图不用 `Quota` 常量自行比较数值、也不硬编码免费上限（对 Pro 权益有感知）。
///
/// **PhotosPicker 的 UI 测试限制**：系统 `PhotosPicker` 呈现的选择器不在 App 自身的无障碍树
/// 内，`XCUITest` 无法可靠驱动其选图操作；DEBUG 构建下按 `-uiTestPhotoInjection` 启动参数
/// 额外展示一个调试注入入口，直接把合成 JPEG 写入草稿以绕开该限制（见阶段 3 计划决策1）。
struct EditorPhotoSection: View {
    @Bindable var model: MomentEditorModel
    @Binding var editorPaywallTrigger: PaywallTrigger?

    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter
    @State private var isPickerPresented = false
    @State private var pickerSelection: [PhotosPickerItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.draftPhotos.isEmpty {
                addPhotoButton
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text("日志图片")
                        .font(AppTypography.cardTitle)
                    Text("\(model.draftPhotos.count) 张")
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    appendButton
                }
                .foregroundStyle(theme.primaryText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MomentPhotoRailLayout.itemSpacing) {
                        ForEach(model.draftPhotos) { photo in
                            thumbnail(for: photo)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.trailing, 12)
                }
            }

            #if DEBUG
                if UITestSupport.wantsPhotoInjectionHook {
                    Button("注入测试照片") {
                        Task {
                            let check = await model.addPhoto(UITestSupport.makeSyntheticPhotoData())
                            if case .exceeded = check {
                                editorPaywallTrigger = .quotaPhoto
                            }
                        }
                    }
                    .accessibilityIdentifier("editorInjectPhotoButton")
                }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .photosPicker(
            isPresented: $isPickerPresented,
            selection: $pickerSelection,
            maxSelectionCount: max(model.remainingPhotoSlots, 1),
            matching: .images
        )
        .onChange(of: pickerSelection) { _, newItems in
            guard !newItems.isEmpty else { return }
            let itemsToLoad = newItems
            Task {
                await appendPickedPhotos(itemsToLoad)
                pickerSelection = []
            }
        }
    }

    private var addPhotoButton: some View {
        Button {
            requestAddPhotos()
        } label: {
            Text("添加照片")
                .font(AppTypography.button)
                .foregroundStyle(theme.onAccentText)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(
                        cornerRadius: TaskSurfaceMetrics.panelCornerRadius,
                        style: .continuous
                    )
                    .fill(theme.accent)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editorAddPhotoButton")
    }

    private var appendButton: some View {
        Button {
            requestAddPhotos()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.onAccentText)
                .frame(width: 28, height: 28)
                .background(Circle().fill(theme.accent))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editorAppendPhotoButton")
        .accessibilityLabel(Text("追加照片"))
    }

    private func thumbnail(for photo: DraftPhoto) -> some View {
        let uiImage = UIImage(data: photo.jpegData)
        let itemSize =
            uiImage.map {
                MomentPhotoRailLayout.itemSize(for: $0.size)
            } ?? MomentPhotoRailLayout.fallbackItemSize

        return ZStack(alignment: .topTrailing) {
            photoContent(uiImage: uiImage, size: itemSize)
            Button {
                model.removePhoto(id: photo.id)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.onDangerText)
                    .frame(
                        width: MomentPhotoRailLayout.deleteBadgeDiameter,
                        height: MomentPhotoRailLayout.deleteBadgeDiameter
                    )
                    .background(Circle().fill(theme.danger))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .offset(x: 12, y: -12)
            .accessibilityLabel(Text("删除该照片"))
            .accessibilityAction(named: Text("删除该照片")) {
                model.removePhoto(id: photo.id)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("editorPhotoThumbnail-\(photo.id.uuidString)")
    }

    @ViewBuilder
    private func photoContent(uiImage: UIImage?, size: CGSize) -> some View {
        if let uiImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MomentPhotoRailLayout.itemCornerRadius,
                        style: .continuous
                    )
                )
                .overlay(photoBorder)
        } else {
            RoundedRectangle(
                cornerRadius: MomentPhotoRailLayout.itemCornerRadius,
                style: .continuous
            )
            .fill(theme.chipFill)
            .frame(width: size.width, height: size.height)
            .overlay(photoBorder)
        }
    }

    private var photoBorder: some View {
        RoundedRectangle(cornerRadius: MomentPhotoRailLayout.itemCornerRadius, style: .continuous)
            .strokeBorder(theme.secondaryText.opacity(0.12), lineWidth: 0.5)
    }

    private func requestAddPhotos() {
        // 额度判定只消费 QuotaService 结果（经 model 现场重查 Pro 权威判定），不在 View 层
        // 比较数值——对 Pro 权益有感知（阶段7计划决策1）。
        Task {
            if case .exceeded = await model.checkCanAddPhoto() {
                editorPaywallTrigger = .quotaPhoto
                return
            }
            isPickerPresented = true
        }
    }

    /// 批量追加：循环**前**只现场重查一次 Pro（`makeCurrentQuotaService()`），循环内复用同一份
    /// `QuotaService` 判定（阶段7 review 修复：避免每张照片各自触发一次 Pro 查询 IO；正确性不变，
    /// 额度判定仍完整落在 `QuotaService`，见该方法头部说明）。
    private func appendPickedPhotos(_ items: [PhotosPickerItem]) async {
        let quotaService = await model.makeCurrentQuotaService()
        for item in items {
            guard let rawData = await loadData(from: item) else { continue }
            guard let compressed = await compress(rawData) else { continue }
            let check = await model.addPhoto(compressed, using: quotaService)
            if case .exceeded = check {
                editorPaywallTrigger = .quotaPhoto
                break
            }
        }
    }

    private func loadData(from item: PhotosPickerItem) async -> Data? {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await errorPresenter.report(
                    message: "读取所选照片失败，请重试。",
                    underlying: PhotoLoadError.emptyData
                )
                return nil
            }
            return data
        } catch {
            await errorPresenter.report(message: "读取所选照片失败，请重试。", underlying: error)
            return nil
        }
    }

    /// 压缩耗时工作显式切到后台执行（见 08-architecture.md §5：耗时工作切后台），
    /// `ImageCompressor` 自身是不做隔离域切换的纯函数；`Task.detached` 内不持有 `errorPresenter`
    /// （`@MainActor` 隔离），错误改为在 `await` 恢复后于调用方所在上下文上报，不吞错。
    private func compress(_ data: Data) async -> Data? {
        do {
            return try await Task.detached(priority: .userInitiated) {
                try ImageCompressor.compressToJPEG(data)
            }.value
        } catch {
            await errorPresenter.report(message: "图片压缩失败，请重试。", underlying: error)
            return nil
        }
    }
}
