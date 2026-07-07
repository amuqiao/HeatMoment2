#!/usr/bin/env bash
# 构建 App（默认 Debug + iPhone 模拟器）。工程不存在时先自动 gen。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
source "$DIR/lib/sim.sh"

usage() {
  cat <<'EOF'
build.sh — 构建 Moodments（Debug + iPhone 模拟器）

用法:
  ./scripts/build.sh [-h|--help]

参数:
  无        构建 Debug 配置到模拟器，不签名（CODE_SIGNING_ALLOWED=NO）

环境变量:
  SIM_NAME  覆盖目标模拟器（默认 iPhone 17，见 lib/sim.sh）

副作用:
  写 DerivedData；工程不存在时先自动调 gen.sh 生成；不改工作区源码、不安装到模拟器。

不负责:
  运行测试（见 test.sh）、启动 App（见 run.sh）。

示例:
  ./scripts/build.sh
  SIM_NAME='iPhone 16 Pro' ./scripts/build.sh

exit code:
  0     BUILD SUCCEEDED
  非 0  编译失败或缺工具（快速失败，详见输出）
EOF
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
require_no_args "./scripts/build.sh" "$@"

require_cmd xcodebuild
cd "$REPO_ROOT"
[ -d "${PROJECT_NAME}.xcodeproj" ] || "$DIR/gen.sh"

log "构建 ${PROJECT_NAME}（${SIM_NAME}）"
set -o pipefail
xcodebuild build \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "${PROJECT_NAME}" \
  -destination "$(sim_destination)" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO | pretty
log "构建完成"
