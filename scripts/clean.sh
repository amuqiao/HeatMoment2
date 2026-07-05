#!/usr/bin/env bash
# 清理：删除 DerivedData 与生成的 .xcodeproj（靠 gen.sh 重建）。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
[ "${1:-}" = "-h" ] && { echo "clean.sh — 删除 DerivedData 与生成的 ${PROJECT_NAME}.xcodeproj"; exit 0; }

cd "$REPO_ROOT"
rm -rf DerivedData "${PROJECT_NAME}.xcodeproj"
log "已清理 DerivedData 与 ${PROJECT_NAME}.xcodeproj"
