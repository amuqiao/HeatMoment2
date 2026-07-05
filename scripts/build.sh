#!/usr/bin/env bash
# 构建 App（默认 Debug + iPhone 模拟器）。工程不存在时先自动 gen。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
source "$DIR/lib/sim.sh"
[ "${1:-}" = "-h" ] && { echo "build.sh — xcodebuild 构建（SIM_NAME 可覆盖模拟器，默认 ${SIM_NAME}）"; exit 0; }

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
