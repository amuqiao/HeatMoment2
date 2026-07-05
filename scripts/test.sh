#!/usr/bin/env bash
# 运行测试：--unit（单元）/ --ui（界面）/ --all（默认）。工程不存在时先 gen。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
source "$DIR/lib/sim.sh"

usage() { echo "test.sh [--unit|--ui|--all]  运行 XCTest/XCUITest（默认 --all，SIM_NAME 可覆盖模拟器）"; }
[ "${1:-}" = "-h" ] && { usage; exit 0; }

MODE="${1:---all}"
require_cmd xcodebuild
cd "$REPO_ROOT"
[ -d "${PROJECT_NAME}.xcodeproj" ] || "$DIR/gen.sh"

ARGS=()
case "$MODE" in
  --unit) ARGS+=(-only-testing:MoodmentsTests) ;;
  --ui)   ARGS+=(-only-testing:MoodmentsUITests) ;;
  --all)  ;;
  *) err "未知参数：$MODE（用 --unit|--ui|--all）" ;;
esac

log "测试 ${PROJECT_NAME}（${MODE}，${SIM_NAME}）"
set -o pipefail
xcodebuild test \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "${PROJECT_NAME}" \
  -destination "$(sim_destination)" \
  "${ARGS[@]+"${ARGS[@]}"}" \
  CODE_SIGNING_ALLOWED=NO | pretty
log "测试通过"
