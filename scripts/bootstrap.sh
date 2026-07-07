#!/usr/bin/env bash
# 环境准备：校验 Xcode，经 Homebrew 安装 xcodegen / swiftlint / swift-format。
# 幂等（已装则跳过）；缺 Homebrew 快速失败。
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat <<'EOF'
bootstrap.sh — 准备本地 iOS 开发工具链（首次在新机器上运行一次）

用法:
  ./scripts/bootstrap.sh [-h|--help]

参数:
  无        校验 Xcode，并用 brew 安装缺失工具

环境变量:
  无

副作用:
  经 Homebrew 安装 xcodegen / swiftlint / swift-format（已装则跳过，幂等）。

不负责:
  安装 Xcode 本体、安装 Homebrew（缺失则报错退出）、生成工程（见 gen.sh）。

示例:
  ./scripts/bootstrap.sh

exit code:
  0     工具齐备（或本次安装成功）
  非 0  缺 Xcode / Homebrew，或某工具安装失败（快速失败，详见 stderr）
EOF
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
require_no_args "./scripts/bootstrap.sh" "$@"

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
