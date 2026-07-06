#!/usr/bin/env bash
# 一次性验证：lint → build → test 一条龙。本地与 CI 共用此入口。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

usage() {
  cat <<'EOF'
verify.sh — 一次性验证：lint → build → test 一条龙（本地与 CI 共用同一入口）

用法:
  ./scripts/verify.sh [-h|--help]

参数:
  无        固定顺序执行 lint → build → test --all，任一阶段失败即中止

环境变量:
  SIM_NAME  覆盖构建/测试所用模拟器（默认 iPhone 17，见 lib/sim.sh）

副作用:
  触发构建与测试：写 DerivedData、启动模拟器跑 XCTest/XCUITest；不改工作区源码。

不负责:
  安装工具链（见 bootstrap.sh）、生成工程（缺失时由 build/test 自动调 gen.sh）。

示例:
  ./scripts/verify.sh
  SIM_NAME='iPhone 16 Pro' ./scripts/verify.sh

exit code:
  0     lint + build + test 全通过
  非 0  任一阶段失败即中止（快速失败，详见 stderr 与各子脚本输出）
EOF
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

log "== 1/3 lint =="; "$DIR/lint.sh"
log "== 2/3 build =="; "$DIR/build.sh"
log "== 3/3 test =="; "$DIR/test.sh" --all
log "verify 全部通过 ✅"
