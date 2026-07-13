#!/usr/bin/env bash
# 清理：删除 DerivedData 与生成的 .xcodeproj（靠 gen.sh 重建）。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

usage() {
  cat <<'EOF'
clean.sh — 清理构建产物：删除 DerivedData 与生成的 HeatMoment.xcodeproj

用法:
  ./scripts/clean.sh [-h|--help]

参数:
  无        删除 DerivedData/ 与 HeatMoment.xcodeproj/

环境变量:
  无

副作用:
  删除 DerivedData 与 HeatMoment.xcodeproj（二者均可重建：工程用 gen.sh、产物用
  build/run 重新生成）。不动 Sources/Tests/Project.yml 等入库文件。

不负责:
  清理模拟器已安装的 App 或应用容器数据（用 xcrun simctl 自行处理）。

示例:
  ./scripts/clean.sh && ./scripts/gen.sh

exit code:
  0     清理完成（目标不存在也视为成功）
  非 0  删除失败（如权限，快速失败）
EOF
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
require_no_args "./scripts/clean.sh" "$@"

cd "$REPO_ROOT"
rm -rf DerivedData "${PROJECT_NAME}.xcodeproj"
log "已清理 DerivedData 与 ${PROJECT_NAME}.xcodeproj"
