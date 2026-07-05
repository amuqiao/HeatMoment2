#!/usr/bin/env bash
# 模拟器 helper：解析默认目标模拟器、拼装 xcodebuild destination、按需启动。
# 可用环境变量 SIM_NAME 覆盖默认机型。
set -euo pipefail

: "${SIM_NAME:=iPhone 17}"
export SIM_NAME

# 输出 xcodebuild 用的 destination 字符串
sim_destination() {
  echo "platform=iOS Simulator,name=${SIM_NAME}"
}

# 找到目标模拟器 UDID 并确保已启动，回显 UDID
sim_boot() {
  local udid
  udid="$(xcrun simctl list devices available | grep -m1 "${SIM_NAME} (" | grep -oE '[0-9A-Fa-f-]{36}' || true)"
  [ -z "${udid}" ] && err "未找到可用模拟器：${SIM_NAME}（用 SIM_NAME=... 覆盖，或 xcrun simctl list 查看）"
  xcrun simctl boot "${udid}" >/dev/null 2>&1 || true   # 已启动会返回非零，忽略
  echo "${udid}"
}
