# 11 · Pro / StoreKit 集成

> 职责：定义「心绪日记 / 时刻」的商业化实现——Pro 商品与 Entitlement（月订阅 + 终身买断）、购买/恢复购买/核销码流程、Paywall 触发原则、订阅状态一致性。限额数值本身不在本文定义。

限额数值（10 篇 Moment / 每篇 3 张照片 / 3 个标签）以 `06-domain-model.md` 的免费 / Pro 限额契约为唯一权威，本文只定义工程侧如何强制执行、检测、恢复，不重复列出数值表。

## 11.1 商品与 Entitlement

- 提供**两个商品**（已裁决）：
  1. **月度 Pro**：自动续期订阅（auto-renewable subscription），¥6/月 `[真机确认]`；价格用 `Product.displayPrice` 动态渲染，不写死文本 `[设计决策实现]`。
  2. **终身 Pro**：一次性买断（non-consumable IAP）`[设计决策，超出原 App：真机截图仅有月订阅，终身买断为本次新增]`。价格未定，见 `13-open-questions.md` 开放问题；商品与 Paywall 视觉需另行设计（标 `[设计决策]`），不冒充真机事实。
- **Pro 判定**：`Transaction.currentEntitlements` 命中「月度订阅未过期」**或**「终身买断已购」任一，即视为 Pro；二者是 OR 关系，任一有效即解锁全部 Pro 能力。
- 启动 / 回前台时用 `Transaction.currentEntitlements` 核对上述两类授权，并订阅 `Transaction.updates` `AsyncSequence` 实时接收续订/退款/取消事件，刷新本地 `SubscriptionStateCache`（见 `07-data-persistence.md` 订阅状态缓存；缓存需能同时表达「订阅态」与「终身买断态」）。

## 11.2 购买 / 恢复购买 / 核销码

- 购买：`Product.purchase()` → 处理 `.success(let verification)` → `checkVerification` 校验签名 → `transaction.finish()` → 更新缓存 → 关闭 `ProPaywallView` 回到触发前上下文。
- 恢复购买：调用 `AppStore.sync()`，成功后重新核对 `Transaction.currentEntitlements` 并给出成功/未找到记录的即时反馈。
- 核销码：仅 iOS 平台且 `SKPaymentQueue.canMakePayments()` 为真时展示入口，调起系统兑换码弹层；兑换成功依赖 `Transaction.updates` 被动接收新授权，无需额外轮询。

## 11.3 Paywall 触发原则

1. **主动触发**：设置页 Pro 横幅点击，任意时刻可进入，退出即返回设置页。
2. **阻断式触发**：新建第 11 篇 Moment / 添加第 4 张照片 / 新建第 4 个标签时，先弹出 `ProPaywallView` 拦截该操作，购买成功后自动放行原操作继续执行，取消则回退到操作前状态（不产生半成品数据）`[观测确认]`。
3. Paywall 页面内容/布局在两类触发下完全一致，只是关闭后的回退目标不同。

## 11.4 状态一致性

- 本地 `SubscriptionStateCache` 只用于 UI 快速展示（避免每次打开编辑器/设置页都等待网络），任何「是否放行」的最终判断都必须以当次 `Transaction.currentEntitlements` 查询结果为准，防止用户在设备离线过久后仍凭过期缓存继续使用超额功能 `[设计决策]`。

> 免费 / Pro 各能力的具体限额数值（Moment 篇数、单篇照片数、标签数、价格、终身买断）见 `06-domain-model.md`。
