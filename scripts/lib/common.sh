#!/usr/bin/env bash
# 公共 helper：仓库根定位、日志、快速失败、命令校验。被各入口 source，不单独执行。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

PROJECT_NAME="Moodments"
export PROJECT_NAME

log()  { printf '\033[0;36m[moodments]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[moodments:warn]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[0;31m[moodments:error]\033[0m %s\n' "$*" >&2; exit 1; }

# 校验命令存在，否则快速失败并提示如何补齐（不 silent fallback）
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || err "缺少命令：$1（先运行 ./scripts/bootstrap.sh）"
}

# 无参数入口统一拒绝未知参数，避免错误命令被静默当作成功路径执行。
require_no_args() {
  local usage_hint="$1"
  shift
  [ "$#" -eq 0 ] || err "未知参数：$1（用 ${usage_hint} -h 查看）"
}

# 若安装了 xcbeautify 则用它美化 xcodebuild 输出，否则原样透传
pretty() {
  if command -v xcbeautify >/dev/null 2>&1; then xcbeautify; else cat; fi
}
