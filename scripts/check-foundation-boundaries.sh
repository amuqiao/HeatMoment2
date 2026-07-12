#!/usr/bin/env bash
# Foundation 边界守卫：快速扫描明显的反向依赖。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

usage() {
  cat <<'EOF'
check-foundation-boundaries.sh — 扫描 SwiftUI foundation / feature / capability 边界

用法:
  ./scripts/check-foundation-boundaries.sh [-h|--help]

参数:
  无        只读扫描，发现边界漂移即失败

环境变量:
  无

副作用:
  只读；不构建、不测试、不修改源码。

不负责:
  Swift 代码格式、编译、XCTest/XCUITest；见 lint.sh / build.sh / test.sh。

示例:
  ./scripts/check-foundation-boundaries.sh

exit code:
  0     边界扫描通过
  非 0  发现边界漂移或缺少扫描工具
EOF
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
require_no_args "./scripts/check-foundation-boundaries.sh" "$@"
require_cmd rg

cd "$REPO_ROOT"

fail_if_found() {
  local label="$1"
  local pattern="$2"
  shift 2

  if rg -n "$pattern" "$@"; then
    err "$label"
  fi
}

log "== 1/3 Foundation UI 业务依赖 =="
fail_if_found \
  "DesignSystem 不应引用 Moodments 业务模型或 canonical 数据实现" \
  "\\b(Mood|Moment|Tag|Timeline|Heatmap|Canonical|Repository|MoodPalette)\\b" \
  Sources/Moodments/DesignSystem

log "== 2/3 Feature concrete capability =="
fail_if_found \
  "Feature 不应直接创建备份/导出 concrete service；应由 App composition 注入 capability contract" \
  "\\bExportService\\(|CanonicalExportSnapshotStore|CanonicalBackupRestoreService|DebugFailingPDFExportService" \
  Sources/Moodments/Features

log "== 3/3 Settings 跨能力协议 =="
fail_if_found \
  "Settings feature 不应定义跨 feature service protocol 或 canonical service 实现" \
  "protocol .*Servicing|struct Canonical.*Service|struct .*Service" \
  Sources/Moodments/Features/Settings

log "foundation 边界扫描通过"
