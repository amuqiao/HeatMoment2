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

# 找到目标模拟器 UDID，回显 UDID
sim_udid() {
  local udid
  udid="$(xcrun simctl list devices available | grep -m1 "${SIM_NAME} (" | grep -oE '[0-9A-Fa-f-]{36}' || true)"
  [ -z "${udid}" ] && err "未找到可用模拟器：${SIM_NAME}（用 SIM_NAME=... 覆盖，或 xcrun simctl list 查看）"
  echo "${udid}"
}

# 输出目标模拟器状态
sim_state() {
  local udid="$1"
  local state
  state="$(xcrun simctl list devices available | grep "${udid}" | grep -oE '\((Booted|Shutdown|Creating|Booting|Shutting Down)\)' | tr -d '()' | head -1 || true)"
  [ -z "${state}" ] && err "未找到模拟器状态：${udid}"
  echo "${state}"
}

# 判断 App 是否已安装到目标模拟器
sim_app_installed() {
  local udid="$1"
  local bundle_id="$2"
  xcrun simctl get_app_container "${udid}" "${bundle_id}" app >/dev/null 2>&1
}

# 找到目标模拟器 UDID 并确保已启动，回显 UDID
sim_boot() {
  local udid
  udid="$(sim_udid)"
  xcrun simctl boot "${udid}" >/dev/null 2>&1 || true   # 已启动会返回非零，忽略
  echo "${udid}"
}
