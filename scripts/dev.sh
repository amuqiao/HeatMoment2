#!/usr/bin/env bash
# 本地开发统一入口：路由常用脚本，并提供模拟器/App 状态与轻量生命周期命令。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"
source "$DIR/lib/sim.sh"

BUNDLE_ID="com.heatmoment.app"

usage() {
  cat <<'EOF'
dev.sh — 本地开发统一入口：路由构建、运行、测试、清理与模拟器 App 操作

用法:
  ./scripts/dev.sh <command> [args]
  ./scripts/dev.sh [-h|--help]

参数:
  doctor       检查本地工具链、工程文件与目标模拟器
  status       查看目标模拟器状态与 App 安装状态
  run          构建、安装并启动 App（等价于 run.sh）
  start        run 的别名
  launch       只启动已安装 App，不重新构建
  stop         只停止模拟器里的 App，不关闭 Simulator.app
  restart      停止 App 后重新 run
  build        只构建（转发 build.sh）
  test         跑测试（转发 test.sh，支持 --unit|--ui|--all 与 --only）
  lint         跑代码规范检查（转发 lint.sh，支持 --fix）
  verify       一条龙验证（转发 verify.sh）
  gen          生成 Xcode 工程（转发 gen.sh）
  clean        清理构建产物和生成工程（转发 clean.sh）

环境变量:
  SIM_NAME     覆盖目标模拟器（默认 iPhone 17，见 lib/sim.sh）

副作用:
  run/start/restart/build/test/verify 会写 DerivedData，run/start/restart 会安装并启动 App；
  launch 会启动 Simulator.app 并启动已安装 App；stop 会 terminate 模拟器中的 App；
  clean 会删除 DerivedData 与 HeatMoment.xcodeproj；status/doctor 不改工作区源码。

不负责:
  真机部署 / 签名分发；安装 Xcode 或 Homebrew（见 bootstrap.sh）。

示例:
  ./scripts/dev.sh status
  ./scripts/dev.sh run
  ./scripts/dev.sh test --unit
  ./scripts/dev.sh test --only HeatMomentTests/MultiTagFilterTests
  SIM_NAME='iPhone 16 Pro' ./scripts/dev.sh restart

exit code:
  0     命令完成
  非 0  未知命令、缺工具、找不到目标模拟器、构建/测试/安装/启动失败（快速失败）
EOF
}

doctor() {
  require_cmd xcodebuild
  require_cmd xcrun
  log "Xcode: $(xcodebuild -version | head -1)"
  log "xcrun: $(xcrun --find simctl)"
  [ -f "$REPO_ROOT/Project.yml" ] || err "未找到 Project.yml"
  if [ -d "$REPO_ROOT/${PROJECT_NAME}.xcodeproj" ]; then
    log "工程文件：${PROJECT_NAME}.xcodeproj 已存在"
  else
    warn "工程文件：${PROJECT_NAME}.xcodeproj 不存在，build/run/test 会自动调用 gen.sh"
  fi

  local udid
  udid="$(sim_udid)"
  log "目标模拟器：${SIM_NAME}（${udid}，$(sim_state "${udid}")）"
}

status() {
  require_cmd xcrun
  local udid
  udid="$(sim_udid)"
  log "目标模拟器：${SIM_NAME}"
  log "UDID：${udid}"
  log "状态：$(sim_state "${udid}")"
  if sim_app_installed "${udid}" "${BUNDLE_ID}"; then
    log "App：已安装 ${BUNDLE_ID}"
  else
    log "App：未安装 ${BUNDLE_ID}"
  fi
}

launch_app() {
  require_cmd xcrun
  local udid
  udid="$(sim_boot)"
  sim_app_installed "${udid}" "${BUNDLE_ID}" || err "App 未安装：${BUNDLE_ID}（先运行 ./scripts/dev.sh run）"
  open -a Simulator || true
  xcrun simctl launch "${udid}" "${BUNDLE_ID}"
  log "已启动 ${PROJECT_NAME}"
}

stop_app() {
  require_cmd xcrun
  local udid
  local output
  udid="$(sim_udid)"
  if ! sim_app_installed "${udid}" "${BUNDLE_ID}"; then
    log "App 未安装，无需停止"
    return 0
  fi
  if output="$(xcrun simctl terminate "${udid}" "${BUNDLE_ID}" 2>&1)"; then
    log "已停止 ${PROJECT_NAME}"
  elif printf '%s\n' "${output}" | grep -q 'found nothing to terminate'; then
    log "App 未运行，无需停止"
  else
    printf '%s\n' "${output}" >&2
    exit 1
  fi
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") usage; err "缺少命令（用 ./scripts/dev.sh -h 查看）" ;;
esac

COMMAND="$1"
shift

case "$COMMAND" in
  doctor)
    require_no_args "./scripts/dev.sh" "$@"
    doctor
    ;;
  status)
    require_no_args "./scripts/dev.sh" "$@"
    status
    ;;
  run|start) "$DIR/run.sh" "$@" ;;
  launch)
    require_no_args "./scripts/dev.sh" "$@"
    launch_app
    ;;
  stop)
    require_no_args "./scripts/dev.sh" "$@"
    stop_app
    ;;
  restart)
    require_no_args "./scripts/dev.sh" "$@"
    stop_app
    "$DIR/run.sh"
    ;;
  build)   "$DIR/build.sh" "$@" ;;
  test)    "$DIR/test.sh" "$@" ;;
  lint)    "$DIR/lint.sh" "$@" ;;
  verify)  "$DIR/verify.sh" "$@" ;;
  gen)     "$DIR/gen.sh" "$@" ;;
  clean)   "$DIR/clean.sh" "$@" ;;
  *)       err "未知命令：${COMMAND}（用 ./scripts/dev.sh -h 查看）" ;;
esac
