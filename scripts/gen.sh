#!/usr/bin/env bash
# 用 XcodeGen 从 Project.yml 生成 Moodments.xcodeproj（工程可重建，勿手改 pbxproj）。
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ "${1:-}" = "-h" ] && { echo "gen.sh — 从 Project.yml 生成 ${PROJECT_NAME}.xcodeproj"; exit 0; }

require_cmd xcodegen
cd "$REPO_ROOT"
xcodegen generate
log "已生成 ${PROJECT_NAME}.xcodeproj"
