import StoreKit
import SwiftUI
import UIKit

/// Pro 权益卡片（任务卡片栈，见 `docs/design/08-architecture.md` §2.2、`11-monetization.md`）：
/// 三类触发来源（设置横幅 / 篇数 / 照片 / 标签额度 / 恢复购买）共用同一内容，只是关闭后回退
/// 目标不同（11 §11.3）——本视图不主动重试触发前的原操作：购买/恢复成功后 `dismiss()` 即完成
/// 「放行」，因为限额闸门本身会在用户下一次交互时重新现场判定（权威判定见
/// `SubscriptionService.currentEntitlementIsPro()`），不由本视图猜测调用方状态。
struct ProPaywallView: View {
    let trigger: PaywallTrigger

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(SubscriptionService.self) private var subscriptionService

    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var infoMessage: LocalizedStringKey?

    var body: some View {
        AppSheetScaffold(style: .commercial) {
            Group {
                if subscriptionService.isPro {
                    alreadyProContent
                } else {
                    purchaseContent
                }
            }
            .appSheetChrome(
                title: "Pro 会员",
                cancellation: AppSheetAction("关闭") {
                    dismiss()
                }
            )
            .userFacingErrorAlert(errorPresenter)
            .alert(
                "提示",
                isPresented: Binding(
                    get: { infoMessage != nil },
                    set: { if !$0 { infoMessage = nil } }
                ),
                presenting: infoMessage
            ) { _ in
                Button("好") {}
            } message: { message in
                Text(message)
            }
            .task {
                let needsMonthlyProduct = subscriptionService.monthlyProduct == nil
                let needsLifetimeProduct = subscriptionService.lifetimeProduct == nil
                if !(needsMonthlyProduct || needsLifetimeProduct) {
                    return
                }
                do {
                    try await subscriptionService.loadProducts()
                } catch {
                    await errorPresenter.report(message: "加载 Pro 商品信息失败，请稍后重试。", underlying: error)
                }
            }
        }
    }

    // MARK: - 已是 Pro 会员态（见 04-screen-specs.md §4.11，13-open-questions.md #11）

    private var alreadyProContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(theme.commercialRed)
            Text("你已是 Pro 会员")
                .font(AppTypography.cardTitle)
                .foregroundStyle(theme.commercialPrimaryText)
            Text("无限日记、无限照片、无限标签已解锁")
                .font(AppTypography.body)
                .foregroundStyle(theme.commercialSecondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("paywallAlreadyProContent")
    }

    // MARK: - 购买态

    private var purchaseContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                benefits
                purchaseButtons
                restoreButton
                if SubscriptionService.canMakePayments {
                    redeemCodeButton
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(triggerHeadline)
                .font(AppTypography.cardTitle)
                .foregroundStyle(theme.commercialPrimaryText)
            Text("解锁无限日记、无限照片、无限标签，随时随地记录每一个时刻")
                .font(AppTypography.body)
                .foregroundStyle(theme.commercialSecondaryText)
        }
        .accessibilityIdentifier("paywallHeadline")
    }

    /// 三类触发（设置横幅 / 篇数 / 照片 / 标签额度）内容一致，只有标题因触发来源不同措辞
    /// （11 §11.3：Paywall 页面内容/布局在两类触发下完全一致，只是关闭后的回退目标不同）。
    private var triggerHeadline: LocalizedStringKey {
        switch trigger {
        case .banner: "立即升级成为 Pro 用户"
        case .quotaMoment: "免费日记数量已达上限"
        case .quotaPhoto: "单篇照片数量已达上限"
        case .quotaTag: "标签数量已达上限"
        case .restore: "恢复购买"
        }
    }

    /// 权益条目完整朗读对比文案（见 `docs/design/12-quality-assurance.md` §12.4）。
    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow(text: "发布无限的心情日记，普通用户最多只能发布 10 篇日记")
            benefitRow(text: "每篇日记添加无限张照片，普通用户每篇最多 3 张")
            benefitRow(text: "创建无限个标签，普通用户最多 3 个标签")
        }
    }

    private func benefitRow(text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.commercialRed)
            Text(text).foregroundStyle(theme.commercialPrimaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var purchaseButtons: some View {
        VStack(spacing: 12) {
            purchaseButton(
                product: subscriptionService.monthlyProduct, title: "月度订阅",
                identifier: "paywallMonthlyButton"
            )
            purchaseButton(
                product: subscriptionService.lifetimeProduct, title: "终身买断",
                identifier: "paywallLifetimeButton"
            )
        }
    }

    /// 价格用 `Product.displayPrice` 动态渲染，不写死文本（见 11 §11.1）。
    private func purchaseButton(
        product: Product?,
        title: LocalizedStringKey,
        identifier: String
    ) -> some View {
        Button {
            guard let product else { return }
            handlePurchase(product)
        } label: {
            HStack {
                Text(title)
                Spacer()
                if let product {
                    Text(product.displayPrice)
                } else {
                    ProgressView()
                }
            }
            .font(AppTypography.button)
            .foregroundStyle(theme.onCommercialText)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.commercialRed)
            )
        }
        .disabled(product == nil || isPurchasing)
        .accessibilityIdentifier(identifier)
    }

    private var restoreButton: some View {
        Button {
            handleRestore()
        } label: {
            if isRestoring {
                ProgressView()
            } else {
                Text("恢复购买")
                    .foregroundStyle(theme.commercialRed)
            }
        }
        .disabled(isRestoring)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("paywallRestoreButton")
    }

    private var redeemCodeButton: some View {
        Button("兑换码") {
            handleRedeemCode()
        }
        .foregroundStyle(theme.commercialRed)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("paywallRedeemCodeButton")
    }

    // MARK: - 动作

    private func handlePurchase(_ product: Product) {
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                switch try await subscriptionService.purchase(product) {
                case .success:
                    dismiss()
                case .userCancelled:
                    break
                case .pending:
                    infoMessage = "购买正在处理中，完成后将自动解锁 Pro 权益。"
                }
            } catch {
                await errorPresenter.report(message: "购买失败，请稍后重试。", underlying: error)
            }
        }
    }

    private func handleRestore() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                let found = try await subscriptionService.restorePurchases()
                if found {
                    dismiss()
                } else {
                    infoMessage = "未找到可恢复的购买记录。"
                }
            } catch {
                await errorPresenter.report(message: "恢复购买失败，请稍后重试。", underlying: error)
            }
        }
    }

    private func handleRedeemCode() {
        Task {
            let foregroundScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
            let fallbackScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
            guard let scene = foregroundScene ?? fallbackScene
            else { return }
            do {
                try await subscriptionService.presentCodeRedemption(in: scene)
            } catch {
                await errorPresenter.report(message: "打开兑换码入口失败，请稍后重试。", underlying: error)
            }
        }
    }
}

#Preview {
    ProPaywallView(trigger: .banner)
        .environment(ThemeManager())
        .environment(ErrorPresenter())
        .environment(SubscriptionService())
}
