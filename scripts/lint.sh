#!/usr/bin/env bash
# 代码规范：swiftlint + swift-format。默认 check（只读校验），--fix 就地修复。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
[ "${1:-}" = "-h" ] && { echo "lint.sh [--fix]  swiftlint + swift-format（默认 check）"; exit 0; }

cd "$REPO_ROOT"
MODE="${1:-check}"

if command -v swiftlint >/dev/null 2>&1; then
  if [ "$MODE" = "--fix" ]; then swiftlint --fix || true; fi
  swiftlint lint --quiet Sources Tests
else
  warn "未安装 swiftlint，跳过（./scripts/bootstrap.sh 可装）"
fi

if command -v swift-format >/dev/null 2>&1; then
  if [ "$MODE" = "--fix" ]; then
    swift-format format --in-place --recursive Sources Tests
  else
    swift-format lint --recursive Sources Tests
  fi
else
  warn "未安装 swift-format，跳过"
fi
log "lint 完成"
