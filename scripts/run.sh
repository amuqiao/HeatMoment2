#!/usr/bin/env bash
# 项目启动：boot 模拟器 → build → install → launch，本地看界面。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
source "$DIR/lib/sim.sh"

usage() {
  cat <<'EOF'
run.sh — 在模拟器构建并启动 App（boot → build → install → launch），本地看界面

用法:
  ./scripts/run.sh [-h|--help]

参数:
  无        构建 Debug 到模拟器并启动 com.moodments.app

环境变量:
  SIM_NAME  覆盖目标模拟器（默认 iPhone 17，见 lib/sim.sh）

副作用:
  启动模拟器（打开 Simulator.app）、写 DerivedData、把 App 安装并启动到模拟器；
  工程不存在时先自动调 gen.sh。不改工作区源码。

不负责:
  运行测试（见 test.sh）；真机部署 / 签名分发。

示例:
  ./scripts/run.sh
  SIM_NAME='iPhone 16 Pro' ./scripts/run.sh

exit code:
  0     已安装并启动
  非 0  找不到目标模拟器 / 构建失败 / 无构建产物（快速失败，详见 stderr）
EOF
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
require_no_args "./scripts/run.sh" "$@"

require_cmd xcodebuild
cd "$REPO_ROOT"
[ -d "${PROJECT_NAME}.xcodeproj" ] || "$DIR/gen.sh"

BUNDLE_ID="com.moodments.app"
UDID="$(sim_boot)"
open -a Simulator || true
log "构建并安装到模拟器 ${SIM_NAME}（${UDID}）"

DERIVED="$REPO_ROOT/DerivedData"
set -o pipefail
xcodebuild build \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "${PROJECT_NAME}" \
  -destination "id=${UDID}" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO | pretty

APP_PATH="$(find "$DERIVED/Build/Products" -name "${PROJECT_NAME}.app" -maxdepth 3 | head -1)"
[ -z "$APP_PATH" ] && err "未找到构建产物 ${PROJECT_NAME}.app"
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$BUNDLE_ID"
log "已启动 ${PROJECT_NAME}"
