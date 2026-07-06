#!/usr/bin/env bash
# 用 XcodeGen 从 Project.yml 生成 Moodments.xcodeproj（工程可重建，勿手改 pbxproj）。
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat <<'EOF'
gen.sh — 用 XcodeGen 从 Project.yml 生成 Moodments.xcodeproj

用法:
  ./scripts/gen.sh [-h|--help]

参数:
  无        每次全量重新生成工程

环境变量:
  无

副作用:
  （重新）生成 Moodments.xcodeproj（该目录不入库、勿手改 pbxproj）；改 Project.yml
  或增删源文件后须重跑。

不负责:
  安装 xcodegen（见 bootstrap.sh）、构建/运行（见 build.sh / run.sh）。

示例:
  ./scripts/gen.sh

exit code:
  0     生成成功
  非 0  缺 xcodegen 或 Project.yml 无效（快速失败，详见 stderr）
EOF
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

require_cmd xcodegen
cd "$REPO_ROOT"
xcodegen generate
log "已生成 ${PROJECT_NAME}.xcodeproj"
