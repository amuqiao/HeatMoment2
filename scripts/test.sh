#!/usr/bin/env bash
# 运行测试：--unit（单元）/ --ui（界面）/ --all（默认）。工程不存在时先 gen。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
source "$DIR/lib/sim.sh"

usage() {
  cat <<'EOF'
test.sh — 运行 XCTest（单元）/ XCUITest（界面）

用法:
  ./scripts/test.sh [--unit|--ui|--all] [--only XCTestIdentifier]... [-h|--help]

参数:
  --unit   仅单元测试（MoodmentsTests）
  --ui     仅界面测试（MoodmentsUITests）
  --all    单元 + 界面（默认）
  --only   定向运行 XCTest 标识，可重复；不能与 --unit/--ui/--all 混用；
           格式用 Xcode 原生
           Target[/Class[/testMethod]]，例如 MoodmentsTests/MultiTagFilterTests

环境变量:
  SIM_NAME  覆盖目标模拟器（默认 iPhone 17，见 lib/sim.sh）

副作用:
  写 DerivedData、启动模拟器跑测试；工程不存在时先自动调 gen.sh；不改工作区源码。

不负责:
  lint / 构建打包（见 lint.sh / build.sh）；一条龙验证见 verify.sh。

示例:
  ./scripts/test.sh --unit
  SIM_NAME='iPhone 16 Pro' ./scripts/test.sh --ui
  ./scripts/test.sh --only MoodmentsTests/MultiTagFilterTests
  ./scripts/test.sh --only MoodmentsUITests/TitleCollapseFilterUITests/testFilterSheetDoesNotAutoDismissAfterChoosing

exit code:
  0     测试通过（含 XCTSkip 的跳过用例，如 StoreKit 环境缺失）
  非 0  测试失败或未知参数（快速失败，详见输出）
EOF
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

MODE="--all"
MODE_WAS_SET=false
ONLY_TESTS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --unit|--ui|--all)
      [ "$MODE_WAS_SET" = false ] || err "只能指定一个测试模式（--unit|--ui|--all）"
      MODE="$1"
      MODE_WAS_SET=true
      ;;
    --only)
      shift
      [ "$#" -gt 0 ] || err "缺少 --only 的 XCTestIdentifier"
      case "$1" in
        -*) err "缺少 --only 的 XCTestIdentifier" ;;
      esac
      ONLY_TESTS+=("$1")
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "未知参数：$1（用 --unit|--ui|--all 或 --only XCTestIdentifier）"
      ;;
  esac
  shift
done

if [ "${#ONLY_TESTS[@]}" -gt 0 ] && [ "$MODE_WAS_SET" = true ]; then
  err "--only 已包含 XCTest target，不能与 --unit/--ui/--all 混用"
fi

require_cmd xcodebuild
cd "$REPO_ROOT"
[ -d "${PROJECT_NAME}.xcodeproj" ] || "$DIR/gen.sh"

ARGS=()
if [ "${#ONLY_TESTS[@]}" -gt 0 ]; then
  for identifier in "${ONLY_TESTS[@]}"; do
    ARGS+=("-only-testing:${identifier}")
  done
else
  case "$MODE" in
    --unit) ARGS+=(-only-testing:MoodmentsTests) ;;
    --ui)   ARGS+=(-only-testing:MoodmentsUITests) ;;
    --all)  ;;
  esac
fi

if [ "${#ONLY_TESTS[@]}" -gt 0 ]; then
  log "测试 ${PROJECT_NAME}（定向 ${ONLY_TESTS[*]}，${SIM_NAME}）"
else
  log "测试 ${PROJECT_NAME}（${MODE}，${SIM_NAME}）"
fi
set -o pipefail
xcodebuild test \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "${PROJECT_NAME}" \
  -destination "$(sim_destination)" \
  "${ARGS[@]+"${ARGS[@]}"}" \
  CODE_SIGNING_ALLOWED=NO | pretty
log "测试通过"
