#!/usr/bin/env bash
# 环境准备：校验 Xcode，经 Homebrew 安装 xcodegen / swiftlint / swift-format。
# 幂等（已装则跳过）；缺 Homebrew 快速失败。
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat <<'EOF'
bootstrap.sh — 准备本地 iOS 开发工具链
  用法:   ./scripts/bootstrap.sh
  作用:   校验 Xcode；用 brew 安装 xcodegen、swiftlint、swift-format（已装跳过）。
  不负责: 安装 Xcode 本体、生成工程（见 gen.sh）。
EOF
}
[ "${1:-}" = "-h" ] && { usage; exit 0; }

require_cmd xcodebuild
log "Xcode: $(xcodebuild -version | head -1)"

command -v brew >/dev/null 2>&1 || err "未找到 Homebrew，请先安装：https://brew.sh"

for tool in xcodegen swiftlint swift-format; do
  if command -v "$tool" >/dev/null 2>&1; then
    log "已安装 $tool"
  else
    log "安装 $tool ..."
    brew install "$tool"
  fi
done
log "bootstrap 完成"
