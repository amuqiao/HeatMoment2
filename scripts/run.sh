#!/usr/bin/env bash
# 项目启动：boot 模拟器 → build → install → launch，本地看界面。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
source "$DIR/lib/sim.sh"
[ "${1:-}" = "-h" ] && { echo "run.sh — 在模拟器（默认 ${SIM_NAME}）构建并启动 App（SIM_NAME 可覆盖）"; exit 0; }

require_cmd xcodebuild
cd "$REPO_ROOT"
[ -d "${PROJECT_NAME}.xcodeproj" ] || "$DIR/gen.sh"

BUNDLE_ID="com.moodments.app"
UDID="$(sim_boot)"
open -a Simulator || true
log "构建并安装到模拟器 ${SIM_NAME}（$UDID）"

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
