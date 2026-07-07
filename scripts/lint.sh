#!/usr/bin/env bash
# 代码规范：swiftlint + swift-format。默认 check（只读校验），--fix 就地修复。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

usage() {
  cat <<'EOF'
lint.sh — 代码规范：swiftlint + swift-format 校验 Sources 与 Tests

用法:
  ./scripts/lint.sh [--fix] [-h|--help]

参数:
  （无）    check：只读校验，不改文件（默认）
  --fix     就地修复可自动修的问题（swiftlint --fix + swift-format --in-place）

环境变量:
  无

副作用:
  默认只读；--fix 会就地改写 Sources/Tests 源文件。工具未安装时告警并跳过该项
  （不静默失败整个流程），不阻断。

不负责:
  构建 / 测试（见 build.sh / test.sh）；安装工具链（见 bootstrap.sh）。

示例:
  ./scripts/lint.sh
  ./scripts/lint.sh --fix

exit code:
  0     无 error（可能有非阻断 warning）
  非 0  存在 lint error（快速失败，详见输出）
EOF
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

cd "$REPO_ROOT"
case "$#" in
  0) MODE="check" ;;
  1)
    case "$1" in
      --fix) MODE="--fix" ;;
      *) err "未知参数：$1（用 ./scripts/lint.sh -h 查看）" ;;
    esac
    ;;
  *)
    [ "$1" = "--fix" ] || err "未知参数：$1（用 ./scripts/lint.sh -h 查看）"
    err "未知参数：$2（用 ./scripts/lint.sh -h 查看）"
    ;;
esac

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
