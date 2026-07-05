#!/usr/bin/env bash
# 一次性验证：lint → build → test 一条龙。本地与 CI 共用此入口。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
[ "${1:-}" = "-h" ] && { echo "verify.sh — lint + build + test 一条龙（CI 也用它）"; exit 0; }

log "== 1/3 lint =="; "$DIR/lint.sh"
log "== 2/3 build =="; "$DIR/build.sh"
log "== 3/3 test =="; "$DIR/test.sh" --all
log "verify 全部通过 ✅"
