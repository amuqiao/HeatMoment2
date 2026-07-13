import Foundation
import LocalAuthentication

/// `LocalAuthentication` 封装（见 `docs/current/implementation-truth.md` §10.1.1）：`LAContext`
/// 非 `Sendable`，实例只在本服务内部临时创建/使用，不跨隔离域传递（见
/// `docs/current/implementation-truth.md` §5）。`.deviceOwnerAuthentication` policy 本身即「优先生物
/// 识别、不可用时兜底系统密码」（docs/current/implementation-truth.md §10.1.1「无生物识别兜底」），不需要本类型自行实现降级分支。
struct BiometricLockService: Sendable {
    /// 设备当前是否具备可用的验证手段（生物识别或系统密码任一）。**设置页「面容解锁」开关据此
    /// 禁用/隐藏**——设备既无生物识别也未设置任何锁屏密码时，不应出现「开了锁但永远验证不了」
    /// 的死锁状态（docs/current/implementation-truth.md §10.1.1）。
    func canEvaluate() -> Bool {
        #if DEBUG
        if UITestSupport.forcedBiometricOutcome != nil { return true }
        #endif
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// 发起一次验证。
    /// - Parameter reason: 验证弹层展示给用户的原因文案。
    /// - Returns: 验证是否成功。
    /// - Throws: 不吞错——`LAError`（用户取消、系统繁忙等）原样上抛，调用方（`PrivacyLockView`）
    ///   决定如何反馈；隐私锁验证失败/取消允许用户重试，不视为不可恢复错误。
    func evaluate(reason: String) async throws -> Bool {
        #if DEBUG
        if let forced = UITestSupport.forcedBiometricOutcome {
            // DEBUG 冒烟注入（见 `UITestSupport`）：绕开真实 Face ID/密码系统交互——系统级验证
            // UI 不在 App 无障碍树内，`XCUITest` 无法可靠驱动（与 `PhotosPicker` 同类限制，见
            // `EditorPhotoSection` 头部注释先例）。
            return forced
        }
        #endif
        let context = LAContext()
        var evalError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evalError) else {
            if let evalError { throw evalError }
            return false
        }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}
